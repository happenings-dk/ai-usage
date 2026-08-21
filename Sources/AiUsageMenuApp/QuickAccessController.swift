import Carbon.HIToolbox
import Observation
import SwiftUI

/// Owns the floating Quick Look panel and its system-wide keyboard shortcut.
@MainActor
@Observable
final class QuickAccessController {
    private static let hotKeySignature: OSType = 0x4149_5547
    private static let shortcutDefaultsKey = "quickAccessShortcut"
    private static let sequenceTimeout: TimeInterval = 1.5

    private(set) var shortcutSequence: QuickAccessShortcutSequence
    private(set) var shortcutRegistrationError: String?

    @ObservationIgnored
    private var model: UsageViewModel?
    @ObservationIgnored
    private var openDashboardAction: (() -> Void)?
    @ObservationIgnored
    private var panel: NSPanel?
    @ObservationIgnored
    private var hotKeyReferences: [EventHotKeyRef] = []
    @ObservationIgnored
    private var registeredShortcuts: [UInt32: QuickAccessShortcut] = [:]
    @ObservationIgnored
    private var sequenceProgress = 0
    @ObservationIgnored
    private var sequenceResetTask: Task<Void, Never>?
    @ObservationIgnored
    private var eventHandlerReference: EventHandlerRef?

    init() {
        shortcutSequence = Self.loadShortcutSequence()
        installGlobalHotKeyHandler()
        registerGlobalHotKeys(shortcutSequence)
    }

    /// Supplies the live model and scene action used by the panel.
    func configure(model: UsageViewModel, openDashboard: @escaping () -> Void) {
        self.model = model
        openDashboardAction = openDashboard
        updatePanelContent()
    }

    /// Shows or hides the Quick Look panel.
    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    /// Shows the Quick Look panel near the top of the active display.
    func show() {
        guard model != nil, openDashboardAction != nil else {
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        updatePanelContent()
        position(panel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the Quick Look panel without destroying its live SwiftUI content.
    func hide() {
        panel?.orderOut(nil)
    }

    /// Replaces the global shortcut and persists it when registration succeeds.
    func updateShortcutSequence(_ candidate: QuickAccessShortcutSequence) {
        let previousSequence = shortcutSequence
        unregisterGlobalHotKeys()

        guard registerGlobalHotKeys(candidate) else {
            let registrationError = shortcutRegistrationError
            _ = registerGlobalHotKeys(previousSequence)
            shortcutRegistrationError = registrationError
            return
        }

        shortcutSequence = candidate
        shortcutRegistrationError = nil
        saveShortcutSequence(candidate)
        updatePanelContent()
    }

    /// Restores the default Shift-Command-U shortcut.
    func resetShortcut() {
        updateShortcutSequence(.defaultSequence)
    }

    /// Temporarily releases the current hotkeys while the recorder has focus.
    func setShortcutRecording(_ isRecording: Bool) {
        if isRecording {
            unregisterGlobalHotKeys()
        } else if hotKeyReferences.isEmpty {
            _ = registerGlobalHotKeys(shortcutSequence)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "AI Usage Quick Look"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func updatePanelContent() {
        guard let model, let openDashboardAction else {
            return
        }

        let rootView = QuickUsageView(
            model: model,
            shortcutName: shortcutSequence.displayName,
            openDashboard: { [weak self] in
                self?.hide()
                openDashboardAction()
            },
            close: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel?.contentView = hostingView
        panel?.setContentSize(hostingView.fittingSize)
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let edgeInset = HappeningsTheme.Layout.windowEdgeInset
        let origin = NSPoint(
            x: min(
                max(visibleFrame.midX - (panelSize.width / 2), visibleFrame.minX + edgeInset),
                visibleFrame.maxX - panelSize.width - edgeInset
            ),
            y: max(
                visibleFrame.maxY - panelSize.height - edgeInset,
                visibleFrame.minY + edgeInset
            )
        )
        panel.setFrameOrigin(origin)
    }

    private func installGlobalHotKeyHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let controllerPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID(signature: 0, id: 0)
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else {
                    return status
                }

                let controller = Unmanaged<QuickAccessController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    controller.handleHotKey(identifier: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            controllerPointer,
            &eventHandlerReference
        )

    }

    @discardableResult
    private func registerGlobalHotKeys(_ sequence: QuickAccessShortcutSequence) -> Bool {
        clearRegisteredHotKeys(resetSequence: true)
        guard let firstShortcut = sequence.shortcuts.first,
              registerHotKey(firstShortcut, identifier: 1) else {
            clearRegisteredHotKeys(resetSequence: true)
            shortcutRegistrationError = "That shortcut is already in use. Try another combination."
            return false
        }
        return true
    }

    private func unregisterGlobalHotKeys() {
        clearRegisteredHotKeys(resetSequence: true)
    }

    private func clearRegisteredHotKeys(resetSequence: Bool) {
        for reference in hotKeyReferences {
            UnregisterEventHotKey(reference)
        }
        hotKeyReferences.removeAll()
        registeredShortcuts.removeAll()
        if resetSequence {
            sequenceResetTask?.cancel()
            sequenceResetTask = nil
            sequenceProgress = 0
        }
    }

    private func registerHotKey(
        _ shortcut: QuickAccessShortcut,
        identifier: UInt32
    ) -> Bool {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: identifier
        )
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            return false
        }
        registeredShortcuts[identifier] = shortcut
        hotKeyReferences.append(reference)
        return true
    }

    private func handleHotKey(identifier: UInt32) {
        guard let pressedShortcut = registeredShortcuts[identifier] else {
            return
        }

        if shortcutSequence.shortcuts.count == 1 {
            toggle()
            return
        }

        if sequenceProgress == 0,
           pressedShortcut == shortcutSequence.shortcuts.first {
            beginWaitingForSecondChord()
            return
        }

        if sequenceProgress == 1,
           pressedShortcut == shortcutSequence.shortcuts[1] {
            restoreInitialHotKey()
            toggle()
        }
    }

    private func beginWaitingForSecondChord() {
        sequenceProgress = 1
        clearRegisteredHotKeys(resetSequence: false)

        guard registerHotKey(shortcutSequence.shortcuts[1], identifier: 2) else {
            restoreInitialHotKey()
            shortcutRegistrationError = "The second shortcut is already in use. Try another combination."
            return
        }

        sequenceResetTask?.cancel()
        sequenceResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.sequenceTimeout))
            guard !Task.isCancelled else { return }
            self?.restoreInitialHotKey()
        }
    }

    private func restoreInitialHotKey() {
        sequenceResetTask?.cancel()
        sequenceResetTask = nil
        clearRegisteredHotKeys(resetSequence: false)
        sequenceProgress = 0

        guard let firstShortcut = shortcutSequence.shortcuts.first,
              registerHotKey(firstShortcut, identifier: 1) else {
            shortcutRegistrationError = "The shortcut could not be restored. Choose it again in Settings."
            return
        }
        shortcutRegistrationError = nil
    }

    private func saveShortcutSequence(_ sequence: QuickAccessShortcutSequence) {
        guard let data = try? JSONEncoder().encode(sequence) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.shortcutDefaultsKey)
    }

    private static func loadShortcutSequence() -> QuickAccessShortcutSequence {
        guard
            let data = UserDefaults.standard.data(forKey: shortcutDefaultsKey)
        else {
            return .defaultSequence
        }
        if let sequence = try? JSONDecoder().decode(
            QuickAccessShortcutSequence.self,
            from: data
        ) {
            return sequence
        }
        if let legacyShortcut = try? JSONDecoder().decode(QuickAccessShortcut.self, from: data),
           let sequence = QuickAccessShortcutSequence(shortcuts: [legacyShortcut]) {
            return sequence
        }
        return .defaultSequence
    }
}
