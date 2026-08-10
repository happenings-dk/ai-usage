import Foundation

/// Shared constants for the local and remote snapshot transports.
enum BridgeProtocol {
    static let version = 1
    static let bonjourServiceType = "_aiusage._tcp"
    static let webSocketSubprotocol = "ai-usage.v1"
    static let authorizationHeader = "Authorization"
}

/// A versioned message delivered to live snapshot subscribers.
struct SnapshotEnvelope: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let sequence: UInt64
    let snapshot: UsageSnapshot

    init(sequence: UInt64, snapshot: UsageSnapshot) {
        protocolVersion = BridgeProtocol.version
        self.sequence = sequence
        self.snapshot = snapshot
    }
}

/// Everything a phone needs to pair with a Mac bridge.
struct BridgePairingPayload: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let deviceID: String
    let deviceName: String
    let snapshotURL: URL
    let webSocketURL: URL
    let token: String
    let relayURL: URL?
    let relaySnapshotURL: URL?
    let relayChannel: String?
    let relayToken: String?

    init(
        deviceID: String,
        deviceName: String,
        snapshotURL: URL,
        webSocketURL: URL,
        token: String,
        relayURL: URL? = nil,
        relaySnapshotURL: URL? = nil,
        relayChannel: String? = nil,
        relayToken: String? = nil
    ) {
        protocolVersion = BridgeProtocol.version
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.snapshotURL = snapshotURL
        self.webSocketURL = webSocketURL
        self.token = token
        self.relayURL = relayURL
        self.relaySnapshotURL = relaySnapshotURL
        self.relayChannel = relayChannel
        self.relayToken = relayToken
    }

    /// Encodes this payload as a URL-safe string suitable for QR codes.
    func encodedPairingURL() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else {
            return nil
        }

        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "aiusage://pair?payload=\(encoded)")
    }

    /// Decodes a pairing URL created by `encodedPairingURL()`.
    static func decode(from url: URL) throws -> BridgePairingPayload {
        guard url.scheme == "aiusage",
              url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "payload" })?.value else {
            throw BridgePairingError.invalidURL
        }

        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))

        guard let data = Data(base64Encoded: base64) else {
            throw BridgePairingError.invalidPayload
        }

        let payload = try JSONDecoder().decode(BridgePairingPayload.self, from: data)
        guard payload.protocolVersion == BridgeProtocol.version else {
            throw BridgePairingError.unsupportedVersion(payload.protocolVersion)
        }
        return payload
    }
}

/// Errors produced while reading pairing data.
enum BridgePairingError: LocalizedError, Equatable {
    case invalidURL
    case invalidPayload
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "This isn't an AI Usage pairing link."
        case .invalidPayload:
            "The pairing link is damaged or incomplete."
        case .unsupportedVersion(let version):
            "Pairing version \(version) isn't supported by this app."
        }
    }
}
