import SwiftUI

/// A SwiftUI wrapper around the native shortcut recorder button.
struct ShortcutRecorderView: NSViewRepresentable {
    let shortcutSequence: QuickAccessShortcutSequence
    let shortcutSequenceChanged: (QuickAccessShortcutSequence) -> Void
    let recordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(
            title: shortcutSequence.displayName,
            target: nil,
            action: nil
        )
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.shortcutSequence = shortcutSequence
        button.shortcutSequenceChanged = shortcutSequenceChanged
        button.recordingChanged = recordingChanged
        button.setAccessibilityLabel("Quick Look keyboard shortcut")
        button.setAccessibilityHelp(
            "Click, then press one or two shortcuts containing Command, Option, or Control"
        )
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcutSequence = shortcutSequence
        button.shortcutSequenceChanged = shortcutSequenceChanged
        button.recordingChanged = recordingChanged
    }
}
