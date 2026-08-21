import SwiftUI

/// A coherent source object showing totals, limits, and current context.
struct UsageSourceCard: View {
    let summary: SourceUsageSummary

    var body: some View {
        HappeningsCard(fillsAvailableHeight: true) {
            VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.standard) {
                HStack(spacing: HappeningsTheme.Spacing.small) {
                    Image(systemName: summary.source.symbolName)
                        .font(.title3)
                        .foregroundStyle(HappeningsTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    Text(summary.source.rawValue)
                        .font(.title2.bold())
                        .foregroundStyle(HappeningsTheme.textPrimary)

                    Spacer(minLength: HappeningsTheme.Spacing.small)

                    HappeningsStatusBadge(
                        text: summary.hasActivity ? "Active" : "Idle",
                        systemImage: summary.hasActivity ? "waveform" : "minus",
                        color: summary.hasActivity
                            ? HappeningsTheme.textPrimary
                            : HappeningsTheme.textSecondary
                    )
                }

                HStack(spacing: HappeningsTheme.Spacing.standard) {
                    SourceMetricView(
                        title: "Current",
                        value: summary.currentWindowUsage.billableApproximation
                    )
                    SourceMetricView(
                        title: "Today",
                        value: summary.todayUsage.billableApproximation
                    )
                    SourceMetricView(
                        title: "7 days",
                        value: summary.weekUsage.billableApproximation
                    )
                }
                .padding(HappeningsTheme.Spacing.control)
                .background(
                    HappeningsTheme.surfaceInset,
                    in: .rect(cornerRadius: HappeningsTheme.Radius.control)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: HappeningsTheme.Radius.control)
                        .stroke(HappeningsTheme.border, lineWidth: 1)
                }

                if summary.rateLimits.isEmpty {
                    Label("No live rate limit", systemImage: "gauge.with.dots.needle.0percent")
                        .font(.callout)
                        .foregroundStyle(HappeningsTheme.textSecondary)
                } else {
                    ForEach(summary.rateLimits, id: \.name) { limit in
                        UsageLimitProgressView(
                            title: limit.name,
                            usedPercent: limit.usedPercent,
                            resetsAt: limit.resetsAt
                        )
                    }
                }

                Divider()

                LabeledContent("Model") {
                    Text(summary.latestModel ?? "Unknown")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent("Project") {
                    Text(projectName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let warning = summary.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
        }
    }

    private var projectName: String {
        guard let project = summary.latestProject, !project.isEmpty else {
            return "Unknown"
        }

        let name = URL(fileURLWithPath: project).lastPathComponent
        return name.isEmpty ? project : name
    }
}
