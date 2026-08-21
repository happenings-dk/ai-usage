import SwiftUI

/// A floating, glanceable usage surface shown by the global shortcut.
struct QuickUsageView: View {
    let model: UsageViewModel
    let shortcutName: String
    let openDashboard: () -> Void
    let close: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            QuickPanelContent(
                model: model,
                shortcutName: shortcutName,
                openDashboard: openDashboard,
                close: close
            )
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
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
}
