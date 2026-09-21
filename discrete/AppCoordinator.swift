/// Wires the independent layers together into the full discrete-mode
/// state machine:
///
///   regular use --tap CapsLock--> discrete.home (graph root)
///   while active, DiscreteKeyboardCapture owns the whole keyboard and
///   feeds every key into DiscreteGraphStore, which walks the graph;
///   the overlay re-renders after every change; CapsLock's meaning
///   depends on the graph's current mode (exit / commit name / cancel).
///
/// Nothing below this file knows about any of the others.
final class AppCoordinator {
    private let settings = UserSettings()
    private let clickListener: CapsLockClickListener
    private let keyboardCapture = DiscreteKeyboardCapture()
    private let graphStore = DiscreteGraphStore()
    private let popup = PopupWindowController()

    private var isDiscreteActive = false

    init() {
        clickListener = CapsLockClickListener(settings: settings)
        clickListener.onClick = { [weak self] in
            self?.handleCapsLockClick()
        }

        keyboardCapture.onKeyDown = { [weak self] captured in
            self?.graphStore.handleKeyDown(captured.keyCode, characters: captured.characters)
        }

        graphStore.onEnterLeaf = { [weak self] scriptURL in
            LeafActionRunner.run(scriptURL)
            self?.exitDiscrete()
        }

        graphStore.onRequestScriptPick = { [weak self] state in
            self?.pickScript(for: state)
        }

        graphStore.onStateChanged = { [weak self] in
            self?.renderOverlay()
        }
    }

    func start() {
        AccessibilityPermission.requestIfNeeded()
        LoginItem.registerIfNeeded()
        clickListener.start()
    }

    private func handleCapsLockClick() {
        guard isDiscreteActive else {
            enterDiscrete()
            return
        }

        switch graphStore.mode {
        case .namingState:
            graphStore.commitName()
        case .settingArguments:
            graphStore.cancelSettingArguments()
        case .navigating:
            exitDiscrete()
        }
    }

    private func enterDiscrete() {
        print("🟢 Entering discrete mode")
        isDiscreteActive = true
        graphStore.enterRoot()
        keyboardCapture.start()
        renderOverlay()
    }

    private func exitDiscrete() {
        print("🔴 Exiting discrete mode")
        isDiscreteActive = false
        keyboardCapture.stop()
        popup.hide()
    }

    private func renderOverlay() {
        guard isDiscreteActive else { return }
        let rows = OverlayRowBuilder.rows(for: graphStore.currentState, mode: graphStore.mode)
        popup.showRows(rows)
    }

    private func pickScript(for state: DiscreteState) {
        ScriptPicker.pick { [weak self] url in
            guard let self, let url else { return }
            graphStore.setScript(url, for: state)
        }
    }
}
