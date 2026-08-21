import SwiftUI

/// Shared Happenings design tokens for the macOS app.
enum HappeningsTheme {
    static let accent = adaptiveColor(light: 0x18181B, dark: 0xFAFAFA)
    static let accentForeground = adaptiveColor(light: 0xFAFAFA, dark: 0x09090B)
    static let background = adaptiveColor(light: 0xFAFAFA, dark: 0x09090B)
    static let surface = adaptiveColor(light: 0xFFFFFF, dark: 0x18181B)
    static let surfaceInset = adaptiveColor(light: 0xF4F4F5, dark: 0x27272A)
    static let surfaceInsetPressed = adaptiveColor(light: 0xE4E4E7, dark: 0x3F3F46)
    static let controlPressed = adaptiveColor(light: 0xD4D4D8, dark: 0x52525B)
    static let border = adaptiveColor(
        light: 0x000000,
        dark: 0xFFFFFF,
        lightOpacity: 0.10,
        darkOpacity: 0.08
    )
    static let borderStrong = adaptiveColor(
        light: 0x000000,
        dark: 0xFFFFFF,
        lightOpacity: 0.16,
        darkOpacity: 0.14
    )
    static let textPrimary = adaptiveColor(light: 0x09090B, dark: 0xFAFAFA)
    static let textSecondary = adaptiveColor(light: 0x71717A, dark: 0xA1A1AA)
    static let textTertiary = adaptiveColor(light: 0xA1A1AA, dark: 0x71717A)

    enum Spacing {
        static let compact: Double = 4
        static let small: Double = 8
        static let control: Double = 12
        static let standard: Double = 16
        static let generous: Double = 20
        static let section: Double = 24
    }

    enum Radius {
        static let card: Double = 16
        static let control: Double = 12
    }

    enum Layout {
        static let quickPanelWidth: Double = 560
        static let quickPanelHeight: Double = 640
        static let shortcutRecorderWidth: Double = 232
        static let windowEdgeInset: Double = 16
    }

    private static func adaptiveColor(
        light: UInt32,
        dark: UInt32,
        lightOpacity: Double = 1,
        darkOpacity: Double = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(
                hex: isDark ? dark : light,
                opacity: isDark ? darkOpacity : lightOpacity
            )
        })
    }
}

private extension NSColor {
    /// Creates a color from a 24-bit RGB value.
    convenience init(hex: UInt32, opacity: Double) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
