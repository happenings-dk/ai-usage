import SwiftUI

/// Quiet freshness and keyboard shortcut metadata for the desktop view.
struct DesktopFooterView: View {
    let updatedAt: Date
    let isInitialLoading: Bool
    let quickAccessShortcut: String

    var body: some View {
        HStack(spacing: HappeningsTheme.Spacing.standard) {
            Text(isInitialLoading ? "Scanning local AI usage logs…" : "Updated \(TimeFormat.relative(updatedAt))")
            Spacer()
            Text("Quick Look  \(quickAccessShortcut)")
            Text("Refresh  ⌘R")
        }
        .font(.caption)
        .foregroundStyle(HappeningsTheme.textTertiary)
    }
}
