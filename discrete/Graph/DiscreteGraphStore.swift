import Combine
import CoreGraphics
import Foundation

/// The graph-walking equivalent of `DiscreteSignalGenerator` one layer up:
/// consumes key input while discrete mode is active and turns it into
/// graph navigation, an editing-mode change, or running a leaf action.
/// Knows nothing about the overlay UI, keyboard capture, or CapsLock —
/// just the graph. `currentState` never changes while in a non-navigating
/// mode: "set node actions" and "action configuration" are edits layered
/// on top of the state you were already on, not new nodes you visit.
final class DiscreteGraphStore: ObservableObject {
    let root: DiscreteState

    @Published private(set) var currentState: DiscreteState
    @Published private(set) var mode: DiscreteMode = .navigating

    /// A state with a script attached was reached — the coordinator should run it and exit discrete.
    var onEnterLeaf: ((URL) -> Void)?
    /// Navigation, a mode change, or a graph edit happened — re-render.
    var onStateChanged: (() -> Void)?
    /// The "set action" step (inside action configuration) was invoked for `state`.
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
        case .namingState(let target, var buffer):
            guard !characters.isEmpty else { return }
            buffer += characters
            mode = .namingState(target: target, buffer: buffer)

        case .settingActions:
            handleSettingActionsKey(keyCode)

        case .editingAction(let triggerKey, let target):
            handleEditingActionKey(keyCode, triggerKey: triggerKey, target: target)

        case .navigating:
            handleNavigationKey(keyCode)
        }
        onStateChanged?()
    }

    /// CapsLock, while naming a state — commits `mode`'s buffer as `target`'s name.
    func commitName() {
        guard case .namingState(let target, let buffer) = mode else { return }
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            target.name = trimmed
        }
        mode = .navigating
        persist()
        onStateChanged?()
    }

    /// CapsLock, while in "set node actions" or "action configuration" — abandons the edit.
    func cancel() {
        mode = .navigating
        onStateChanged?()
    }

    /// The "set action" step: attach a script to `state`, then return to navigating.
    func setScript(_ url: URL, for state: DiscreteState) {
        state.scriptURL = url
        mode = .navigating
        persist()
        onStateChanged?()
    }

    private func handleNavigationKey(_ keyCode: CGKeyCode) {
        let reserved = KeyList.reservedSlots(for: currentState)

        if keyCode == reserved.back?.keyCode {
            goBack()
            return
        }
        if keyCode == reserved.actions?.keyCode {
            mode = .settingActions
            return
        }
        if keyCode == reserved.name?.keyCode {
            mode = .namingState(target: currentState, buffer: "")
            return
        }
        if let child = currentState.children[keyCode] {
            enter(child)
        }
    }

    /// Inside "set node actions": an occupied key opens action
    /// configuration for that action; an unoccupied one creates a new
    /// child bound to it and returns straight to navigating.
    private func handleSettingActionsKey(_ keyCode: CGKeyCode) {
        if let child = currentState.children[keyCode] {
            mode = .editingAction(triggerKey: keyCode, target: child)
            return
        }

        let child = DiscreteState(parent: currentState)
        currentState.children[keyCode] = child
        mode = .navigating
        persist()
    }

    /// Inside "action configuration": rename / set action / delete, keyed
    /// off `target`'s own unoccupied keys (workplan-independent — this is
    /// the spec's new, explicit mechanism).
    private func handleEditingActionKey(_ keyCode: CGKeyCode, triggerKey: CGKeyCode, target: DiscreteState) {
        let slots = KeyList.actionEditSlots(for: target)

        if keyCode == slots.rename?.keyCode {
            mode = .namingState(target: target, buffer: "")
            return
        }
        if keyCode == slots.setAction?.keyCode {
            onRequestScriptPick?(target)
            return
        }
        if keyCode == slots.delete?.keyCode {
            // "delete the editing action and its state from the system.
            // return to the action's parent state" — currentState never
            // moved, so it already *is* that parent state.
            currentState.children.removeValue(forKey: triggerKey)
            mode = .navigating
            persist()
            return
        }
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
