import SwiftUI

/// One source-qualified limit in the Quick Look panel.
struct QuickLimitCard: View {
    let item: UsageLimitItem

    var body: some View {
        VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.small) {
            HStack(spacing: HappeningsTheme.Spacing.small) {
                Label(item.source.rawValue, systemImage: item.source.symbolName)
                    .font(.headline)
                    .foregroundStyle(HappeningsTheme.textPrimary)

                Text(item.window.name)
                    .font(.callout)
                    .foregroundStyle(HappeningsTheme.textSecondary)

                Spacer(minLength: HappeningsTheme.Spacing.small)

                Text("\(item.window.usedPercent, format: .number.precision(.fractionLength(0)))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(HappeningsTheme.textPrimary)
            }

            ProgressView(value: normalizedPercent)
                .progressViewStyle(.linear)
                .tint(progressColor)
                .accessibilityLabel("\(item.source.rawValue) \(item.window.name) usage")
                .accessibilityValue("\(item.window.usedPercent, format: .number.precision(.fractionLength(0))) percent used")

            Text("Resets \(TimeFormat.reset(item.window.resetsAt))")
                .font(.caption)
                .foregroundStyle(HappeningsTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(HappeningsTheme.Spacing.control)
        .background(HappeningsTheme.surface, in: .rect(cornerRadius: HappeningsTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: HappeningsTheme.Radius.control)
                .stroke(HappeningsTheme.border, lineWidth: 1)
        }
    }

    private var normalizedPercent: Double {
        min(max(item.window.usedPercent / 100, 0), 1)
    }

    private var progressColor: Color {
        if item.window.usedPercent >= 90 {
            .red
        } else if item.window.usedPercent >= 75 {
            .orange
        } else {
            HappeningsTheme.accent
        }
    }
}
