import Combine
import CoreGraphics
import Foundation

/// The graph-walking equivalent of `DiscreteSignalGenerator` one layer up:
/// consumes key input while discrete mode is active and turns it into
/// graph navigation, an editing-mode change, or running a leaf action.
/// Knows nothing about the overlay UI, keyboard capture, or CapsLock —
/// just the graph. `currentState` never changes while in a non-navigating
/// mode: "configure" and everything under it are edits layered on top of
/// the state you were already on, not new nodes you visit.
final class DiscreteGraphStore: ObservableObject {
    let root: DiscreteState

    @Published private(set) var currentState: DiscreteState
    @Published private(set) var mode: DiscreteMode = .navigating

    /// A state with a script attached was reached — the coordinator should run it and exit discrete.
    var onEnterLeaf: ((URL) -> Void)?
    /// Navigation, a mode change, or a graph edit happened — re-render.
    var onStateChanged: (() -> Void)?
    /// "add an action" finished naming its new leaf — the coordinator should open the script picker.
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

        case .namingNewLeaf(let target, var buffer):
            guard !characters.isEmpty else { return }
            buffer += characters
            mode = .namingNewLeaf(target: target, buffer: buffer)

        case .configuring:
            handleConfiguringKey(keyCode)

        case .addingState:
            handleAddingStateKey(keyCode)

        case .addingAction:
            handleAddingActionKey(keyCode)

        case .pickingAction(let purpose):
            handlePickingActionKey(keyCode, purpose: purpose)

        case .pickingNewTrigger(let oldKey, let target):
            handlePickingNewTriggerKey(keyCode, oldKey: oldKey, target: target)

        case .navigating:
            handleNavigationKey(keyCode)
        }
        onStateChanged?()
    }

    /// CapsLock, while naming — commits the buffer as `target`'s name.
    /// For `.namingNewLeaf` this also kicks off the script picker; for
    /// plain `.namingState` it returns straight to navigating.
    func commitName() {
        switch mode {
        case .namingState(let target, let buffer):
            applyName(buffer, to: target)
            mode = .navigating
            persist()
            onStateChanged?()

        case .namingNewLeaf(let target, let buffer):
            applyName(buffer, to: target)
            mode = .navigating
            persist()
            onStateChanged?()
            onRequestScriptPick?(target)

        default:
            return
        }
    }

    /// CapsLock, while in any editing mode other than naming — abandons the edit.
    func cancel() {
        mode = .navigating
        onStateChanged?()
    }

    /// The tail end of "add an action": attach the picked script, then return to navigating.
    func setScript(_ url: URL, for state: DiscreteState) {
        state.scriptURL = url
        mode = .navigating
        persist()
        onStateChanged?()
    }

    /// "add an action," abandoned by cancelling the script picker: removes
    /// the key binding and state `handleAddingActionKey`/`commitName`
    /// already created for it. Without this, a cancelled pick left behind
    /// a plain, scriptless, navigable state — indistinguishable from one
    /// made via "add state" — instead of the transition-that-calls-a-script
    /// the spec calls for. "add an action" now either fully completes
    /// (bound, named, scripted) or leaves no trace at all.
    func discardPendingAction(_ state: DiscreteState) {
        guard let parent = state.parent,
              let triggerKey = parent.children.first(where: { $0.value === state })?.key else {
            return
        }
        parent.children.removeValue(forKey: triggerKey)
        persist()
        onStateChanged?()
    }

    private func handleNavigationKey(_ keyCode: CGKeyCode) {
        let reserved = KeyList.reservedSlots(for: currentState)

        if keyCode == reserved.back?.keyCode {
            goBack()
            return
        }
        if keyCode == reserved.configure?.keyCode {
            mode = .configuring
            return
        }
        if let child = currentState.children[keyCode] {
            enter(child)
        }
    }

    private func handleConfiguringKey(_ keyCode: CGKeyCode) {
        let slots = KeyList.configureSlots(for: currentState)

        if keyCode == slots.addState?.keyCode {
            mode = .addingState
        } else if keyCode == slots.addAction?.keyCode {
            mode = .addingAction
        } else if keyCode == slots.renameAction?.keyCode {
            mode = .pickingAction(purpose: .rename)
        } else if keyCode == slots.setTrigger?.keyCode {
            mode = .pickingAction(purpose: .setTrigger)
        } else if keyCode == slots.deleteAction?.keyCode {
            mode = .pickingAction(purpose: .delete)
        } else if keyCode == slots.deleteState?.keyCode {
            deleteCurrentState()
        } else if keyCode == slots.renameState?.keyCode {
            mode = .namingState(target: currentState, buffer: "")
        }
    }

    /// An unoccupied key creates a new child bound to it, then moves into
    /// naming it — "[?] create new action" per spec (yes, for a state too).
    private func handleAddingStateKey(_ keyCode: CGKeyCode) {
        guard currentState.children[keyCode] == nil else { return }
        let child = DiscreteState(parent: currentState)
        currentState.children[keyCode] = child
        persist()
        mode = .namingState(target: child, buffer: "")
    }

    /// Same as `handleAddingStateKey`, but naming chains into the script
    /// picker on commit (via `.namingNewLeaf`) instead of just saving.
    private func handleAddingActionKey(_ keyCode: CGKeyCode) {
        guard currentState.children[keyCode] == nil else { return }
        let child = DiscreteState(parent: currentState)
        currentState.children[keyCode] = child
        persist()
        mode = .namingNewLeaf(target: child, buffer: "")
    }

    /// Pressing an existing action's own trigger key selects it for
    /// `purpose`. Only matches children that are actions (have a script
    /// attached via "add an action") — the spec calls this a "list of
    /// actions" (twice, for set-trigger and delete), not a list of
    /// children in general. A plain sub-state made via "add state" is
    /// renamed/retargeted/deleted through its *own* configure menu
    /// ("rename this state"/"delete this state"), not from here.
    private func handlePickingActionKey(_ keyCode: CGKeyCode, purpose: ActionPickerPurpose) {
        guard let target = currentState.children[keyCode], target.scriptURL != nil else { return }

        switch purpose {
        case .rename:
            mode = .namingState(target: target, buffer: "")
        case .setTrigger:
            mode = .pickingNewTrigger(oldKey: keyCode, target: target)
        case .delete:
            currentState.children.removeValue(forKey: keyCode)
            mode = .navigating
            persist()
        }
    }

    private func handlePickingNewTriggerKey(_ keyCode: CGKeyCode, oldKey: CGKeyCode, target: DiscreteState) {
        guard currentState.children[keyCode] == nil else { return }
        currentState.children.removeValue(forKey: oldKey)
        currentState.children[keyCode] = target
        mode = .navigating
        persist()
    }

    /// "delete this state ... delete the state and transition to the
    /// state's parent" — only reachable when `configureSlots` offered the
    /// slot at all, which already requires a parent to exist.
    private func deleteCurrentState() {
        guard let parent = currentState.parent,
              let triggerKey = parent.children.first(where: { $0.value === currentState })?.key else {
            return
        }
        parent.children.removeValue(forKey: triggerKey)
        currentState = parent
        mode = .navigating
        persist()
    }

    private func applyName(_ buffer: String, to target: DiscreteState) {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            target.name = trimmed
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
