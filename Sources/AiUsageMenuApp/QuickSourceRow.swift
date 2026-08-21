import SwiftUI

/// One source summary in the compact quick-access grid.
struct QuickSourceRow: View {
    let summary: SourceUsageSummary

    var body: some View {
        HStack(spacing: HappeningsTheme.Spacing.control) {
            Image(systemName: summary.source.symbolName)
                .font(.body)
                .foregroundStyle(HappeningsTheme.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.compact) {
                Text(summary.source.rawValue)
                    .font(.callout)
                    .foregroundStyle(HappeningsTheme.textSecondary)

                Text(NumberFormat.compact(summary.currentWindowUsage.billableApproximation))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(HappeningsTheme.textPrimary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: HappeningsTheme.Spacing.small)

            if let usedPercent = summary.primaryPercent {
                Text("\(usedPercent, format: .number.precision(.fractionLength(0)))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(HappeningsTheme.textSecondary)
            }
        }
        .padding(HappeningsTheme.Spacing.control)
        .background(HappeningsTheme.surfaceInset, in: .rect(cornerRadius: HappeningsTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: HappeningsTheme.Radius.control)
                .stroke(HappeningsTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
