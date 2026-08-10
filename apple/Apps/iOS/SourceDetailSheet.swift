import SwiftUI

/// A live, source-specific usage breakdown presented from the dashboard.
struct SourceDetailSheet: View {
    let model: MobileUsageModel
    let source: UsageSource

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HapTheme.Space.lg) {
                    SourceDetailHeader(summary: summary)
                    usageSection
                    tokenSection
                    limitsSection
                    projectsSection
                    activitySection

                    if let warning = summary.warning {
                        warningSection(warning)
                    }
                }
                .padding(.horizontal, HapTheme.Space.lg)
                .padding(.vertical, HapTheme.Space.md)
            }
            .background(HapTheme.background)
            .navigationTitle(source.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var summary: SourceUsageSummary {
        model.snapshot.summary(for: source)
    }

    private var usageSection: some View {
        SourceDetailSection(title: "Usage") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: HapTheme.Space.sm), count: 3),
                spacing: HapTheme.Space.sm
            ) {
                SourceDetailMetric(title: "5 hours", usage: summary.currentWindowUsage)
                SourceDetailMetric(title: "Today", usage: summary.todayUsage)
                SourceDetailMetric(title: "7 days", usage: summary.weekUsage)
            }
        }
    }

    private var tokenSection: some View {
        SourceDetailSection(title: "Current window") {
            VStack(spacing: HapTheme.Space.sm) {
                SourceDetailRow(title: "Input", value: NumberFormat.compact(summary.currentWindowUsage.input))
                SourceDetailRow(title: "Output", value: NumberFormat.compact(summary.currentWindowUsage.output))
                SourceDetailRow(title: "Cached", value: NumberFormat.compact(summary.currentWindowUsage.cachedInput))
                SourceDetailRow(
                    title: "Cache creation",
                    value: NumberFormat.compact(summary.currentWindowUsage.cacheCreationInput)
                )
                SourceDetailRow(title: reasoningTitle, value: reasoningValue)
                Divider()
                SourceDetailRow(
                    title: "Billable",
                    value: NumberFormat.compact(summary.currentWindowUsage.billableApproximation),
                    isEmphasized: true
                )
                SourceDetailRow(
                    title: "Total",
                    value: NumberFormat.compact(summary.currentWindowUsage.total),
                    isEmphasized: true
                )
            }
        }
    }

    private var limitsSection: some View {
        SourceDetailSection(title: "Limits and resets") {
            VStack(spacing: HapTheme.Space.md) {
                if summary.rateLimits.isEmpty {
                    SourceDetailRow(title: "5 hour reset", value: TimeFormat.reset(summary.estimatedResetAt))
                    SourceDetailRow(title: "Weekly reset", value: TimeFormat.reset(summary.estimatedWeeklyResetAt))
                } else {
                    ForEach(summary.rateLimits, id: \.name) { window in
                        SourceLimitDetail(window: window)
                    }
                }
            }
        }
    }

    private var projectsSection: some View {
        Group {
            if !summary.topProjects.isEmpty {
                SourceDetailSection(title: "Top projects") {
                    VStack(spacing: HapTheme.Space.sm) {
                        ForEach(summary.topProjects) { project in
                            SourceProjectRow(project: project)
                        }
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        SourceDetailSection(title: "Activity") {
            VStack(spacing: HapTheme.Space.sm) {
                SourceDetailRow(title: "Last event", value: TimeFormat.exact(summary.lastEventAt))
                SourceDetailRow(title: "Latest model", value: summary.latestModel ?? "Unknown")
                SourceDetailRow(title: "Latest project", value: projectName(summary.latestProject))
                SourceDetailRow(title: "Files scanned", value: "\(summary.scannedFiles)")
                SourceDetailRow(title: "Events", value: "\(summary.eventCount)")
                SourceDetailRow(title: "5 hour events", value: "\(summary.currentWindowEventCount)")

                if let updatedAt = summary.rateLimitUpdatedAt {
                    SourceDetailRow(title: "Limits updated", value: TimeFormat.exact(updatedAt))
                }

                ForEach(summary.extraDetails) { detail in
                    SourceDetailRow(title: detail.title, value: detail.value)
                }
            }
        }
    }

    private var reasoningTitle: String {
        source == .gemini ? "Thoughts" : "Reasoning"
    }

    private var reasoningValue: String {
        switch source {
        case .claude, .grok:
            "N/A"
        case .codex, .gemini:
            NumberFormat.compact(summary.currentWindowUsage.reasoningOutput)
        }
    }

    private func projectName(_ path: String?) -> String {
        guard let path else {
            return "No active project"
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func warningSection(_ warning: String) -> some View {
        SourceDetailSection(title: "Notice") {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(HapTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SourceDetailHeader: View {
    let summary: SourceUsageSummary

    var body: some View {
        HapCard(padding: HapTheme.Space.lg) {
            HStack(spacing: HapTheme.Space.md) {
                Image(systemName: summary.source.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HapTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        HapTheme.surfaceInset,
                        in: RoundedRectangle(cornerRadius: HapTheme.Radius.control, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: HapTheme.Space.xs) {
                    Text(summary.source.rawValue)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(HapTheme.textPrimary)
                    Text("Updated \(TimeFormat.relative(summary.lastEventAt))")
                        .font(.caption)
                        .foregroundStyle(HapTheme.textSecondary)
                }

                Spacer(minLength: HapTheme.Space.sm)

                VStack(alignment: .trailing, spacing: HapTheme.Space.xs) {
                    Text(NumberFormat.compact(summary.currentWindowUsage.billableApproximation))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(HapTheme.textPrimary)
                    Text("billable")
                        .font(.caption2)
                        .foregroundStyle(HapTheme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SourceDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HapTheme.Space.sm) {
            HapSectionHeader(title: title)
            HapCard(padding: HapTheme.Space.md) {
                content
            }
        }
    }
}

private struct SourceDetailMetric: View {
    let title: String
    let usage: TokenUsage

    var body: some View {
        VStack(alignment: .leading, spacing: HapTheme.Space.xs) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(HapTheme.textSecondary)
            Text(NumberFormat.compact(usage.billableApproximation))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(HapTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("billable")
                .font(.caption2)
                .foregroundStyle(HapTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HapTheme.Space.sm)
        .background(
            HapTheme.surfaceInset,
            in: RoundedRectangle(cornerRadius: HapTheme.Radius.row, style: .continuous)
        )
    }
}

private struct SourceDetailRow: View {
    let title: String
    let value: String
    var isEmphasized = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HapTheme.Space.md) {
            Text(title)
                .foregroundStyle(isEmphasized ? HapTheme.textPrimary : HapTheme.textSecondary)
            Spacer(minLength: HapTheme.Space.md)
            Text(value)
                .foregroundStyle(HapTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .font(isEmphasized ? .subheadline.weight(.semibold) : .subheadline)
        .accessibilityElement(children: .combine)
    }
}

private struct SourceLimitDetail: View {
    let window: RateLimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: HapTheme.Space.sm) {
            HStack {
                Text(window.name)
                    .fontWeight(.medium)
                Spacer()
                Text("\(NumberFormat.percent(window.usedPercent)) used")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(HapTheme.textPrimary)

            ProgressView(value: min(max(window.usedPercent, 0), 100), total: 100)
                .tint(HapTheme.accent)

            HStack {
                Text("\(NumberFormat.percent(max(0, 100 - window.usedPercent))) left")
                Spacer()
                Text("Resets \(TimeFormat.remaining(until: window.resetsAt))")
            }
            .font(.caption)
            .foregroundStyle(HapTheme.textSecondary)
        }
        .padding(HapTheme.Space.sm)
        .background(
            HapTheme.surfaceInset,
            in: RoundedRectangle(cornerRadius: HapTheme.Radius.row, style: .continuous)
        )
    }
}

private struct SourceProjectRow: View {
    let project: ProjectUsage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HapTheme.Space.md) {
            VStack(alignment: .leading, spacing: HapTheme.Space.xs) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HapTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(project.eventCount) events")
                    .font(.caption)
                    .foregroundStyle(HapTheme.textSecondary)
            }

            Spacer(minLength: HapTheme.Space.sm)

            Text(NumberFormat.compact(project.usage.billableApproximation))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(HapTheme.textPrimary)
        }
        .padding(HapTheme.Space.sm)
        .background(
            HapTheme.surfaceInset,
            in: RoundedRectangle(cornerRadius: HapTheme.Radius.row, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
