import AppKit
import Combine

/// Wires the independent layers together into the full discrete-mode
/// state machine:
///
///   regular use --tap CapsLock--> state.root
///   while active, DiscreteKeyboardCapture owns the whole keyboard and
///   routes trigger taps to the graph and typed keys to the native field;
///   the overlay re-renders after every change;
///   CapsLock from any state leaves discrete, cancelling any edit first.
///
/// Nothing below this file knows about any of the others.
final class AppCoordinator {
    private let settings = UserSettings()
    private let clickListener: CapsLockClickListener
    private let keyboardCapture: DiscreteKeyboardCapture
    private let graphStore: DiscreteGraphStore
    private let popup = PopupWindowController()
    private let windowBrowser = WindowBrowserController()
    private let filePicker = FilePicker()

    private var isDiscreteActive = false
    private var isWindowBrowserActive = false
    private var capsLockWasOnAtPressBegan = false
    private var settingsSubscription: AnyCancellable?

    init() {
        clickListener = CapsLockClickListener(settings: settings)
        keyboardCapture = DiscreteKeyboardCapture(settings: settings)
        graphStore = DiscreteGraphStore(settings: settings)

        clickListener.onClick = { [weak self] in
            self?.handleCapsLockClick()
        }
        clickListener.onPressBegan = { [weak self] time, wasCapsLockOn in
            guard let self, !self.isDiscreteActive else { return }
            self.capsLockWasOnAtPressBegan = wasCapsLockOn
            guard !wasCapsLockOn else { return }
            self.keyboardCapture.beginActivation(at: time)
        }
        clickListener.onHold = { [weak self] in
            self?.capsLockWasOnAtPressBegan = false
            self?.keyboardCapture.cancelActivation()
        }

        keyboardCapture.onTap = { [weak self] keyCode in
            guard let self else { return }
            if self.isWindowBrowserActive {
                self.windowBrowser.handleTap(keyCode)
            } else {
                self.graphStore.handleTap(keyCode)
            }
        }
        keyboardCapture.onTyped = { [weak self] key in
            self?.popup.handleKeyDown(key)
        }
        popup.onTextChanged = { [weak self] text, draftID in
            self?.graphStore.updateText(text, draftID: draftID)
        }
        popup.onTextCommand = { [weak self] command, draftID in
            self?.graphStore.handleTextCommand(command, draftID: draftID)
        }

        graphStore.onRunFile = { [weak self] fileURL in
            LeafActionRunner.run(fileURL)
            self?.exitDiscrete()
        }

        graphStore.onRunBuiltin = { [weak self] builtin, argument in
            guard let self else { return }
            if builtin.behavior == .windowsBrowser {
                self.openWindowBrowser()
            } else {
                BuiltinRunner.run(builtin, argument: argument)
            }
        }

        graphStore.onExitDiscrete = { [weak self] in
            self?.exitDiscrete()
        }

        graphStore.onOpenFile = { [weak self] url in
            // Search apps use the same policy as configured app resources.
            // Search files still open normally (including executable files).
            if url.pathExtension.lowercased() == "app" {
                ApplicationOpener.open(url)
            } else {
                if NSWorkspace.shared.open(url) { SearchUsageStore.shared.recordOpen(url) }
            }
            self?.exitDiscrete()
        }

        graphStore.onRequestFileSelect = { [weak self] in
            self?.pickFile()
        }

        graphStore.onStateChanged = { [weak self] in
            self?.syncCaptureMode()
            self?.renderOverlay()
        }

        windowBrowser.onCancel = { [weak self] in
            self?.closeWindowBrowser()
        }
        windowBrowser.onSelect = { [weak self] selection in
            self?.selectWindow(selection)
        }
    }

    func start() {
        SearchUsageStore.shared.observeApplications()
        AccessibilityPermission.requestIfNeeded()
        LoginItem.registerIfNeeded()
        // Keep the OS's CapsLock delay equal to the tap threshold, now and
        // whenever the setting changes (the publisher emits the current value first).
        settingsSubscription = settings.$clickHoldThreshold
            .removeDuplicates()
            .sink { CapsLockDelay.apply(threshold: $0) }
        keyboardCapture.observe()
        clickListener.start()
    }

    private func handleCapsLockClick() {
        let wasCapsLockOn = capsLockWasOnAtPressBegan
        capsLockWasOnAtPressBegan = false
        if isDiscreteActive {
            exitDiscrete()
        } else if wasCapsLockOn {
            // Turning Caps Lock off is regular computer use. In particular,
            // do not finish or replay an activation buffer.
            keyboardCapture.cancelActivation()
            print("⇪ Caps Lock was on — leaving Discrete inactive")
        } else {
            enterDiscrete()
        }
    }

    private func enterDiscrete() {
        print("🟢 Entering discrete mode")
        isDiscreteActive = true
        // Keyboards may have been connected or removed since last time.
        KeyList.refreshAvailableKeys()
        keyboardCapture.mode = .triggers
        keyboardCapture.start()
        graphStore.enterRoot()
        // Replay synchronously so every key sees the mode/state produced by
        // the previous one, including a transition into search or a text editor.
        keyboardCapture.replayActivation()
    }

    /// Leaves discrete from any state. An edit in progress is cancelled
    /// first, so nothing half-finished is kept.
    private func exitDiscrete() {
        print("🔴 Exiting discrete mode")
        isDiscreteActive = false
        isWindowBrowserActive = false
        graphStore.cancelEditInProgress()
        filePicker.cancel()
        windowBrowser.hide()
        keyboardCapture.stop()
        popup.hide()
    }

    /// state.text_string and the searches read keys like a text field; everything else
    /// reads trigger taps. While the file picker is open discrete stops
    /// consuming keys entirely, so the picker can be used normally.
    private func syncCaptureMode() {
        guard isDiscreteActive else { return }
        if isWindowBrowserActive {
            keyboardCapture.mode = .triggers
            keyboardCapture.start()
            return
        }
        if case .selectingFile = graphStore.mode {
            keyboardCapture.stop()
        } else {
            keyboardCapture.mode = graphStore.mode.textDraft?.isTyping == true ? .typing : .triggers
            keyboardCapture.start()
        }
    }

    private func renderOverlay() {
        guard isDiscreteActive, !isWindowBrowserActive else { return }
        let content = OverlayRowBuilder.build(for: graphStore.currentState, mode: graphStore.mode)
        popup.show(content, settings: settings)
    }

    private func openWindowBrowser() {
        guard isDiscreteActive else { return }
        isWindowBrowserActive = true
        keyboardCapture.mode = .triggers
        popup.hide()
        windowBrowser.show()
    }

    private func closeWindowBrowser() {
        guard isDiscreteActive, isWindowBrowserActive else { return }
        isWindowBrowserActive = false
        windowBrowser.hide()
        syncCaptureMode()
        renderOverlay()
    }

    private func selectWindow(_ selection: WindowBrowserSelection) {
        guard isDiscreteActive, isWindowBrowserActive else { return }
        isWindowBrowserActive = false
        windowBrowser.hide()
        exitDiscrete()
        guard let app = NSRunningApplication(processIdentifier: selection.processID) else { return }
        ApplicationOpener.focusWindow(id: selection.windowID, app: app, followPointer: true) {}
    }

    private func pickFile() {
        guard case .selectingFile(let request) = graphStore.mode else { return }
        filePicker.pick(prompt: request.prompt) { [weak self] url in
            self?.graphStore.completeFileSelect(url)
        }
    }
}
