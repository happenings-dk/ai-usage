import SwiftUI

@main
struct AiUsageMenuApp: App {
    @State private var model = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsageDashboardView(model: model)
                .frame(width: 390)
        } label: {
            Label {
                Text(model.menuBarTitle)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "chart.bar.xaxis")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(width: 440)
                .padding(20)
        }
    }
}
