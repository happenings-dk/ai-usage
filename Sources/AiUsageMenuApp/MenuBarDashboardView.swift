import SwiftUI

/// Adapts the menu-bar dashboard to the app's shared window actions.
struct MenuBarDashboardView: View {
    @Environment(\.openWindow) private var openWindow

    let model: UsageViewModel
    let quickAccessController: QuickAccessController

    var body: some View {
        UsageDashboardView(
            model: model,
            openDashboard: openDashboard,
            showQuickAccess: quickAccessController.toggle
        )
        .frame(width: 390, height: 820)
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
