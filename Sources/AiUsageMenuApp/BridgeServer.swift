import Foundation
import Network

/// Serves snapshots over authenticated HTTP and broadcasts updates over WebSocket.
///
/// All mutable state is confined to `queue`; the unchecked conformance bridges
/// Network.framework's dispatch callbacks into Swift 6 strict concurrency.
final class BridgeServer: @unchecked Sendable {
    static let shared = BridgeServer()

    private let queue = DispatchQueue(label: "ai-usage.bridge-server")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private var currentSnapshotData: Data?
    private var currentEnvelopeData: Data?
    private var httpListener: NWListener?
    private var webSocketListener: NWListener?
    private var webSocketClients: [UUID: NWConnection] = [:]
    private var httpPort: UInt16 = 0
    private var webSocketPort: UInt16 = 0
    private var sequence: UInt64 = 0

    let deviceID: String
    let token: String

    private init() {
        deviceID = Self.loadOrCreateValue(named: "bridge-device-id", generate: { UUID().uuidString.lowercased() })
        token = Self.loadOrCreateValue(named: "bridge-token", generate: {
            UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        })
    }

    var isRunning: Bool {
        queue.sync { httpListener != nil && webSocketListener != nil }
    }

    var bridgeURL: URL? {
        endpointURL(scheme: "http", port: queue.sync { httpPort }, path: "/snapshot.json")
    }

    var localhostURL: URL? {
        endpointURL(scheme: "http", host: "127.0.0.1", port: queue.sync { httpPort }, path: "/snapshot.json")
    }

    var webSocketURL: URL? {
        endpointURL(scheme: "ws", port: queue.sync { webSocketPort }, path: "/live")
    }

    var pairingPayload: BridgePairingPayload? {
        guard let localSnapshotURL = bridgeURL, let webSocketURL else {
            return nil
        }
        let relay = RelayConfiguration.load()
        return BridgePairingPayload(
            deviceID: deviceID,
            deviceName: Host.current().localizedName ?? "Mac",
            snapshotURL: relay?.snapshotURL ?? localSnapshotURL,
            webSocketURL: webSocketURL,
            token: token,
            relayURL: relay?.subscriberURL,
            relaySnapshotURL: relay?.snapshotURL,
            relayChannel: relay?.channel,
            relayToken: relay?.token
        )
    }

    /// Starts the HTTP and WebSocket listeners if needed.
    func start() {
        queue.async { [weak self] in
            self?.startListeners()
        }
    }

    /// Replaces the current snapshot and broadcasts it to every live client.
    func update(snapshot: UsageSnapshot) {
        queue.async { [weak self] in
            self?.publish(snapshot: snapshot)
        }
    }

    private func startListeners() {
        guard httpListener == nil, webSocketListener == nil else {
            return
        }

        do {
            let httpListener = try NWListener(using: .tcp, on: .any)
            httpListener.stateUpdateHandler = { [weak self] state in
                self?.handleHTTPListenerState(state)
            }
            httpListener.newConnectionHandler = { [weak self] connection in
                self?.acceptHTTP(connection)
            }
            self.httpListener = httpListener
            httpListener.start(queue: queue)

            let webSocketOptions = NWProtocolWebSocket.Options(.version13)
            webSocketOptions.autoReplyPing = true
            webSocketOptions.maximumMessageSize = 2 * 1024 * 1024
            let token = self.token
            webSocketOptions.setClientRequestHandler(queue) { subprotocols, headers in
                let isAuthorized = Self.isAuthorized(headers: headers, token: token)
                let selectedProtocol = subprotocols.contains(BridgeProtocol.webSocketSubprotocol)
                    ? BridgeProtocol.webSocketSubprotocol
                    : nil
                return NWProtocolWebSocket.Response(
                    status: isAuthorized ? .accept : .reject,
                    subprotocol: selectedProtocol
                )
            }

            let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
            parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
            let webSocketListener = try NWListener(using: parameters, on: .any)
            let txtRecord = NWTXTRecord([
                "deviceID": deviceID,
                "version": String(BridgeProtocol.version)
            ])
            webSocketListener.service = NWListener.Service(
                name: Host.current().localizedName,
                type: BridgeProtocol.bonjourServiceType,
                txtRecord: txtRecord
            )
            webSocketListener.stateUpdateHandler = { [weak self] state in
                self?.handleWebSocketListenerState(state)
            }
            webSocketListener.newConnectionHandler = { [weak self] connection in
                self?.acceptWebSocket(connection)
            }
            self.webSocketListener = webSocketListener
            webSocketListener.start(queue: queue)
        } catch {
            Self.log("bridge start error: \(error)")
            stopListeners()
        }
    }

    private func handleHTTPListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            httpPort = httpListener?.port?.rawValue ?? 0
            Self.log("HTTP bridge ready on \(httpPort)")
        case .failed(let error):
            Self.log("HTTP bridge failed: \(error)")
            stopListeners()
        case .cancelled:
            httpPort = 0
        default:
            break
        }
    }

    private func handleWebSocketListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            webSocketPort = webSocketListener?.port?.rawValue ?? 0
            Self.log("WebSocket bridge ready on \(webSocketPort)")
        case .failed(let error):
            Self.log("WebSocket bridge failed: \(error)")
            stopListeners()
        case .cancelled:
            webSocketPort = 0
        default:
            break
        }
    }

    private func acceptHTTP(_ connection: NWConnection) {
        let connectionID = UUID()
        connection.stateUpdateHandler = { [weak connection] state in
            if case .failed = state {
                connection?.cancel()
            }
        }
        connection.start(queue: queue)
        receiveHTTPRequest(connection, connectionID: connectionID, buffered: Data())
    }

    private func receiveHTTPRequest(_ connection: NWConnection, connectionID: UUID, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = buffered
            if let data {
                requestData.append(data)
            }
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete || error != nil {
                let response = self.response(for: requestData)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                self.receiveHTTPRequest(connection, connectionID: connectionID, buffered: requestData)
            }
        }
    }

    private func acceptWebSocket(_ connection: NWConnection) {
        let id = UUID()
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleWebSocketState(state, id: id, connection: connection)
        }
        connection.start(queue: queue)
    }

    private func handleWebSocketState(_ state: NWConnection.State, id: UUID, connection: NWConnection) {
        switch state {
        case .ready:
            webSocketClients[id] = connection
            if let currentEnvelopeData {
                send(currentEnvelopeData, to: connection, id: id)
            }
            receiveWebSocketMessage(from: connection, id: id)
        case .failed(let error):
            Self.log("WebSocket client failed: \(error)")
            removeWebSocketClient(id)
        case .cancelled:
            removeWebSocketClient(id)
        default:
            break
        }
    }

    private func receiveWebSocketMessage(from connection: NWConnection, id: UUID) {
        connection.receiveMessage { [weak self] _, context, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                Self.log("WebSocket receive failed: \(error)")
                self.removeWebSocketClient(id)
                return
            }
            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                self.removeWebSocketClient(id)
                return
            }
            self.receiveWebSocketMessage(from: connection, id: id)
        }
    }

    private func publish(snapshot: UsageSnapshot) {
        guard let snapshotData = try? encoder.encode(snapshot) else {
            return
        }
        sequence &+= 1
        guard let envelopeData = try? encoder.encode(SnapshotEnvelope(sequence: sequence, snapshot: snapshot)) else {
            return
        }
        currentSnapshotData = snapshotData
        currentEnvelopeData = envelopeData
        for (id, connection) in webSocketClients {
            send(envelopeData, to: connection, id: id)
        }
        if let relay = RelayConfiguration.load() {
            Task {
                await RelayClient.shared.publish(envelopeData, using: relay)
            }
        }
    }

    private func send(_ data: Data, to connection: NWConnection, id: UUID) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(
            identifier: "snapshot-\(sequence)",
            metadata: [metadata]
        )
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            guard error != nil else {
                return
            }
            self?.removeWebSocketClient(id)
        })
    }

    private func removeWebSocketClient(_ id: UUID) {
        webSocketClients.removeValue(forKey: id)?.cancel()
    }

    private func stopListeners() {
        httpListener?.cancel()
        webSocketListener?.cancel()
        httpListener = nil
        webSocketListener = nil
        httpPort = 0
        webSocketPort = 0
        for connection in webSocketClients.values {
            connection.cancel()
        }
        webSocketClients.removeAll()
    }

    private func response(for requestData: Data) -> Data {
        guard let request = String(data: requestData, encoding: .utf8) else {
            return httpResponse(status: "400 Bad Request", body: #"{"error":"bad_request"}"#)
        }
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return httpResponse(status: "400 Bad Request", body: #"{"error":"bad_request"}"#)
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: "400 Bad Request", body: #"{"error":"bad_request"}"#)
        }

        let target = String(parts[1])
        guard target.hasPrefix("/snapshot.json") else {
            return httpResponse(status: "404 Not Found", body: #"{"error":"not_found"}"#)
        }
        let headers = lines.dropFirst().compactMap(Self.parseHeader)
        let queryToken = URLComponents(string: "http://bridge\(target)")?.queryItems?
            .first(where: { $0.name == "token" })?.value
        guard Self.isAuthorized(headers: headers, token: token) || queryToken == token else {
            return httpResponse(status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
        }

        let body = currentSnapshotData ?? (try? encoder.encode(UsageSnapshot.empty)) ?? Data("{}".utf8)
        return httpResponse(status: "200 OK", contentType: "application/json", body: body)
    }

    private func httpResponse(status: String, contentType: String = "application/json", body: String) -> Data {
        httpResponse(status: status, contentType: contentType, body: Data(body.utf8))
    }

    private func httpResponse(status: String, contentType: String = "application/json", body: Data) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func endpointURL(scheme: String, port: UInt16, path: String) -> URL? {
        guard let host = Self.preferredHostAddress() else {
            return nil
        }
        return endpointURL(scheme: scheme, host: host, port: port, path: path)
    }

    private func endpointURL(scheme: String, host: String, port: UInt16, path: String) -> URL? {
        guard port > 0 else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = Int(port)
        components.path = path
        return components.url
    }

    private static func parseHeader(_ line: String) -> (name: String, value: String)? {
        guard let separator = line.firstIndex(of: ":") else {
            return nil
        }
        let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        return (name, value)
    }

    private static func isAuthorized(headers: [(name: String, value: String)], token: String) -> Bool {
        headers.contains { header in
            header.name.caseInsensitiveCompare(BridgeProtocol.authorizationHeader) == .orderedSame &&
                header.value == "Bearer \(token)"
        }
    }

    private static func loadOrCreateValue(named name: String, generate: () -> String) -> String {
        let directory = URL(fileURLWithPath: NSString(string: "~/.ai-usage").expandingTildeInPath)
        let file = directory.appendingPathComponent(name)
        if let existing = try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }

        let value = generate()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? value.write(to: file, atomically: true, encoding: .utf8)
        return value
    }

    private static func log(_ message: String) {
        let directory = URL(fileURLWithPath: NSString(string: "~/.ai-usage").expandingTildeInPath)
        let file = directory.appendingPathComponent("bridge.log")
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

    private static func preferredHostAddress() -> String? {
        let addresses = hostAddresses()
        return addresses.first { $0.address.hasPrefix("100.") }?.address ??
            addresses.first { $0.interface == "en0" }?.address ??
            addresses.first?.address
    }

    private static func hostAddresses() -> [(interface: String, address: String)] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return []
        }
        defer { freeifaddrs(pointer) }

        var result: [(interface: String, address: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            defer { current = item.pointee.ifa_next }
            let flags = Int32(item.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let interface = String(cString: item.pointee.ifa_name)
            let endIndex = host.firstIndex(of: 0) ?? host.endIndex
            let addressString = String(decoding: host[..<endIndex].map(UInt8.init(bitPattern:)), as: UTF8.self)
            if !addressString.hasPrefix("169.254.") {
                result.append((interface, addressString))
            }
        }
        return result
    }
}
