import AppKit
import Carbon.HIToolbox

/// A native button that records one modified keyboard chord.
final class ShortcutRecorderButton: NSButton {
    var shortcutSequence = QuickAccessShortcutSequence.defaultSequence {
        didSet {
            guard !isRecording else {
                return
            }
            title = shortcutSequence.displayName
        }
    }

    var shortcutSequenceChanged: ((QuickAccessShortcutSequence) -> Void)?
    var recordingChanged: ((Bool) -> Void)?
    private var isRecording = false
    private var pendingShortcuts: [QuickAccessShortcut] = []
    private var commitTimer: Timer?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording(commit: false)
            return
        }
        if event.keyCode == UInt16(kVK_Return), !pendingShortcuts.isEmpty {
            finishRecording(commit: true)
            return
        }

        guard let shortcut = QuickAccessShortcut(event: event) else {
            NSSound.beep()
            title = "Add ⌘, ⌥, or ⌃"
            return
        }

        pendingShortcuts.append(shortcut)
        if pendingShortcuts.count == QuickAccessShortcutSequence.maximumChordCount {
            finishRecording(commit: true)
            return
        }

        title = "\(shortcut.displayName) → …"
        commitTimer?.invalidate()
        commitTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishRecording(commit: true)
            }
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecording {
            finishRecording(commit: !pendingShortcuts.isEmpty)
        }
        return didResign
    }

    private func beginRecording() {
        isRecording = true
        recordingChanged?(true)
        pendingShortcuts.removeAll()
        commitTimer?.invalidate()
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    private func finishRecording(commit: Bool) {
        commitTimer?.invalidate()
        commitTimer = nil
        if commit,
           let sequence = QuickAccessShortcutSequence(shortcuts: pendingShortcuts) {
            shortcutSequence = sequence
            shortcutSequenceChanged?(sequence)
        }
        pendingShortcuts.removeAll()
        isRecording = false
        title = shortcutSequence.displayName
        recordingChanged?(false)
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }
}
