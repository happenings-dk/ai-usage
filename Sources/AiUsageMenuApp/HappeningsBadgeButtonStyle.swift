import SwiftUI

/// Press feedback for compact status-badge actions.
struct HappeningsBadgeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.58)
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == HappeningsBadgeButtonStyle {
    /// A compact flat action with Happenings press feedback.
    static var happeningsBadge: HappeningsBadgeButtonStyle { .init() }
}
