# AI Usage Relay

This Cloudflare Worker keeps one hibernatable Durable Object per private channel. The Mac publishes complete, versioned snapshots over an authenticated WebSocket; phones subscribe to that channel and receive the most recent snapshot immediately. No inbound connection to the Mac is required.

## Local development

```sh
npm install
printf '%s' 'replace-with-a-long-random-token' | npx wrangler secret put RELAY_TOKEN
npm run check
npm run dev
```

The public health endpoint is `GET /health`. Every channel route requires `Authorization: Bearer <RELAY_TOKEN>` and the WebSocket subprotocol `ai-usage.v1`.

An authenticated `GET /v1/channels/<channel>/devices` returns connection counts plus the last APNs status/reason for diagnostics; raw APNs tokens are never exposed.

## Deploy

```sh
npx wrangler login
npx wrangler secret put RELAY_TOKEN
npm run deploy
```

Then create `~/.ai-usage/relay.json` on the Mac:

```json
{
  "base_url": "https://ai-usage-relay.<account>.workers.dev",
  "channel": "rasmus-mac",
  "token": "the-same-long-random-token"
}
```

Use a unique random token and keep the file private (`chmod 600 ~/.ai-usage/relay.json`). Restart AI Usage Menu, open Settings, and scan the new pairing QR on the phone.

The included setup command securely generates a token, installs it as a Worker secret, and writes the matching mode-0600 Mac configuration without printing the token:

```sh
chmod +x configure-relay.sh
./configure-relay.sh https://ai-usage-relay.<account>.workers.dev rasmus-mac
```

## APNs background refresh

Foreground WebSockets are real-time. iOS can suspend network connections in the background, so the relay can additionally send a throttled silent notification. Configure these Worker secrets:

```sh
npx wrangler secret put APNS_TEAM_ID
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_BUNDLE_ID
npx wrangler secret put APNS_PRIVATE_KEY
```

Set `APNS_ENVIRONMENT` to `sandbox` while installing development builds, or leave it unset/use `production` for distributed builds. The APNs key must be the full PKCS#8 `.p8` text. Silent pushes are opportunistic: iOS decides when to launch the app, and this relay intentionally sends at most one every 20 minutes per channel.
