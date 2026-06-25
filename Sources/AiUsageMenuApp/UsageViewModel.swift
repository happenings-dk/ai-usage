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
    @ObservationIgnored private let bridgeServer = BridgeServer.shared

    init() {
        bridgeServer.start()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
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

    func refresh() {
        refreshTask?.cancel()
        versionRefreshTask?.cancel()
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

            versionRefreshTask = Task {
                let checkedAt = Date()
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
                isRefreshing = false
            }
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

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
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
        if let url = bridgeServer.bridgeURL {
            bridgeURLText = url.absoluteString
        } else if let url = bridgeServer.localhostURL {
            bridgeURLText = url.absoluteString
        } else {
            bridgeURLText = "Bridge unavailable"
        }
    }
}
