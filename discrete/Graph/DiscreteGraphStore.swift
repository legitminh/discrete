import Combine
import CoreGraphics
import Foundation

/// The state machine the spec describes: walks the graph on trigger taps,
/// runs the configure menu and its sub-states, and drives the text and
/// file editors. Knows nothing about the overlay, keyboard capture, or
/// CapsLock — the coordinator feeds it input and reacts to its callbacks.
final class DiscreteGraphStore: ObservableObject {
    let root: DiscreteState

    @Published private(set) var currentState: DiscreteState
    @Published private(set) var mode: DiscreteMode = .navigating

    /// A function was triggered — the coordinator should run it and exit discrete.
    var onRunFunction: ((URL) -> Void)?
    /// Navigation, a mode change, or a graph edit happened — re-render.
    var onStateChanged: (() -> Void)?
    /// Entered state.file_select — the coordinator should open the file picker.
    var onRequestFileSelect: (() -> Void)?

    init() {
        if let loaded = GraphPersistence.load() {
            root = loaded
        } else {
            root = DiscreteState(name: "root")
            GraphPersistence.save(root: root)
        }
        currentState = root
    }

    func enterRoot() {
        currentState = root
        mode = .navigating
        onStateChanged?()
    }

    /// CapsLock while discrete is active: any edit in progress is cancelled
    /// exactly as Esc would, so nothing half-finished is kept. The
    /// coordinator then leaves discrete.
    func cancelEditInProgress() {
        switch mode {
        case .editingText(let request):
            request.cancel()
        case .selectingFile(let request):
            request.cancel()
        default:
            break
        }
        mode = .navigating
    }

    // MARK: - Input

    /// A trigger tap (the tap rule: fired on release, in press order).
    func handleTap(_ keyCode: CGKeyCode) {
        switch mode {
        case .navigating:
            handleNavigationTap(keyCode)
        case .configuring:
            handleConfiguringTap(keyCode)
        case .confirmingDelete:
            handleConfirmDeleteTap(keyCode)
        case .addingState:
            handleAddingStateTap(keyCode)
        case .addingFunction:
            handleAddingFunctionTap(keyCode)
        case .pickingFunction(let purpose):
            handlePickingFunctionTap(keyCode, purpose: purpose)
        case .pickingNewTrigger(let oldKey, let function):
            handlePickingNewTriggerTap(keyCode, oldKey: oldKey, function: function)
        case .editingText, .selectingFile:
            return
        }
        onStateChanged?()
    }

    /// A key typed while in state.text_string (normal key-down typing).
    func handleTyped(_ key: TypedKey) {
        guard case .editingText(var request) = mode else { return }

        switch key.keyCode {
        case KeyCode.enter, KeyCode.keypadEnter:
            mode = .navigating
            request.save(request.buffer.text)
        case KeyCode.escape:
            mode = .navigating
            request.cancel()
        default:
            request.buffer.apply(key)
            mode = .editingText(request)
        }
        onStateChanged?()
    }

    /// The file picker finished: a file was chosen, or it was cancelled (nil).
    func completeFileSelect(_ url: URL?) {
        guard case .selectingFile(let request) = mode else { return }
        mode = .navigating
        if let url {
            request.save(url)
        } else {
            request.cancel()
        }
        onStateChanged?()
    }

    // MARK: - state.?

    private func handleNavigationTap(_ keyCode: CGKeyCode) {
        let reserved = KeyList.reservedSlots(for: currentState)

        if keyCode == reserved.configure {
            mode = .configuring
            return
        }
        if keyCode == reserved.back, let parent = currentState.parent {
            currentState = parent
            return
        }
        switch currentState.actions[keyCode] {
        case .transition(let child):
            currentState = child
        case .function(let function):
            onRunFunction?(function.fileURL)
        case nil:
            return
        }
    }

    // MARK: - state.?.conf

    private func handleConfiguringTap(_ keyCode: CGKeyCode) {
        typealias Slots = KeyList.ConfigureSlots

        switch keyCode {
        case KeyCode.escape:
            mode = .navigating
        case Slots.nameState:
            let state = currentState
            mode = .editingText(TextEditRequest(
                prompt: "name this state",
                save: { [weak self] text in
                    state.name = text
                    self?.persist()
                    self?.mode = .configuring
                },
                cancel: { [weak self] in self?.mode = .configuring }
            ))
        case Slots.deleteState where currentState.parent != nil:
            mode = .confirmingDelete
        case Slots.newState:
            mode = .addingState
        case Slots.addFunction:
            mode = .addingFunction
        case Slots.deleteFunction where currentState.hasFunctions:
            mode = .pickingFunction(.delete)
        case Slots.renameFunction where currentState.hasFunctions:
            mode = .pickingFunction(.rename)
        case Slots.setFunctionTrigger where currentState.hasFunctions:
            mode = .pickingFunction(.setTrigger)
        default:
            return
        }
    }

    /// The same key again deletes; anything else backs out to the menu.
    private func handleConfirmDeleteTap(_ keyCode: CGKeyCode) {
        guard keyCode == KeyList.ConfigureSlots.deleteState,
              let parent = currentState.parent,
              let key = parent.key(of: currentState) else {
            mode = .configuring
            return
        }
        parent.actions.removeValue(forKey: key)
        currentState = parent
        mode = .navigating
        persist()
    }

    /// The new state is only created once it's named, so "exit" or
    /// cancelling the name leaves nothing behind.
    private func handleAddingStateTap(_ keyCode: CGKeyCode) {
        if keyCode == KeyCode.escape {
            mode = .navigating
            return
        }
        guard isUnoccupied(keyCode) else { return }

        let parent = currentState
        mode = .editingText(TextEditRequest(
            prompt: "name the new state",
            save: { [weak self] text in
                parent.actions[keyCode] = .transition(DiscreteState(name: text, parent: parent))
                self?.persist()
                self?.mode = .navigating
            },
            cancel: { [weak self] in self?.mode = .navigating }
        ))
    }

    /// Key → name → file. The function is only added once it has a file,
    /// so cancelling at any step leaves nothing behind.
    private func handleAddingFunctionTap(_ keyCode: CGKeyCode) {
        if keyCode == KeyCode.escape {
            mode = .navigating
            return
        }
        guard isUnoccupied(keyCode) else { return }

        let parent = currentState
        mode = .editingText(TextEditRequest(
            prompt: "name the new function",
            save: { [weak self] name in
                self?.mode = .selectingFile(FileSelectRequest(
                    prompt: "choose a file, script, or app for \"\(name)\"",
                    save: { url in
                        parent.actions[keyCode] = .function(DiscreteFunction(name: name, fileURL: url))
                        self?.persist()
                        self?.mode = .navigating
                    },
                    cancel: { self?.mode = .navigating }
                ))
                self?.onRequestFileSelect?()
            },
            cancel: { [weak self] in self?.mode = .navigating }
        ))
    }

    private func handlePickingFunctionTap(_ keyCode: CGKeyCode, purpose: FunctionPickerPurpose) {
        if keyCode == KeyCode.escape {
            mode = .navigating
            return
        }
        guard let trigger = KeyList.functionSelectionKeys(for: currentState)[keyCode],
              case .function(let function) = currentState.actions[trigger] else { return }

        switch purpose {
        case .delete:
            currentState.actions.removeValue(forKey: trigger)
            mode = .navigating
            persist()
        case .rename:
            mode = .editingText(TextEditRequest(
                prompt: "rename \"\(function.name)\"",
                save: { [weak self] text in
                    function.name = text
                    self?.persist()
                    self?.mode = .navigating
                },
                cancel: { [weak self] in self?.mode = .navigating }
            ))
        case .setTrigger:
            mode = .pickingNewTrigger(oldKey: trigger, function: function)
        }
    }

    /// Esc leaves the trigger unchanged; an occupied key is ignored.
    private func handlePickingNewTriggerTap(_ keyCode: CGKeyCode, oldKey: CGKeyCode, function: DiscreteFunction) {
        if keyCode == KeyCode.escape {
            mode = .navigating
            return
        }
        guard isUnoccupied(keyCode) else { return }
        currentState.actions.removeValue(forKey: oldKey)
        currentState.actions[keyCode] = .function(function)
        mode = .navigating
        persist()
    }

    // MARK: - Helpers

    /// Free for a new user binding in the current state. The keys shown
    /// for configure/back count as free — binding one just moves them.
    private func isUnoccupied(_ keyCode: CGKeyCode) -> Bool {
        KeyList.isBindable(keyCode) && currentState.actions[keyCode] == nil
    }

    private func persist() {
        GraphPersistence.save(root: root)
    }
}
