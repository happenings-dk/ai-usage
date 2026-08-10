import Foundation

/// User-owned configuration for the optional internet relay.
struct RelayConfiguration: Codable, Equatable, Sendable {
    let baseURL: URL
    let channel: String
    let token: String

    private enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case channel
        case token
    }

    var publisherURL: URL? {
        endpointURL(role: "publisher")
    }

    var subscriberURL: URL? {
        endpointURL(role: "subscriber")
    }

    var snapshotURL: URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let scheme = components.scheme
        components.scheme = scheme == "http" ? "http" : "https"
        components.path = "/v1/channels/\(channel)/snapshot"
        components.query = nil
        return components.url
    }

    static func load() -> RelayConfiguration? {
        let file = URL(fileURLWithPath: NSString(string: "~/.ai-usage/relay.json").expandingTildeInPath)
        guard let data = try? Data(contentsOf: file) else {
            return nil
        }
        guard let configuration = try? JSONDecoder().decode(RelayConfiguration.self, from: data),
              configuration.isValid else {
            return nil
        }
        return configuration
    }

    private var isValid: Bool {
        guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              baseURL.host != nil,
              !token.isEmpty,
              !channel.isEmpty else {
            return false
        }
        return channel.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }

    private func endpointURL(role: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let scheme = components.scheme
        components.scheme = scheme == "http" ? "ws" : "wss"
        components.path = "/v1/channels/\(channel)"
        components.queryItems = [URLQueryItem(name: "role", value: role)]
        return components.url
    }
}

/// Maintains the Mac's outbound publisher connection to an optional relay.
actor RelayClient {
    static let shared = RelayClient()

    private var connection: RelayWebSocketConnection?
    private var activePublisherURL: URL?

    func publish(_ data: Data, using configuration: RelayConfiguration) async {
        guard let publisherURL = configuration.publisherURL else {
            return
        }

        do {
            let connection = try await makeConnectionIfNeeded(url: publisherURL, token: configuration.token)
            try await connection.ping()
            try await connection.task.send(.data(data))
        } catch {
            Self.log("publish failed: \(error.localizedDescription)")
            disconnect()
            do {
                let replacement = try await makeConnectionIfNeeded(url: publisherURL, token: configuration.token)
                try await replacement.ping()
                try await replacement.task.send(.data(data))
            } catch {
                Self.log("publish retry failed: \(error.localizedDescription)")
                disconnect()
            }
        }
    }

    private func makeConnectionIfNeeded(url: URL, token: String) async throws -> RelayWebSocketConnection {
        if let connection, activePublisherURL == url {
            return connection
        }

        disconnect()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: BridgeProtocol.authorizationHeader)
        request.setValue(BridgeProtocol.webSocketSubprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let delegate = RelayWebSocketDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let newTask = session.webSocketTask(with: request)
        newTask.maximumMessageSize = 2 * 1024 * 1024
        let newConnection = RelayWebSocketConnection(session: session, task: newTask, delegate: delegate)
        connection = newConnection
        activePublisherURL = url
        newTask.resume()
        try await delegate.waitUntilOpen()
        return newConnection
    }

    private func disconnect() {
        connection?.task.cancel(with: .goingAway, reason: nil)
        connection?.session.invalidateAndCancel()
        connection = nil
        activePublisherURL = nil
    }

    private static func log(_ message: String) {
        let directory = URL(fileURLWithPath: NSString(string: "~/.ai-usage").expandingTildeInPath)
        let file = directory.appendingPathComponent("relay.log")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        if FileManager.default.fileExists(atPath: file.path),
           let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}

/// Retains the delegate-backed URLSession for the lifetime of one publisher socket.
private final class RelayWebSocketConnection: @unchecked Sendable {
    let session: URLSession
    let task: URLSessionWebSocketTask
    let delegate: RelayWebSocketDelegate

    init(session: URLSession, task: URLSessionWebSocketTask, delegate: RelayWebSocketDelegate) {
        self.session = session
        self.task = task
        self.delegate = delegate
    }

    func ping() async throws {
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Bridges URLSession's WebSocket-open callback to structured concurrency.
private final class RelayWebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func waitUntilOpen() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            if let result {
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard `protocol` == BridgeProtocol.webSocketSubprotocol else {
            finish(.failure(RelayClientError.unsupportedProtocol))
            return
        }
        finish(.success(()))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard self.result == nil else {
            return
        }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }
}

private enum RelayClientError: LocalizedError {
    case unsupportedProtocol

    var errorDescription: String? {
        "The relay didn't negotiate the AI Usage WebSocket protocol."
    }
}
