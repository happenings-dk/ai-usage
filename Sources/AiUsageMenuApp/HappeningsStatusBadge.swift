import SwiftUI

/// A compact status label that never relies on color alone.
struct HappeningsStatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.bold())
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, HappeningsTheme.Spacing.small)
            .padding(.vertical, HappeningsTheme.Spacing.compact)
            .background(color.opacity(0.12), in: .capsule)
    }
}
