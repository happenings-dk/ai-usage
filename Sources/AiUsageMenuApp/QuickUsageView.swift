import SwiftUI

/// A floating, glanceable usage surface shown by the global shortcut.
struct QuickUsageView: View {
    let model: UsageViewModel
    let shortcutName: String
    let openDashboard: () -> Void
    let close: () -> Void

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            QuickPanelContent(
                model: model,
                shortcutName: shortcutName,
                openDashboard: openDashboard,
                close: close
            )
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            materialContent
        }
        #else
        materialContent
        #endif
    }

    private var materialContent: some View {
        QuickPanelContent(
            model: model,
            shortcutName: shortcutName,
            openDashboard: openDashboard,
            close: close
        )
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(HappeningsTheme.borderStrong, lineWidth: 1)
        }
    }
}
