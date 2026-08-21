import SwiftUI

/// A flat, bordered content surface from the Happenings design system.
struct HappeningsCard<Content: View>: View {
    private let padding: Double
    private let fillsAvailableHeight: Bool
    @ViewBuilder private let content: Content

    init(
        padding: Double = HappeningsTheme.Spacing.generous,
        fillsAvailableHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.fillsAvailableHeight = fillsAvailableHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsAvailableHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .background(HappeningsTheme.surface, in: .rect(cornerRadius: HappeningsTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: HappeningsTheme.Radius.card)
                    .stroke(HappeningsTheme.border, lineWidth: 1)
            }
    }
}
