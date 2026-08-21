import SwiftUI

/// A source-scoped token total used inside a shared inset group.
struct SourceMetricView: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.compact) {
            Text(title)
                .font(.caption)
                .foregroundStyle(HappeningsTheme.textSecondary)

            Text(NumberFormat.compact(value))
                .font(.headline.monospacedDigit())
                .foregroundStyle(HappeningsTheme.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
