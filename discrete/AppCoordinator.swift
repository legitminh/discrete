import AppKit
import Combine

/// Wires the independent layers together into the full discrete-mode
/// state machine:
///
///   regular use --tap CapsLock--> state.root
///   while active, DiscreteKeyboardCapture owns the whole keyboard and
///   feeds taps (or, in state.text_string, typed keys) into
///   DiscreteGraphStore; the overlay re-renders after every change;
///   CapsLock from any state leaves discrete, cancelling any edit first.
///
/// Nothing below this file knows about any of the others.
final class AppCoordinator {
    private let settings = UserSettings()
    private let clickListener: CapsLockClickListener
    private let keyboardCapture: DiscreteKeyboardCapture
    private let graphStore = DiscreteGraphStore()
    private let popup = PopupWindowController()
    private let filePicker = FilePicker()

    private var isDiscreteActive = false
    private var settingsSubscription: AnyCancellable?

    init() {
        clickListener = CapsLockClickListener(settings: settings)
        keyboardCapture = DiscreteKeyboardCapture(settings: settings)

        clickListener.onClick = { [weak self] in
            self?.handleCapsLockClick()
        }

        keyboardCapture.onTap = { [weak self] keyCode in
            self?.graphStore.handleTap(keyCode)
        }
        keyboardCapture.onTyped = { [weak self] key in
            self?.graphStore.handleTyped(key)
        }

        graphStore.onRunFunction = { [weak self] fileURL in
            LeafActionRunner.run(fileURL)
            self?.exitDiscrete()
        }

        graphStore.onRequestFileSelect = { [weak self] in
            self?.pickFile()
        }

        graphStore.onStateChanged = { [weak self] in
            self?.syncCaptureMode()
            self?.renderOverlay()
        }
    }

    func start() {
        AccessibilityPermission.requestIfNeeded()
        LoginItem.registerIfNeeded()
        // Keep the OS's CapsLock delay equal to the tap threshold, now and
        // whenever the setting changes (the publisher emits the current value first).
        settingsSubscription = settings.$clickHoldThreshold
            .removeDuplicates()
            .sink { CapsLockDelay.apply(threshold: $0) }
        clickListener.start()
    }

    private func handleCapsLockClick() {
        if isDiscreteActive {
            exitDiscrete()
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
    }

    /// Leaves discrete from any state. An edit in progress is cancelled
    /// first, exactly as Esc would, so nothing half-finished is kept.
    private func exitDiscrete() {
        print("🔴 Exiting discrete mode")
        isDiscreteActive = false
        graphStore.cancelEditInProgress()
        filePicker.cancel()
        keyboardCapture.stop()
        popup.hide()
    }

    /// state.text_string reads keys like a text field; everything else
    /// reads trigger taps. While the file picker is open discrete stops
    /// consuming keys entirely, so the picker can be used normally.
    private func syncCaptureMode() {
        guard isDiscreteActive else { return }
        switch graphStore.mode {
        case .editingText:
            keyboardCapture.mode = .typing
            keyboardCapture.start()
        case .selectingFile:
            keyboardCapture.stop()
        default:
            keyboardCapture.mode = .triggers
            keyboardCapture.start()
        }
    }

    private func renderOverlay() {
        guard isDiscreteActive else { return }
        let content = OverlayRowBuilder.build(for: graphStore.currentState, mode: graphStore.mode)
        popup.show(content)
    }

    private func pickFile() {
        guard case .selectingFile(let request) = graphStore.mode else { return }
        filePicker.pick(prompt: request.prompt) { [weak self] url in
            self?.graphStore.completeFileSelect(url)
        }
    }
}
