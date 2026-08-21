import SwiftUI

/// A labeled limit bar that communicates state with text and color.
struct UsageLimitProgressView: View {
    let title: String
    let usedPercent: Double
    let resetsAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.small) {
            ProgressView(value: normalizedPercent)
                .progressViewStyle(.linear)
                .tint(progressColor)
                .accessibilityLabel("\(title) usage")
                .accessibilityValue("\(usedPercent, format: .number.precision(.fractionLength(0))) percent used")

            HStack(spacing: HappeningsTheme.Spacing.small) {
                Text("\(usedPercent, format: .number.precision(.fractionLength(0)))% used")
                Spacer(minLength: HappeningsTheme.Spacing.small)
                Text("Resets \(TimeFormat.reset(resetsAt))")
            }
            .font(.caption)
            .foregroundStyle(HappeningsTheme.textSecondary)
        }
    }

    private var normalizedPercent: Double {
        min(max(usedPercent / 100, 0), 1)
    }

    private var progressColor: Color {
        if usedPercent >= 90 {
            .red
        } else if usedPercent >= 75 {
            .orange
        } else {
            HappeningsTheme.accent
        }
    }
}
