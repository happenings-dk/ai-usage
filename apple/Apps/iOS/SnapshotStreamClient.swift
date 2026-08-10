import Foundation
import Network

/// Receives versioned snapshots over local Network.framework or remote URLSession WebSockets.
actor SnapshotStreamClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private var localConnection: NWConnection?

    /// Connects and receives messages until cancellation or transport failure.
    func run(
        pairing: BridgePairingPayload,
        localEndpoint: NWEndpoint?,
        onSnapshot: @escaping @Sendable (SnapshotEnvelope) async -> Void
    ) async throws {
        disconnect()
        if let localEndpoint {
#if DEBUG
            print("AI Usage transport: Bonjour")
#endif
            try await runLocal(endpoint: localEndpoint, pairing: pairing, onSnapshot: onSnapshot)
        } else if pairing.relayURL == nil, let directEndpoint = Self.directEndpoint(from: pairing.webSocketURL) {
#if DEBUG
            print("AI Usage transport: direct")
#endif
            try await runLocal(endpoint: directEndpoint, pairing: pairing, onSnapshot: onSnapshot)
        } else {
#if DEBUG
            print("AI Usage transport: relay")
#endif
            try await runRemote(pairing: pairing, onSnapshot: onSnapshot)
        }
    }

    /// Closes every active transport.
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        localConnection?.cancel()
        localConnection = nil
    }

    private func runRemote(
        pairing: BridgePairingPayload,
        onSnapshot: @escaping @Sendable (SnapshotEnvelope) async -> Void
    ) async throws {
        let destinationURL = pairing.relayURL ?? pairing.webSocketURL
        let credential = pairing.relayURL == nil ? pairing.token : (pairing.relayToken ?? pairing.token)
        var request = URLRequest(url: destinationURL)
        request.setValue("Bearer \(credential)", forHTTPHeaderField: BridgeProtocol.authorizationHeader)
        request.setValue(BridgeProtocol.webSocketSubprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.maximumMessageSize = 2 * 1024 * 1024
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
            if webSocketTask === task {
                webSocketTask = nil
            }
        }

        while !Task.isCancelled {
            let message = try await task.receive()
            try await decode(message: message, onSnapshot: onSnapshot)
        }
        throw CancellationError()
    }

    private func runLocal(
        endpoint: NWEndpoint,
        pairing: BridgePairingPayload,
        onSnapshot: @escaping @Sendable (SnapshotEnvelope) async -> Void
    ) async throws {
        let webSocketOptions = NWProtocolWebSocket.Options(.version13)
        webSocketOptions.autoReplyPing = true
        webSocketOptions.maximumMessageSize = 2 * 1024 * 1024
        webSocketOptions.setAdditionalHeaders([
            (BridgeProtocol.authorizationHeader, "Bearer \(pairing.token)")
        ])
        webSocketOptions.setSubprotocols([BridgeProtocol.webSocketSubprotocol])
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        let connection = NWConnection(to: endpoint, using: parameters)
        localConnection = connection
        try await waitUntilReady(connection)
        defer {
            connection.cancel()
            if localConnection === connection {
                localConnection = nil
            }
        }

        while !Task.isCancelled {
            let data = try await receiveMessage(from: connection)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
            await onSnapshot(envelope)
        }
        throw CancellationError()
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ConnectionContinuationGate(continuation: continuation)
            connection.stateUpdateHandler = { state in
                gate.handle(state)
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func receiveMessage(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { data, context, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                   metadata.opcode == .close {
                    continuation.resume(throwing: SnapshotStreamError.closed)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: SnapshotStreamError.emptyMessage)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func decode(
        message: URLSessionWebSocketTask.Message,
        onSnapshot: @escaping @Sendable (SnapshotEnvelope) async -> Void
    ) async throws {
        let data: Data
        switch message {
        case .data(let receivedData):
            data = receivedData
        case .string(let string):
            data = Data(string.utf8)
        @unknown default:
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
        await onSnapshot(envelope)
    }

    private static func directEndpoint(from url: URL) -> NWEndpoint? {
        guard url.scheme == "ws",
              let host = url.host,
              let portValue = url.port,
              let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
            return nil
        }
        return .hostPort(host: NWEndpoint.Host(host), port: port)
    }
}

/// Serializes completion of the one-shot NWConnection readiness continuation.
private final class ConnectionContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func handle(_ state: NWConnection.State) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else {
            return
        }
        switch state {
        case .ready:
            self.continuation = nil
            continuation.resume()
        case .failed(let error):
            self.continuation = nil
            continuation.resume(throwing: error)
        case .cancelled:
            self.continuation = nil
            continuation.resume(throwing: CancellationError())
        default:
            break
        }
    }
}

/// Terminal errors emitted by a live snapshot stream.
private enum SnapshotStreamError: LocalizedError {
    case closed
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .closed:
            "The Mac closed the live connection."
        case .emptyMessage:
            "The Mac sent an empty live update."
        }
    }
}
