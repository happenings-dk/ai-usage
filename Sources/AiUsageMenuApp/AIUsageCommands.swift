import SwiftUI

/// Keyboard commands available from the macOS menu bar.
struct AIUsageCommands: Commands {
    let model: UsageViewModel
    let quickAccessController: QuickAccessController

    var body: some Commands {
        CommandMenu("Usage") {
            Button(
                "Show Quick Look (\(quickAccessController.shortcutSequence.displayName))",
                action: quickAccessController.toggle
            )

            Button("Refresh Usage", action: model.refresh)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing)
        }
    }
}
