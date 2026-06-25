import SwiftUI
import UIKit

enum HapTheme {
    static let zinc50 = Color(hex: 0xFAFAFA)
    static let zinc100 = Color(hex: 0xF4F4F5)
    static let zinc200 = Color(hex: 0xE4E4E7)
    static let zinc400 = Color(hex: 0xA1A1AA)
    static let zinc500 = Color(hex: 0x71717A)
    static let zinc700 = Color(hex: 0x3F3F46)
    static let zinc800 = Color(hex: 0x27272A)
    static let zinc900 = Color(hex: 0x18181B)
    static let zinc950 = Color(hex: 0x09090B)

    static let accent = dyn(light: 0x18181B, dark: 0xFAFAFA)
    static let onAccent = dyn(light: 0xFAFAFA, dark: 0x09090B)
    static let background = dyn(light: 0xFAFAFA, dark: 0x09090B)
    static let surface = dyn(light: 0xFFFFFF, dark: 0x18181B)
    static let surfaceInset = dyn(light: 0xF4F4F5, dark: 0x27272A)
    static let border = dynAlpha(light: 0x000000, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let borderStrong = dynAlpha(light: 0x000000, lightAlpha: 0.16, dark: 0xFFFFFF, darkAlpha: 0.14)
    static let textPrimary = dyn(light: 0x09090B, dark: 0xFAFAFA)
    static let textSecondary = dyn(light: 0x71717A, dark: 0xA1A1AA)
    static let textTertiary = dyn(light: 0xA1A1AA, dark: 0x71717A)

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 12
        static let row: CGFloat = 10
    }

    static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    static func dynAlpha(light: UInt32, lightAlpha: CGFloat, dark: UInt32, darkAlpha: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark).withAlphaComponent(darkAlpha)
                : UIColor(hex: light).withAlphaComponent(lightAlpha)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct HapPressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HapSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(HapTheme.textTertiary)
            .textCase(.uppercase)
            .kerning(0.4)
    }
}

struct HapCard<Content: View>: View {
    var padding: CGFloat = HapTheme.Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HapTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: HapTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HapTheme.Radius.card, style: .continuous)
                    .stroke(HapTheme.border, lineWidth: 1)
            )
    }
}
