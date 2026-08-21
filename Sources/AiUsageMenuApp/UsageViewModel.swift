import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UsageViewModel {
    var snapshot = UsageSnapshot.empty
    var isRefreshing = false
    var lastError: String?
    var isInstallingUpdate = false
    private(set) var checkingVersionSourceIDs = Set<String>()
    private(set) var isCheckingAppVersion = false
    var bridgeURLText = "Starting bridge..."

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var versionRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var activeVersionCheckID: UUID?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var versionTimer: Timer?
    @ObservationIgnored private var fileWatcher: UsageFileWatcher?
    @ObservationIgnored private let bridgeServer = BridgeServer.shared

    init() {
        bridgeServer.start()
        refresh()
        fileWatcher = UsageFileWatcher { [weak self] in
            Task { @MainActor in
                self?.refreshUsage()
            }
        }
        fileWatcher?.start()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshUsage()
            }
        }
        versionTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkVersions()
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            updateBridgeURLText()
        }
    }

    var menuBarTitle: String {
        if let tightestLimit = snapshot.tightestLimit {
            return "AI \(Int(tightestLimit.window.usedPercent.rounded()))%"
        }

        let total = snapshot.summaries.reduce(0) { $0 + $1.currentWindowUsage.billableApproximation }
        if total > 0 {
            return "AI \(NumberFormat.compact(total))"
        }
        return "AI"
    }

    var pairingURL: URL? {
        bridgeServer.pairingPayload?.encodedPairingURL()
    }

    var isCheckingVersions: Bool {
        !checkingVersionSourceIDs.isEmpty || isCheckingAppVersion
    }

    func refresh() {
        refreshUsage(includeVersions: true)
    }

    /// Rebuilds local usage immediately without waiting for the fallback timer.
    func refreshUsage() {
        refreshUsage(includeVersions: false)
    }

    private func refreshUsage(includeVersions: Bool) {
        refreshTask?.cancel()
        isRefreshing = true
        lastError = nil

        refreshTask = Task {
            let usageGeneratedAt = Date()
            let summaries = await Task.detached(priority: .userInitiated) {
                UsageStore().loadUsageSummaries(now: usageGeneratedAt)
            }.value

            guard !Task.isCancelled else { return }
            snapshot = UsageSnapshot(
                generatedAt: usageGeneratedAt,
                summaries: summaries,
                cliVersions: snapshot.cliVersions,
                appUpdate: snapshot.appUpdate
            )
            publishBridgeSnapshot()
            isRefreshing = false

            if includeVersions {
                checkVersions()
            }
        }
    }

    func isCheckingVersion(_ source: UsageSource) -> Bool {
        checkingVersionSourceIDs.contains(source.id)
    }

    func checkVersions() {
        guard let checkID = beginVersionCheck(
            sources: UsageSource.allCases,
            includeApp: true
        ) else { return }
        versionRefreshTask = Task {
            let checkedAt = Date()
            let versionSnapshot = await VersionStore().loadConcurrently(now: checkedAt)

            guard !Task.isCancelled, activeVersionCheckID == checkID else { return }
            snapshot = UsageSnapshot(
                generatedAt: snapshot.generatedAt,
                summaries: snapshot.summaries,
                cliVersions: versionSnapshot.cliVersions,
                appUpdate: versionSnapshot.appUpdate
            )
            publishBridgeSnapshot()
            finishVersionCheck(checkID)
        }
    }

    func checkVersion(for source: UsageSource) {
        guard let checkID = beginVersionCheck(
            sources: [source],
            includeApp: false
        ) else { return }
        versionRefreshTask = Task {
            let checkedAt = Date()
            let status = await VersionStore().loadVersionConcurrently(
                for: source,
                now: checkedAt
            )

            guard !Task.isCancelled, activeVersionCheckID == checkID else { return }
            var versions = snapshot.cliVersions
            if let index = versions.firstIndex(where: { $0.source == source }) {
                versions[index] = status
            } else {
                versions.append(status)
            }
            versions.sort { lhs, rhs in
                let lhsIndex = UsageSource.allCases.firstIndex(of: lhs.source) ?? .max
                let rhsIndex = UsageSource.allCases.firstIndex(of: rhs.source) ?? .max
                return lhsIndex < rhsIndex
            }
            snapshot = UsageSnapshot(
                generatedAt: snapshot.generatedAt,
                summaries: snapshot.summaries,
                cliVersions: versions,
                appUpdate: snapshot.appUpdate
            )
            publishBridgeSnapshot()
            finishVersionCheck(checkID)
        }
    }

    func checkAppVersion() {
        guard let checkID = beginVersionCheck(
            sources: [],
            includeApp: true
        ) else { return }
        versionRefreshTask = Task {
            let checkedAt = Date()
            let appUpdate = await VersionStore().loadAppVersionConcurrently(now: checkedAt)

            guard !Task.isCancelled, activeVersionCheckID == checkID else { return }
            snapshot = UsageSnapshot(
                generatedAt: snapshot.generatedAt,
                summaries: snapshot.summaries,
                cliVersions: snapshot.cliVersions,
                appUpdate: appUpdate
            )
            publishBridgeSnapshot()
            finishVersionCheck(checkID)
        }
    }

    func openClaudeLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/.claude/projects").expandingTildeInPath))
    }

    func openCodexLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/.codex/sessions").expandingTildeInPath))
    }

    func openGeminiLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/.gemini/tmp").expandingTildeInPath))
    }

    func openGrokLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/.grok/sessions").expandingTildeInPath))
    }

    func openClaudeRateLimitCache() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/.claude/ai-usage-rate-limits.json").expandingTildeInPath))
    }

    func openAppUpdateDownload() {
        guard let url = snapshot.appUpdate.releasePageURL ?? snapshot.appUpdate.downloadURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func installAppUpdate() {
        let update = snapshot.appUpdate
        guard update.canInstallAutomatically else {
            return
        }

        isInstallingUpdate = true
        lastError = nil
        Task.detached(priority: .userInitiated) {
            do {
                try await AppUpdater.install(update: update)
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isInstallingUpdate = false
                }
            }
        }
    }

    func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.plainTextSummary(), forType: .string)
    }

    func copyBridgeURL() {
        updateBridgeURLText()
        guard let url = bridgeServer.bridgeURL ?? bridgeServer.localhostURL else {
            return
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: bridgeServer.token)]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(components?.url?.absoluteString ?? url.absoluteString, forType: .string)
    }

    func copyPairingLink() {
        updateBridgeURLText()
        guard let pairingURL = bridgeServer.pairingPayload?.encodedPairingURL() else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingURL.absoluteString, forType: .string)
    }

    func copyUpdateCommands() {
        let commands = snapshot.cliVersions
            .filter(\.isOutdated)
            .map(\.updateCommand)

        guard !commands.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands.joined(separator: "\n"), forType: .string)
    }

    func copyUpdateCommand(for status: CLIVersionStatus) {
        guard status.isOutdated else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(status.updateCommand, forType: .string)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func publishBridgeSnapshot() {
        bridgeServer.update(snapshot: snapshot)
        updateBridgeURLText()
    }

    private func beginVersionCheck(
        sources: [UsageSource],
        includeApp: Bool
    ) -> UUID? {
        guard activeVersionCheckID == nil else {
            return nil
        }
        let checkID = UUID()
        activeVersionCheckID = checkID
        checkingVersionSourceIDs = Set(sources.map(\.id))
        isCheckingAppVersion = includeApp
        return checkID
    }

    private func finishVersionCheck(_ checkID: UUID) {
        guard activeVersionCheckID == checkID else {
            return
        }
        activeVersionCheckID = nil
        versionRefreshTask = nil
        checkingVersionSourceIDs.removeAll()
        isCheckingAppVersion = false
    }

    private func updateBridgeURLText() {
        if let url = bridgeServer.webSocketURL {
            bridgeURLText = url.absoluteString
        } else if let url = bridgeServer.localhostURL {
            bridgeURLText = url.absoluteString
        } else {
            bridgeURLText = "Bridge unavailable"
        }
    }
}
