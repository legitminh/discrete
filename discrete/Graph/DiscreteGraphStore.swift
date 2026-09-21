import Combine
import CoreGraphics
import Foundation

/// The graph-walking equivalent of `DiscreteSignalGenerator` one layer up:
/// consumes key input while discrete mode is active and turns it into
/// graph navigation, a mini-mode edit, or a leaf action. Knows nothing
/// about the overlay UI, keyboard capture, or CapsLock — just the graph.
final class DiscreteGraphStore: ObservableObject {
    let root: DiscreteState

    @Published private(set) var currentState: DiscreteState
    @Published private(set) var mode: DiscreteMode = .navigating

    /// A leaf action was reached — the coordinator should run it and exit discrete.
    var onEnterLeaf: ((URL) -> Void)?
    /// Navigation, a mini-mode change, or a leaf assignment happened — re-render.
    var onStateChanged: (() -> Void)?
    /// The leaf "pick a script" action was invoked for `state`.
    var onRequestScriptPick: ((DiscreteState) -> Void)?

    init() {
        if let loaded = GraphPersistence.load() {
            root = loaded
        } else {
            let newRoot = DiscreteState(name: "home")
            let settings = DiscreteState(name: "settings", parent: newRoot)
            newRoot.children[KeyList.delete.keyCode] = settings
            root = newRoot
            GraphPersistence.save(root: newRoot)
        }
        currentState = root
    }

    func enterRoot() {
        currentState = root
        mode = .navigating
        onStateChanged?()
    }

    func handleKeyDown(_ keyCode: CGKeyCode, characters: String) {
        switch mode {
        case .namingState(var buffer):
            guard !characters.isEmpty else { return }
            buffer += characters
            mode = .namingState(buffer: buffer)

        case .settingArguments:
            bindNewAction(for: keyCode)

        case .navigating:
            handleNavigationKey(keyCode)
        }
        onStateChanged?()
    }

    /// CapsLock, while naming a state — commits `mode`'s buffer as the name.
    func commitName() {
        guard case .namingState(let buffer) = mode else { return }
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            currentState.name = trimmed
        }
        mode = .navigating
        persist()
        onStateChanged?()
    }

    /// CapsLock, while setting arguments — abandons the new binding.
    func cancelSettingArguments() {
        mode = .navigating
        onStateChanged?()
    }

    func setScript(_ url: URL, for state: DiscreteState) {
        state.scriptURL = url
        persist()
        onStateChanged?()
    }

    private func handleNavigationKey(_ keyCode: CGKeyCode) {
        let reserved = KeyList.reservedSlots(for: currentState)

        if keyCode == reserved.name?.keyCode {
            mode = .namingState(buffer: "")
            return
        }
        if keyCode == reserved.arguments?.keyCode {
            mode = .settingArguments
            return
        }
        if keyCode == reserved.back?.keyCode {
            goBack()
            return
        }
        if keyCode == reserved.pickScript?.keyCode {
            onRequestScriptPick?(currentState)
            return
        }
        if let child = currentState.children[keyCode] {
            enter(child)
        }
    }

    private func bindNewAction(for keyCode: CGKeyCode) {
        let reserved = KeyList.reservedSlots(for: currentState)
        let reservedKeyCodes = [reserved.name, reserved.arguments, reserved.back, reserved.pickScript]
            .compactMap { $0?.keyCode }

        guard currentState.children[keyCode] == nil, !reservedKeyCodes.contains(keyCode) else {
            mode = .navigating
            return
        }

        let child = DiscreteState(parent: currentState)
        currentState.children[keyCode] = child
        mode = .navigating
        persist()
    }

    private func enter(_ state: DiscreteState) {
        if let scriptURL = state.scriptURL {
            onEnterLeaf?(scriptURL)
            return
        }
        currentState = state
        mode = .navigating
    }

    private func goBack() {
        guard let parent = currentState.parent else { return }
        currentState = parent
        mode = .navigating
    }

    private func persist() {
        GraphPersistence.save(root: root)
    }
}
