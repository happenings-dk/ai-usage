import SwiftUI

/// A compact aggregate metric with tabular number formatting.
struct UsageMetricView: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.compact) {
            Text(title)
                .font(.caption)
                .foregroundStyle(HappeningsTheme.textSecondary)

            Text(NumberFormat.compact(value))
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(HappeningsTheme.textPrimary)
                .contentTransition(.numericText())
        }
        .padding(HappeningsTheme.Spacing.control)
        .frame(minWidth: 104, maxWidth: .infinity, alignment: .leading)
        .background(HappeningsTheme.surfaceInset, in: .rect(cornerRadius: HappeningsTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: HappeningsTheme.Radius.control)
                .stroke(HappeningsTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
