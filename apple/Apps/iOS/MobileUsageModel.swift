import Foundation
import Network
import Observation
import OSLog
import UIKit

/// The phone app's current connection phase.
enum SnapshotConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected(String)
    case reconnecting(Int)
    case failed(String)
}

/// Owns cached usage, pairing, and the foreground live-stream lifecycle.
@MainActor
@Observable
final class MobileUsageModel {
    var snapshot = UsageSnapshot.empty
    var isRefreshing = false
    var lastError: String?
    var lastImportLabel = "Bundled snapshot"
    var connectionState = SnapshotConnectionState.idle
    var discoveredBridges: [DiscoveredBridge] = []
    var syncURLString: String {
        didSet {
            UserDefaults.standard.set(syncURLString, forKey: syncURLDefaultsKey)
        }
    }

    @ObservationIgnored private let savedSnapshotDefaultsKey = "savedSnapshot"
    @ObservationIgnored private let syncURLDefaultsKey = "syncURLString"
    @ObservationIgnored private let pairedBridgeDefaultsKey = "pairedBridge"
    @ObservationIgnored private let streamClient = SnapshotStreamClient()
    @ObservationIgnored private let discovery = BridgeDiscovery()
    @ObservationIgnored private let logger = Logger(subsystem: "com.happenings.aiusage", category: "live-sync")
    @ObservationIgnored private var pairedBridge: BridgePairingPayload?

    init() {
        syncURLString = UserDefaults.standard.string(forKey: syncURLDefaultsKey) ??
            Self.bundledDefaultBridgeURL() ??
            ""
        pairedBridge = Self.loadPairedBridge(defaultsKey: pairedBridgeDefaultsKey)
        if let pairedBridge {
            syncURLString = pairedBridge.snapshotURL.absoluteString
        }
        loadInitialSnapshot()
#if DEBUG
        print("AI Usage pairing restored: \(pairedBridge != nil)")
#endif
    }

    var canRefresh: Bool {
        URL(string: syncURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    var isPaired: Bool {
        pairedBridge != nil
    }

    var currentWindowBillableTotal: Int {
        snapshot.summaries.reduce(0) { $0 + $1.currentWindowUsage.billableApproximation }
    }

    var weekBillableTotal: Int {
        snapshot.summaries.reduce(0) { $0 + $1.weekUsage.billableApproximation }
    }

    var activeSummaries: [SourceUsageSummary] {
        snapshot.summaries.filter(\.hasActivity) + snapshot.summaries.filter { !$0.hasActivity }
    }

    var connectionStatusLabel: String {
        switch connectionState {
        case .idle:
            lastImportLabel
        case .connecting:
            "Connecting"
        case .connected(let name):
            "Live from \(name)"
        case .reconnecting:
            "Reconnecting"
        case .failed:
            "Offline"
        }
    }

    var connectionStatusSymbol: String {
        switch connectionState {
        case .connected:
            "bolt.horizontal.circle.fill"
        case .connecting, .reconnecting:
            "arrow.triangle.2.circlepath"
        case .idle:
            "tray.and.arrow.down"
        case .failed:
            "wifi.slash"
        }
    }

    /// Maintains a live connection until SwiftUI cancels the active-scene task.
    func runLiveUpdates() async {
        guard let pairedBridge else {
#if DEBUG
            print("AI Usage live stream unavailable: no pairing")
#endif
            await refreshFromSyncURL()
            return
        }
#if DEBUG
        print("AI Usage live stream starting")
#endif

        var attempt = 0
        await withTaskCancellationHandler {
            while !Task.isCancelled {
                connectionState = attempt == 0 ? .connecting : .reconnecting(attempt)
                do {
                    let localEndpoint = discoveredBridges
                        .first(where: { $0.deviceID == pairedBridge.deviceID })?
                        .endpoint
                    try await streamClient.run(pairing: pairedBridge, localEndpoint: localEndpoint) { [weak self] envelope in
                        await self?.apply(envelope: envelope, label: pairedBridge.deviceName)
                    }
                    attempt = 0
                } catch is CancellationError {
                    return
                } catch {
                    attempt += 1
                    connectionState = .failed(error.localizedDescription)
                    lastError = error.localizedDescription
                    logger.error("Live stream failed: \(error.localizedDescription, privacy: .public)")
#if DEBUG
                    print("AI Usage live stream failed: \(error.localizedDescription)")
#endif
                }

                let delay = min(pow(2.0, Double(attempt)), 30)
                try? await Task.sleep(for: .seconds(delay))
            }
        } onCancel: {
            Task {
                await self.streamClient.disconnect()
            }
        }
    }

    /// Starts Bonjour discovery for nearby Mac bridges.
    func startDiscovery() {
        discovery.start { [weak self] bridges in
            self?.discoveredBridges = bridges
        }
    }

    /// Stops the current foreground stream.
    func disconnect() async {
        await streamClient.disconnect()
        if case .connected = connectionState {
            connectionState = .idle
        }
    }

    /// Downloads one snapshot from the configured fallback URL.
    func refreshFromSyncURL() {
        Task {
            await refreshFromSyncURL()
        }
    }

    /// Pairs from a custom URL, including links opened by QR scanners or Messages.
    func pair(_ url: URL) {
        do {
            let payload = try BridgePairingPayload.decode(from: url)
            try save(pairing: payload)
            lastError = nil
            connectionState = .idle
            Task {
                await refreshFromSyncURL()
                await PushRegistrationService.shared.syncRegistration(pairing: payload)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reads either a pairing link or a raw snapshot from pasted text.
    func importClipboardText(_ text: String?) {
        guard let text else {
            lastError = "The clipboard is empty."
            return
        }
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme == "aiusage" {
            pair(url)
            return
        }
        guard let data = text.data(using: .utf8) else {
            lastError = "The clipboard doesn't contain a snapshot or pairing link."
            return
        }

        do {
            try applySnapshotData(data, label: "Clipboard")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Imports a snapshot file selected by the system file picker.
    func importFile(_ result: Result<URL, Error>) {
        Task {
            do {
                let url = try result.get()
                let isScoped = url.startAccessingSecurityScopedResource()
                defer {
                    if isScoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try Data(contentsOf: url)
                try applySnapshotData(data, label: url.lastPathComponent)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Registers this device and syncs its token with a configured relay.
    func registerForRemoteUpdates() async {
        UIApplication.shared.registerForRemoteNotifications()
        if let pairedBridge {
            await PushRegistrationService.shared.syncRegistration(pairing: pairedBridge)
        }
    }

    /// Refreshes content within the time granted by a silent push.
    func refreshInBackground() async -> Bool {
        do {
            try await downloadSnapshot()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func refreshFromSyncURL() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }
        do {
            try await downloadSnapshot()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func downloadSnapshot() async throws {
        let trimmed = syncURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw MobileUsageError.invalidSyncURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        if let pairing = pairedBridge {
            let credential = url == pairing.relaySnapshotURL
                ? (pairing.relayToken ?? pairing.token)
                : pairing.token
            request.setValue("Bearer \(credential)", forHTTPHeaderField: BridgeProtocol.authorizationHeader)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw MobileUsageError.invalidServerResponse
        }
        try applySnapshotData(data, label: url.host ?? url.lastPathComponent)
    }

    private func apply(envelope: SnapshotEnvelope, label: String) {
        guard envelope.protocolVersion == BridgeProtocol.version else {
            lastError = "The Mac uses an unsupported live protocol."
            return
        }
        snapshot = envelope.snapshot
        connectionState = .connected(label)
        lastImportLabel = label
        lastError = nil
        save(snapshot: envelope.snapshot)
    }

    private func save(pairing: BridgePairingPayload) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(pairing)
        UserDefaults.standard.set(data, forKey: pairedBridgeDefaultsKey)
        pairedBridge = pairing
        syncURLString = pairing.snapshotURL.absoluteString
    }

    private func loadInitialSnapshot() {
        if let saved = UserDefaults.standard.data(forKey: savedSnapshotDefaultsKey),
           let decoded = try? decodeSnapshot(from: saved) {
            snapshot = decoded
            lastImportLabel = "Saved snapshot"
            return
        }

        guard let url = Bundle.main.url(forResource: "SeedSnapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? decodeSnapshot(from: data) else {
            return
        }
        snapshot = decoded
    }

    private func applySnapshotData(_ data: Data, label: String) throws {
        let decoded = try decodeSnapshot(from: data)
        snapshot = decoded
        lastImportLabel = label
        lastError = nil
        save(snapshot: decoded)
    }

    private func save(snapshot: UsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            UserDefaults.standard.set(data, forKey: savedSnapshotDefaultsKey)
        }
    }

    private func decodeSnapshot(from data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UsageSnapshot.self, from: data)
    }

    private static func loadPairedBridge(defaultsKey: String) -> BridgePairingPayload? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(BridgePairingPayload.self, from: data)
    }

    private static func bundledDefaultBridgeURL() -> String? {
        guard let url = Bundle.main.url(forResource: "DefaultBridgeURL", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// User-facing failures from the phone's snapshot transport.
private enum MobileUsageError: LocalizedError {
    case invalidSyncURL
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .invalidSyncURL:
            "The sync URL isn't valid."
        case .invalidServerResponse:
            "The Mac returned an unexpected response."
        }
    }
}
