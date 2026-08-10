import { DurableObject } from "cloudflare:workers";

const PROTOCOL = "ai-usage.v1";
const MAX_MESSAGE_BYTES = 2 * 1024 * 1024;
const MINIMUM_PUSH_INTERVAL_MS = 20 * 60 * 1000;

interface Env {
  CHANNELS: DurableObjectNamespace<UsageChannel>;
  RELAY_TOKEN: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_ID?: string;
  APNS_BUNDLE_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_ENVIRONMENT?: "production" | "sandbox";
}

interface SocketAttachment {
  role: "publisher" | "subscriber";
}

interface SnapshotEnvelope {
  protocolVersion: number;
  sequence: number;
  snapshot: unknown;
}

interface PushResult {
  status: number;
  reason: string | null;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return Response.json({ ok: true, protocol: PROTOCOL });
    }

    const route = parseChannelRoute(url.pathname);
    if (!route) {
      return jsonError(404, "not_found");
    }
    if (!(await isAuthorized(request, env.RELAY_TOKEN))) {
      return jsonError(401, "unauthorized");
    }

    const id = env.CHANNELS.idFromName(route.channel);
    const stub = env.CHANNELS.get(id);
    const forwarded = new Request(request);
    forwarded.headers.set("X-AI-Usage-Action", route.action);

    if (route.action === "socket") {
      const role = url.searchParams.get("role");
      if (role !== "publisher" && role !== "subscriber") {
        return jsonError(400, "invalid_role");
      }
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return jsonError(426, "websocket_required");
      }
      if (!requestedProtocols(request).includes(PROTOCOL)) {
        return jsonError(426, "unsupported_protocol");
      }
      forwarded.headers.set("X-AI-Usage-Role", role);
    }

    return stub.fetch(forwarded);
  },
} satisfies ExportedHandler<Env>;

export class UsageChannel extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const action = request.headers.get("X-AI-Usage-Action");
    switch (action) {
      case "socket":
        return this.openSocket(request);
      case "snapshot":
        return this.getSnapshot();
      case "devices":
        return this.registerDevice(request);
      default:
        return jsonError(404, "not_found");
    }
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment?.role !== "publisher") {
      socket.close(1008, "Subscribers are read-only");
      return;
    }

    const byteLength = typeof message === "string" ? new TextEncoder().encode(message).byteLength : message.byteLength;
    if (byteLength > MAX_MESSAGE_BYTES) {
      socket.close(1009, "Snapshot is too large");
      return;
    }

    const encoded = typeof message === "string" ? message : new TextDecoder().decode(message);
    const envelope = decodeEnvelope(encoded);
    if (!envelope) {
      socket.close(1007, "Invalid snapshot envelope");
      return;
    }

    await this.ctx.storage.put("latestEnvelope", encoded);
    for (const subscriber of this.ctx.getWebSockets("subscriber")) {
      try {
        subscriber.send(encoded);
      } catch {
        subscriber.close(1011, "Delivery failed");
      }
    }

    this.ctx.waitUntil(this.sendBackgroundPushesIfDue());
  }

  webSocketClose(_socket: WebSocket, _code: number, _reason: string): void {
    // The runtime completes the close handshake for current compatibility dates.
  }

  private async openSocket(request: Request): Promise<Response> {
    const role = request.headers.get("X-AI-Usage-Role");
    if (role !== "publisher" && role !== "subscriber") {
      return jsonError(400, "invalid_role");
    }

    const [client, server] = Object.values(new WebSocketPair());
    server.serializeAttachment({ role } satisfies SocketAttachment);
    this.ctx.acceptWebSocket(server, [role]);

    if (role === "subscriber") {
      const latest = await this.ctx.storage.get<string>("latestEnvelope");
      if (latest) {
        server.send(latest);
      }
    }

    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: { "Sec-WebSocket-Protocol": PROTOCOL },
    });
  }

  private async getSnapshot(): Promise<Response> {
    const latest = await this.ctx.storage.get<string>("latestEnvelope");
    if (!latest) {
      return jsonError(404, "snapshot_unavailable");
    }
    const envelope = decodeEnvelope(latest);
    if (!envelope) {
      return jsonError(500, "snapshot_invalid");
    }
    return Response.json(envelope.snapshot, {
      headers: { "Cache-Control": "no-store" },
    });
  }

  private async registerDevice(request: Request): Promise<Response> {
    if (request.method === "GET") {
      const devices = await this.ctx.storage.get<string[]>("devices") ?? [];
      const lastPushAttempt = await this.ctx.storage.get<number>("lastPushAttempt") ?? null;
      const lastPushResults = await this.ctx.storage.get<PushResult[]>("lastPushResults") ?? [];
      return Response.json({
        count: devices.length,
        publishers: this.ctx.getWebSockets("publisher").length,
        subscribers: this.ctx.getWebSockets("subscriber").length,
        lastPushAttempt,
        lastPushResults,
      });
    }
    if (request.method !== "POST") {
      return jsonError(405, "method_not_allowed");
    }
    const body = await request.json<{ deviceToken?: unknown; platform?: unknown }>().catch(() => null);
    if (!body || body.platform !== "ios" || typeof body.deviceToken !== "string" || !/^(?:[a-fA-F0-9]{2}){16,200}$/.test(body.deviceToken)) {
      return jsonError(400, "invalid_device");
    }

    const devices = new Set(await this.ctx.storage.get<string[]>("devices") ?? []);
    devices.add(body.deviceToken.toLowerCase());
    await this.ctx.storage.put("devices", [...devices].slice(-16));
    return Response.json({ registered: true });
  }

  private async sendBackgroundPushesIfDue(): Promise<void> {
    const now = Date.now();
    const lastPush = await this.ctx.storage.get<number>("lastPush") ?? 0;
    if (now - lastPush < MINIMUM_PUSH_INTERVAL_MS) {
      return;
    }
    const devices = await this.ctx.storage.get<string[]>("devices") ?? [];
    if (devices.length === 0 || !hasApnsConfiguration(this.env)) {
      return;
    }

    const jwt = await createApnsJwt(this.env);
    const invalidDevices = new Set<string>();
    const results = await Promise.all(devices.map(async (deviceToken): Promise<PushResult> => {
      const host = this.env.APNS_ENVIRONMENT === "sandbox"
        ? "api.sandbox.push.apple.com"
        : "api.push.apple.com";
      const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
        method: "POST",
        headers: {
          Authorization: `bearer ${jwt}`,
          "Content-Type": "application/json",
          "apns-priority": "5",
          "apns-push-type": "background",
          "apns-topic": this.env.APNS_BUNDLE_ID!,
        },
        body: JSON.stringify({ aps: { "content-available": 1 } }),
      });
      if (response.status === 410) {
        invalidDevices.add(deviceToken);
      }
      const responseBody = await response.json<{ reason?: string }>().catch(() => null);
      return { status: response.status, reason: responseBody?.reason ?? null };
    }));
    await this.ctx.storage.put("lastPushAttempt", now);
    await this.ctx.storage.put("lastPushResults", results);
    if (results.some((result) => result.status === 200)) {
      await this.ctx.storage.put("lastPush", now);
    }
    if (invalidDevices.size > 0) {
      await this.ctx.storage.put("devices", devices.filter((device) => !invalidDevices.has(device)));
    }
  }
}

function parseChannelRoute(pathname: string): { channel: string; action: "socket" | "snapshot" | "devices" } | null {
  const match = pathname.match(/^\/v1\/channels\/([A-Za-z0-9_-]{1,64})(?:\/(snapshot|devices))?$/);
  if (!match) {
    return null;
  }
  return {
    channel: match[1],
    action: match[2] === "snapshot" || match[2] === "devices" ? match[2] : "socket",
  };
}

function requestedProtocols(request: Request): string[] {
  return (request.headers.get("Sec-WebSocket-Protocol") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

function decodeEnvelope(encoded: string): SnapshotEnvelope | null {
  try {
    const value = JSON.parse(encoded) as Partial<SnapshotEnvelope>;
    if (value.protocolVersion !== 1 || !Number.isSafeInteger(value.sequence) || value.snapshot === undefined) {
      return null;
    }
    return value as SnapshotEnvelope;
  } catch {
    return null;
  }
}

async function isAuthorized(request: Request, expectedToken: string): Promise<boolean> {
  const provided = request.headers.get("Authorization")?.match(/^Bearer (.+)$/)?.[1];
  if (!provided || !expectedToken) {
    return false;
  }
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(provided)),
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(expectedToken)),
  ]);
  const left = new Uint8Array(providedHash);
  const right = new Uint8Array(expectedHash);
  let difference = left.length ^ right.length;
  for (let index = 0; index < Math.min(left.length, right.length); index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function hasApnsConfiguration(env: Env): env is Env & Required<Pick<Env, "APNS_TEAM_ID" | "APNS_KEY_ID" | "APNS_BUNDLE_ID" | "APNS_PRIVATE_KEY">> {
  return Boolean(env.APNS_TEAM_ID && env.APNS_KEY_ID && env.APNS_BUNDLE_ID && env.APNS_PRIVATE_KEY);
}

async function createApnsJwt(env: Env & Required<Pick<Env, "APNS_TEAM_ID" | "APNS_KEY_ID" | "APNS_BUNDLE_ID" | "APNS_PRIVATE_KEY">>): Promise<string> {
  const header = base64Url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = base64Url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) }));
  const signingInput = `${header}.${claims}`;
  const keyData = decodePem(env.APNS_PRIVATE_KEY);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function decodePem(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const bytes = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
  return bytes.buffer;
}

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function jsonError(status: number, error: string): Response {
  return Response.json({ error }, { status });
}
