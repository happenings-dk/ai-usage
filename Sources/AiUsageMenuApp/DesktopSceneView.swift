import SwiftUI

/// Connects the desktop scene's window action to the shared quick-access controller.
struct DesktopSceneView: View {
    @Environment(\.openWindow) private var openWindow

    let model: UsageViewModel
    let quickAccessController: QuickAccessController

    var body: some View {
        DesktopDashboardView(
            model: model,
            quickAccessShortcut: quickAccessController.shortcutSequence.displayName,
            showQuickAccess: quickAccessController.toggle
        )
        .onAppear(perform: configureQuickAccess)
    }

    private func configureQuickAccess() {
        quickAccessController.configure(
            model: model,
            openDashboard: openDashboard
        )
    }

    private func openDashboard() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: AiUsageMenuApp.dashboardWindowID)
    }
}
