import SwiftUI

/// The highest-priority usage state and aggregate token totals.
struct UsageOverviewView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HappeningsCard {
            HStack(alignment: .center, spacing: HappeningsTheme.Spacing.section) {
                VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.small) {
                    Text("Current pressure")
                        .font(.subheadline)
                        .foregroundStyle(HappeningsTheme.textSecondary)

                    if let tightestLimit = snapshot.tightestLimit {
                        Text(tightestLimit.window.usedPercent, format: .number.precision(.fractionLength(0)))
                            .font(.largeTitle.bold().monospacedDigit())
                            .foregroundStyle(HappeningsTheme.textPrimary)
                            .contentTransition(.numericText())
                            .accessibilityLabel("\(tightestLimit.window.usedPercent, format: .number.precision(.fractionLength(0))) percent used")

                        Text("\(tightestLimit.source.rawValue) · \(tightestLimit.window.name) window")
                            .font(.callout)
                            .foregroundStyle(HappeningsTheme.textSecondary)

                        UsageLimitProgressView(
                            title: tightestLimit.window.name,
                            usedPercent: tightestLimit.window.usedPercent,
                            resetsAt: tightestLimit.window.resetsAt
                        )
                    } else {
                        Text(NumberFormat.compact(currentWindowTotal))
                            .font(.largeTitle.bold().monospacedDigit())
                            .foregroundStyle(HappeningsTheme.textPrimary)
                            .contentTransition(.numericText())

                        Text("Billable tokens in the current window")
                            .font(.callout)
                            .foregroundStyle(HappeningsTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: HappeningsTheme.Spacing.small) {
                    UsageMetricView(title: "Current", value: currentWindowTotal)
                    UsageMetricView(title: "Today", value: todayTotal)
                    UsageMetricView(title: "7 days", value: weekTotal)
                }
            }
        }
    }

    private var currentWindowTotal: Int {
        snapshot.summaries.reduce(0) { total, summary in
            total + summary.currentWindowUsage.billableApproximation
        }
    }

    private var todayTotal: Int {
        snapshot.summaries.reduce(0) { total, summary in
            total + summary.todayUsage.billableApproximation
        }
    }

    private var weekTotal: Int {
        snapshot.summaries.reduce(0) { total, summary in
            total + summary.weekUsage.billableApproximation
        }
    }
}
