import SwiftUI

/// A high-contrast primary control with restrained press compression.
struct HappeningsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.bold())
            .foregroundStyle(HappeningsTheme.accentForeground)
            .padding(.horizontal, HappeningsTheme.Spacing.standard)
            .frame(minHeight: 44)
            .background(
                HappeningsTheme.accent.opacity(configuration.isPressed ? 0.82 : 1),
                in: .rect(cornerRadius: HappeningsTheme.Radius.control)
            )
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == HappeningsPrimaryButtonStyle {
    /// A high-contrast Happenings primary control style.
    static var happeningsPrimary: HappeningsPrimaryButtonStyle { .init() }
}
