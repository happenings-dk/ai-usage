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
    var bridgeURLText = "Starting bridge..."

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var versionRefreshTask: Task<Void, Never>?
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
                self?.refreshVersions()
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

    func refresh() {
        refreshUsage(includeVersions: true)
    }

    /// Rebuilds local usage immediately without waiting for the fallback timer.
    func refreshUsage() {
        refreshUsage(includeVersions: false)
    }

    private func refreshUsage(includeVersions: Bool) {
        refreshTask?.cancel()
        if includeVersions {
            versionRefreshTask?.cancel()
        }
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
                refreshVersions()
            }
        }
    }

    private func refreshVersions() {
        versionRefreshTask?.cancel()
        versionRefreshTask = Task {
            let checkedAt = Date()
            // Version probes invoke subprocesses and network requests, so they
            // deliberately run outside the main actor.
            let versionSnapshot = await Task.detached(priority: .utility) {
                VersionStore().load(now: checkedAt)
            }.value

            guard !Task.isCancelled else { return }
            snapshot = UsageSnapshot(
                generatedAt: snapshot.generatedAt,
                summaries: snapshot.summaries,
                cliVersions: versionSnapshot.cliVersions,
                appUpdate: versionSnapshot.appUpdate
            )
            publishBridgeSnapshot()
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
        guard update.isUpdateAvailable, update.downloadURL != nil else {
            return
        }

        isInstallingUpdate = true
        lastError = nil
        Task.detached(priority: .userInitiated) {
            do {
                try AppUpdater.install(update: update)
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
