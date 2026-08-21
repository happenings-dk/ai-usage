import SwiftUI

/// A bordered inset control with restrained press compression.
struct HappeningsControlButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(isEnabled ? HappeningsTheme.textPrimary : HappeningsTheme.textSecondary)
            .padding(.horizontal, HappeningsTheme.Spacing.control)
            .frame(minHeight: 44)
            .background(
                configuration.isPressed
                    ? HappeningsTheme.controlPressed
                    : HappeningsTheme.surfaceInsetPressed,
                in: .rect(cornerRadius: HappeningsTheme.Radius.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HappeningsTheme.Radius.control)
                    .stroke(
                        configuration.isPressed
                            ? HappeningsTheme.borderStrong
                            : HappeningsTheme.border,
                        lineWidth: 1
                    )
            }
            .opacity(isEnabled ? 1 : 0.62)
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == HappeningsControlButtonStyle {
    /// A flat Happenings secondary control style.
    static var happeningsControl: HappeningsControlButtonStyle { .init() }
}
