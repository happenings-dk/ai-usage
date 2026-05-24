import SwiftUI

struct UsageDashboardView: View {
    let model: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView(model: model)

            ScrollView {
                VStack(spacing: 10) {
                    SourceUsageView(summary: model.snapshot.summary(for: .claude))
                    SourceUsageView(summary: model.snapshot.summary(for: .codex))
                    let gemini = model.snapshot.summary(for: .gemini)
                    if gemini.hasActivity {
                        SourceUsageView(summary: gemini)
                    } else {
                        CompactSourceUsageView(summary: gemini)
                    }

                    VersionStatusView(
                        cliVersions: model.snapshot.cliVersions,
                        appUpdate: model.snapshot.appUpdate
                    )
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 820)

            Divider()

            HStack {
                Text("Updated \(TimeFormat.relative(model.snapshot.generatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .disabled(model.isRefreshing)

                Menu {
                    Button("Copy Summary") {
                        model.copySummary()
                    }
                    Button("Copy CLI Update Commands") {
                        model.copyUpdateCommands()
                    }
                    .disabled(!model.snapshot.cliVersions.contains { $0.isOutdated })
                    if model.snapshot.appUpdate.isUpdateAvailable,
                       model.snapshot.appUpdate.downloadURL != nil {
                        Button("Install App Update") {
                            model.installAppUpdate()
                        }
                        .disabled(model.isInstallingUpdate)
                    }
                    Divider()
                    Button("Open Claude Logs") {
                        model.openClaudeLogs()
                    }
                    Button("Open Claude Limit Cache") {
                        model.openClaudeRateLimitCache()
                    }
                    Button("Open Codex Logs") {
                        model.openCodexLogs()
                    }
                    Button("Open Gemini Logs") {
                        model.openGeminiLogs()
                    }
                    if model.snapshot.appUpdate.releasePageURL != nil || model.snapshot.appUpdate.downloadURL != nil {
                        Divider()
                        Button("Open App Release") {
                            model.openAppUpdateDownload()
                        }
                    }
                    Divider()
                    SettingsLink {
                        Text("Settings")
                    }
                    Divider()
                    Button("Quit AI Usage") {
                        model.quit()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .help("More")
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }
}

private struct HeaderView: View {
    let model: UsageViewModel

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Usage")
                    .font(.title3.weight(.semibold))
                Text("Claude, Codex, and Gemini CLI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isRefreshing || model.isInstallingUpdate {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

private struct SourceUsageView: View {
    let summary: SourceUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: summary.source.symbolName)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)

                Text(summary.source.rawValue)
                    .font(.headline)

                Spacer()

                Text(NumberFormat.compact(summary.currentWindowUsage.billableApproximation))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .accessibilityLabel("\(summary.currentWindowUsage.billableApproximation) current window tokens")
            }

            HStack(spacing: 10) {
                MetricPill(title: "5h billable", value: NumberFormat.compact(summary.currentWindowUsage.billableApproximation))
                MetricPill(title: "Today", value: NumberFormat.compact(summary.todayUsage.billableApproximation))
                MetricPill(title: "7d", value: NumberFormat.compact(summary.weekUsage.billableApproximation))
            }

            TokenBreakdownView(source: summary.source, usage: summary.currentWindowUsage)

            if summary.rateLimits.isEmpty {
                ResetLine(
                    title: "Estimated 5h reset",
                    resetsAt: summary.estimatedResetAt,
                    percent: nil,
                    windowMinutes: 5 * 60
                )
                ResetLine(
                    title: "Estimated weekly reset",
                    resetsAt: summary.estimatedWeeklyResetAt,
                    percent: nil,
                    windowMinutes: 7 * 24 * 60
                )
            } else {
                ForEach(summary.rateLimits, id: \.name) { limit in
                    ResetLine(
                        title: "\(limit.name) reset",
                        resetsAt: limit.resetsAt,
                        percent: limit.usedPercent,
                        windowMinutes: limit.windowMinutes
                    )
                }

                if let rateLimitUpdatedAt = summary.rateLimitUpdatedAt {
                    Text("Limits updated \(TimeFormat.exact(rateLimitUpdatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Last \(TimeFormat.relative(summary.lastEventAt))")
                Spacer()
                Text("\(summary.currentWindowEventCount)/\(summary.eventCount) events")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            DetailRows(summary: summary)
            TopProjectsView(projects: summary.topProjects)

            if let warning = summary.warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct CompactSourceUsageView: View {
    let summary: SourceUsageSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.source.symbolName)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.source.rawValue)
                    .font(.headline)
                Text("No activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(summary.scannedFiles) files")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
    }
}

private struct VersionStatusView: View {
    let cliVersions: [CLIVersionStatus]
    let appUpdate: AppUpdateStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Versions")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let checkedAt = cliVersions.compactMap(\.checkedAt).max() ?? appUpdate.checkedAt {
                    Text("Checked \(TimeFormat.relative(checkedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(cliVersions) { status in
                VersionRow(status: status)
            }

            AppUpdateRow(update: appUpdate)
        }
        .padding(10)
        .background(.background.secondary.opacity(0.72), in: .rect(cornerRadius: 8))
    }
}

private struct VersionRow: View {
    let status: CLIVersionStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.source.symbolName)
                .frame(width: 18)
                .foregroundStyle(.secondary)

            Text(status.source.rawValue)
                .font(.caption)

            Spacer(minLength: 8)

            Text(status.installedVersion ?? "Missing")
                .font(.caption.monospacedDigit())
                .foregroundStyle(status.installedVersion == nil ? .orange : .primary)

            if let latestVersion = status.latestVersion {
                Text("latest \(latestVersion)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VersionBadge(status: badgeStatus)
        }
        .help(helpText)
    }

    private var badgeStatus: VersionBadge.Status {
        if status.isOutdated {
            return .needsUpdate
        }
        if status.installedVersion == nil || status.latestVersion == nil {
            return .unknown
        }
        return .current
    }

    private var helpText: String {
        if status.isOutdated {
            return status.updateCommand
        }
        if let error = status.error {
            return error
        }
        return status.packageName
    }
}

private struct AppUpdateRow: View {
    let update: AppUpdateStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.badge")
                .frame(width: 18)
                .foregroundStyle(.secondary)

                Text("App")
                .font(.caption)

            Spacer(minLength: 8)

            Text(update.currentVersion)
                .font(.caption.monospacedDigit())

            if let latestVersion = update.latestVersion {
                Text("latest \(latestVersion)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let githubRepository = update.githubRepository {
                Text(githubRepository)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if !update.isConfigured {
                Text("repo not set")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VersionBadge(status: badgeStatus)
        }
        .help(helpText)
    }

    private var badgeStatus: VersionBadge.Status {
        if update.isUpdateAvailable {
            return .needsUpdate
        }
        if update.latestVersion == nil {
            return .unknown
        }
        return .current
    }

    private var helpText: String {
        if let downloadURL = update.downloadURL, update.isUpdateAvailable {
            return downloadURL.absoluteString
        }
        if let error = update.error {
            return error
        }
        return update.feedURL?.absoluteString ?? "~/.ai-usage/update-feed-url"
    }
}

private struct VersionBadge: View {
    enum Status {
        case current
        case needsUpdate
        case unknown
    }

    let status: Status

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: .capsule)
            .foregroundStyle(color)
    }

    private var text: String {
        switch status {
        case .current:
            "Current"
        case .needsUpdate:
            "Update"
        case .unknown:
            "Check"
        }
    }

    private var color: Color {
        switch status {
        case .current:
            .green
        case .needsUpdate:
            .orange
        case .unknown:
            .secondary
        }
    }
}

private struct TokenBreakdownView: View {
    let source: UsageSource
    let usage: TokenUsage

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                BreakdownItem(title: "Input", value: usage.input)
                BreakdownItem(title: "Output", value: usage.output)
                BreakdownItem(title: "Cached", value: usage.cachedInput)
                BreakdownItem(title: reasoningTitle, value: reasoningValue)
            }

            HStack {
                Text("Billable approx")
                Spacer()
                Text(NumberFormat.compact(usage.billableApproximation))
                    .monospacedDigit()
            }
            .font(.caption)

            HStack {
                Text("Total incl. cached")
                Spacer()
                Text(NumberFormat.compact(usage.total))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var reasoningTitle: String {
        switch source {
        case .claude:
            "Reason"
        case .codex:
            "Reason"
        case .gemini:
            "Thoughts"
        }
    }

    private var reasoningValue: String {
        switch source {
        case .claude:
            "N/A"
        case .codex, .gemini:
            NumberFormat.compact(usage.reasoningOutput)
        }
    }
}

private struct BreakdownItem: View {
    let title: String
    let value: String

    init(title: String, value: Int) {
        self.title = title
        self.value = NumberFormat.compact(value)
    }

    init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailRows: View {
    let summary: SourceUsageSummary

    var body: some View {
        VStack(spacing: 5) {
            DetailRow(title: "Model", value: summary.latestModel ?? "Unknown")
            DetailRow(title: "Project", value: formattedProject(summary.latestProject))
            DetailRow(title: "Scanned", value: "\(summary.scannedFiles) newest files")
            if !summary.rateLimits.isEmpty {
                DetailRow(title: "Limit source", value: limitSource)
            }
        }
    }

    private var limitSource: String {
        switch summary.source {
        case .claude:
            "Claude status line"
        case .codex:
            "Codex events"
        case .gemini:
            "Local estimate"
        }
    }

    private func formattedProject(_ project: String?) -> String {
        guard let project, !project.isEmpty else {
            return "Unknown"
        }

        let url = URL(fileURLWithPath: project)
        let name = url.lastPathComponent
        return name.isEmpty ? project : name
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }
}

private struct TopProjectsView: View {
    let projects: [ProjectUsage]

    var body: some View {
        if !projects.isEmpty {
            VStack(spacing: 5) {
                HStack {
                    Text("Top projects")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("7d billable")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                ForEach(Array(projects.prefix(3))) { project in
                    HStack {
                        Text(project.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(NumberFormat.compact(project.usage.billableApproximation))
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: .rect(cornerRadius: 6))
    }
}

private struct ResetLine: View {
    let title: String
    let resetsAt: Date?
    let percent: Double?
    let windowMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                if let percent, percent >= 80 {
                    WarningBadge(text: title.localizedCaseInsensitiveContains("weekly") ? "High weekly" : "High")
                }
                Spacer()
                if let percent {
                    Text(NumberFormat.percent(percent))
                        .monospacedDigit()
                }
                Text(TimeFormat.reset(resetsAt))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            HStack(spacing: 6) {
                if let percent {
                    Text("\(NumberFormat.percent(max(0, 100 - percent))) left")
                }
                if resetsAt != nil {
                    Text("resets in \(TimeFormat.remaining(until: resetsAt))")
                }
                if let pace = paceText {
                    Text(pace)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let percent {
                ProgressView(value: min(max(percent, 0), 100), total: 100)
                    .controlSize(.small)
                    .tint(progressTint(percent))
            }
        }
    }

    private var paceText: String? {
        guard let percent, let resetsAt, windowMinutes > 0, percent > 0 else {
            return nil
        }

        let now = Date()
        let windowStart = resetsAt.addingTimeInterval(-TimeInterval(windowMinutes * 60))
        let elapsedHours = max(now.timeIntervalSince(windowStart) / 3600, 1.0 / 60.0)
        let percentPerHour = percent / elapsedHours
        guard percentPerHour > 0 else {
            return nil
        }

        let remainingPercent = max(0, 100 - percent)
        let hoursToCap = remainingPercent / percentPerHour
        let projectedCapAt = now.addingTimeInterval(hoursToCap * 3600)
        if projectedCapAt < resetsAt {
            return "cap in \(TimeFormat.compactDuration(seconds: Int(hoursToCap * 3600)))"
        }

        return "pace \(NumberFormat.percentPrecise(percentPerHour))/h"
    }

    private func progressTint(_ percent: Double) -> Color {
        if percent >= 85 {
            return .red
        }
        if percent >= 65 {
            return .orange
        }
        return .green
    }
}

private struct WarningBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.red.opacity(0.14), in: .capsule)
            .foregroundStyle(.red)
    }
}

struct SettingsView: View {
    let model: UsageViewModel

    var body: some View {
        Form {
            Section("Data Sources") {
                LabeledContent("Claude") {
                    Text("~/.claude/projects")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Codex") {
                    Text("~/.codex/sessions")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Gemini") {
                    Text("~/.gemini/tmp")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Refresh") {
                LabeledContent("Interval") {
                    Text("60 seconds")
                        .foregroundStyle(.secondary)
                }
                Button("Refresh Now") {
                    model.refresh()
                }
            }

            Section("Updates") {
                LabeledContent("App Version") {
                    Text(model.snapshot.appUpdate.currentVersion)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Update Feed") {
                    Text(model.snapshot.appUpdate.feedURL?.absoluteString ?? "~/.ai-usage/update-feed-url")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
    }
}
