import Foundation

final class BridgeServer: @unchecked Sendable {
    static let shared = BridgeServer()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ai-usage.bridge-server")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private var socketDescriptor: Int32 = -1
    private var currentSnapshotData: Data?
    private(set) var port: UInt16 = 0
    let token: String

    private init() {
        token = Self.loadOrCreateToken()
    }

    var isRunning: Bool {
        lock.withLock { socketDescriptor >= 0 }
    }

    var bridgeURL: URL? {
        guard port > 0, let host = Self.preferredHostAddress() else {
            return nil
        }
        return URL(string: "http://\(host):\(port)/snapshot.json?token=\(token)")
    }

    var localhostURL: URL? {
        guard port > 0 else {
            return nil
        }
        return URL(string: "http://127.0.0.1:\(port)/snapshot.json?token=\(token)")
    }

    func start() {
        lock.lock()
        if socketDescriptor >= 0 {
            lock.unlock()
            return
        }
        lock.unlock()

        do {
            let selectedPort = try Self.availableBridgePort()
            let descriptor = try Self.makeListeningSocket(port: selectedPort)

            lock.withLock {
                self.socketDescriptor = descriptor
                self.port = selectedPort
            }
            Self.log("starting bridge on \(selectedPort)")
            queue.async { [weak self] in
                self?.acceptLoop(socketDescriptor: descriptor)
            }
            Self.log("bridge ready on \(selectedPort)")
        } catch {
            Self.log("bridge start error: \(error)")
            // Bridge is best-effort; the UI exposes absence by omitting a URL.
        }
    }

    func update(snapshot: UsageSnapshot) {
        if let data = try? encoder.encode(snapshot) {
            lock.withLock {
                currentSnapshotData = data
            }
        }
    }

    private func acceptLoop(socketDescriptor: Int32) {
        while true {
            var clientAddress = sockaddr()
            var clientAddressLength = socklen_t(MemoryLayout<sockaddr>.size)
            let client = accept(socketDescriptor, &clientAddress, &clientAddressLength)
            if client < 0 {
                Self.log("bridge accept error: \(errno)")
                continue
            }

            handle(client: client)
        }
    }

    private func handle(client: Int32) {
        defer { close(client) }

        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else {
            return
        }

        let response = response(for: Data(buffer.prefix(count)))
        response.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            _ = write(client, baseAddress, response.count)
        }
    }

    private func response(for requestData: Data) -> Data {
        guard let request = String(data: requestData, encoding: .utf8),
              let firstLine = request.split(separator: "\r\n").first else {
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
        guard target.contains("token=\(token)") else {
            return httpResponse(status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
        }

        let body = lock.withLock { currentSnapshotData } ?? (try? encoder.encode(UsageSnapshot.empty)) ?? Data("{}".utf8)
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
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "\r\n"

        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private static func loadOrCreateToken() -> String {
        let directory = URL(fileURLWithPath: NSString(string: "~/.ai-usage").expandingTildeInPath)
        let file = directory.appendingPathComponent("bridge-token")
        if let existing = try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? token.write(to: file, atomically: true, encoding: .utf8)
        return token
    }

    private static func log(_ message: String) {
        let directory = URL(fileURLWithPath: NSString(string: "~/.ai-usage").expandingTildeInPath)
        let file = directory.appendingPathComponent("bridge.log")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let data = line.data(using: .utf8) {
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

    private static func availableBridgePort() throws -> UInt16 {
        for port in UInt16(47_392)...UInt16(47_402) {
            if canBind(port: port) {
                return port
            }
        }
        throw CocoaError(.fileWriteUnknown)
    }

    private static func makeListeningSocket(port: UInt16) throws -> Int32 {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var yes: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let didBind = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard didBind else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            close(socketDescriptor)
            throw error
        }

        guard listen(socketDescriptor, SOMAXCONN) == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            close(socketDescriptor)
            throw error
        }

        return socketDescriptor
    }

    private static func canBind(port: UInt16) -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            return false
        }
        defer { close(socketDescriptor) }

        var yes: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
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
                result.append((interface: interface, address: addressString))
            }
        }
        return result
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
