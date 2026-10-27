import Combine
import CoreGraphics
import Foundation
import AppKit

/// The state machine the spec describes: walks the graph on trigger taps,
/// runs the configure menu and its sub-states, and drives the text, file
/// and builtin editors. Knows nothing about the overlay, keyboard capture, or
/// CapsLock — the coordinator feeds it input and reacts to its callbacks.
final class DiscreteGraphStore: ObservableObject {
    let root: DiscreteState

    @Published private(set) var currentState: DiscreteState
    @Published private(set) var mode: DiscreteMode = .navigating

    /// A function with a file target was triggered — the coordinator
    /// should run the file and exit discrete.
    var onRunFile: ((URL) -> Void)?
    /// A builtin that acts outside discrete was triggered — the
    /// coordinator should run it (with its argument).
    var onRunBuiltin: ((BuiltinFunction, String?) -> Void)?
    /// A builtin that doesn't stay active finished — exit discrete.
    var onExitDiscrete: (() -> Void)?
    /// Navigation, a mode change, or a graph edit happened — re-render.
    var onStateChanged: (() -> Void)?
    /// Entered state.file_select — the coordinator should open the file picker.
    var onRequestFileSelect: (() -> Void)?
    /// An app or file was picked in state.search — the coordinator should
    /// open it and exit discrete.
    var onOpenFile: ((URL) -> Void)?

    private let settings: UserSettings
    private let searchEngine: SearchEngine
    private let saveGraph: (DiscreteState) -> Void
    private let readClipboard: () -> String?
    private let writeClipboard: (String) -> Void

    init(settings: UserSettings, root initialRoot: DiscreteState? = nil,
         saveGraph: @escaping (DiscreteState) -> Void = { GraphPersistence.save(root: $0) },
         readClipboard: @escaping () -> String? = { NSPasteboard.general.string(forType: .string) },
         writeClipboard: @escaping (String) -> Void = { text in
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString(text, forType: .string)
         }) {
        self.settings = settings
        self.saveGraph = saveGraph
        self.readClipboard = readClipboard
        self.writeClipboard = writeClipboard
        searchEngine = SearchEngine(settings: settings)
        if let initialRoot {
            root = initialRoot
        } else if let loaded = GraphPersistence.load() {
            root = loaded
        } else {
            root = DiscreteState(name: "root")
            saveGraph(root)
        }
        currentState = root
        searchEngine.onUpdate = { [weak self] in
            self?.refreshSearchResults()
        }
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
        if case .commandFunctions(let editor) = mode { mode = editor }
        switch mode {
        case .editingText(let request):
            request.cancel()
        case .selectingFile(let request):
            request.cancel()
        case .searching:
            searchEngine.end()
        case .selectingBuiltin(let request):
            request.cancel()
        case .searchingBuiltins(let session):
            session.request.cancel()
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
        case .choosingFunctionKind(let setup):
            handleChoosingFunctionKindTap(keyCode, setup: setup)
        case .addingFunction(let kind):
            handleAddingFunctionTap(keyCode, kind: kind)
        case .pickingFunction(let purpose):
            handlePickingFunctionTap(keyCode, purpose: purpose)
        case .pickingNewTrigger(let oldKey, let function):
            handlePickingNewTriggerTap(keyCode, oldKey: oldKey, function: function)
        case .selectingBuiltin(let request):
            handleBuiltinSelectTap(keyCode, request: request)
        case .editingText, .commandFunctions, .selectingFile, .searching, .searchingBuiltins:
            return
        }
        onStateChanged?()
    }

    /// A key typed while in state.text_string, state.search or
    /// state.builtin_select.search (normal key-down typing).
    func handleTyped(_ key: TypedKey) {
        if case .commandFunctions(let editor) = mode {
            switch key.keyCode {
            case KeyCode.escape:
                mode = editor
            case KeyCode.c, KeyCode.v:
                guard !key.flags.contains(.maskControl), !key.flags.contains(.maskAlternate) else { return }
                mode = editor
                performClipboardCommand(key.keyCode)
            default:
                return
            }
            onStateChanged?()
            return
        }
        switch mode {
        case .editingText, .searching, .searchingBuiltins:
            if key.keyCode == KeyCode.leftCommand || key.keyCode == KeyCode.rightCommand {
                mode = .commandFunctions(mode)
                onStateChanged?()
                return
            }
            if key.flags.contains(.maskCommand) {
                if !key.flags.contains(.maskControl), !key.flags.contains(.maskAlternate) {
                    performClipboardCommand(key.keyCode)
                }
                onStateChanged?()
                return
            }
        default:
            return
        }
        applyTextInput(key)
        onStateChanged?()
    }

    private func applyTextInput(_ key: TypedKey) {
        switch mode {
        case .editingText(let request):
            handleTextTyped(key, request: request)
        case .searching(let session):
            handleSearchTyped(key, session: session)
        case .searchingBuiltins(let session):
            handleBuiltinSearchTyped(key, session: session)
        default:
            return
        }
    }

    private func performClipboardCommand(_ keyCode: CGKeyCode) {
        if keyCode == KeyCode.c {
            let text: String
            switch mode {
            case .editingText(let request): text = request.buffer.text
            case .searching(let session): text = session.buffer.text
            case .searchingBuiltins(let session): text = session.buffer.text
            default: return
            }
            writeClipboard(text)
        } else if keyCode == KeyCode.v, let text = readClipboard() {
            // Feed paste through the same single-line filtering and search
            // refresh path as typing. Digits in pasted text aren't selectors.
            applyTextInput(TypedKey(keyCode: 0, flags: [], characters: text))
        }
    }

    private func handleTextTyped(_ key: TypedKey, request: TextEditRequest) {
        var request = request
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
        if keyCode == reserved.search {
            openSearch()
            return
        }
        switch currentState.actions[keyCode] {
        case .transition(let child):
            currentState = child
        case .function(let function):
            run(function)
        case nil:
            return
        }
    }

    /// A file target is run and discrete exits. A builtin does what it
    /// does, then exits unless it stays active; one this version no
    /// longer ships does nothing.
    private func run(_ function: DiscreteFunction) {
        switch function.target {
        case .file(let url):
            onRunFile?(url)
        case .builtin(let id, let argument):
            guard let builtin = BuiltinToolkit.function(id: id) else { return }
            if builtin.behavior == .openSearch {
                openSearch()
            } else {
                onRunBuiltin?(builtin, argument)
            }
            if !builtin.staysActive {
                onExitDiscrete?()
            }
        }
    }

    /// Opens state.search with an empty query. Esc returns to
    /// `currentState` — the root, or the state holding the builtin search
    /// function that opened it.
    private func openSearch() {
        searchEngine.begin(root: root)
        mode = .searching(SearchSession())
    }

    // MARK: - state.search

    /// Digit key n opens the nth suggestion (one key, one event — digits
    /// never type, whatever modifiers are held), Esc goes back to the state
    /// search was opened from; anything else edits the query.
    private func handleSearchTyped(_ key: TypedKey, session: SearchSession) {
        if let rank = KeyCode.digits.firstIndex(of: key.keyCode) {
            openSearchResult(at: rank, in: session)
            return
        }
        switch key.keyCode {
        case KeyCode.escape:
            searchEngine.end()
            mode = .navigating
        case KeyCode.enter, KeyCode.keypadEnter:
            return
        default:
            var session = session
            let before = session.buffer.text
            session.buffer.apply(key)
            if session.buffer.text != before {
                searchEngine.update(query: session.buffer.text)
                session.results = searchEngine.results
            }
            mode = .searching(session)
        }
    }

    /// Spotlight's file results came in after the query was typed.
    private func refreshSearchResults() {
        switch mode {
        case .searching(var session):
            session.results = searchEngine.results
            mode = .searching(session)
        case .commandFunctions(.searching(var session)):
            session.results = searchEngine.results
            mode = .commandFunctions(.searching(session))
        default:
            return
        }
        onStateChanged?()
    }

    private func openSearchResult(at index: Int, in session: SearchSession) {
        guard session.results.indices.contains(index) else { return }
        let item = session.results[index].item
        searchEngine.end()
        mode = .navigating
        switch item {
        case .function(let function):
            // A builtin search function lands back in a fresh search.
            run(function)
        case .state(let state):
            currentState = state
        case .app(let url), .file(let url):
            onOpenFile?(url)
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
            mode = .choosingFunctionKind(.add)
        case Slots.deleteFunction where currentState.hasFunctions:
            mode = .pickingFunction(.delete)
        case Slots.renameFunction where currentState.hasFunctions:
            mode = .pickingFunction(.rename)
        case Slots.setFunctionTrigger where currentState.hasFunctions:
            mode = .pickingFunction(.setTrigger)
        case Slots.updateFunction where currentState.hasFunctions:
            mode = .pickingFunction(.update)
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

    /// Add/update: a resource from the file picker, or a builtin.
    private func handleChoosingFunctionKindTap(_ keyCode: CGKeyCode, setup: FunctionSetup) {
        typealias Slots = KeyList.AddFunctionSlots

        let kind: FunctionKind
        switch keyCode {
        case KeyCode.escape:
            mode = .navigating
            return
        case Slots.resource:
            kind = .resource
        case Slots.builtin:
            kind = .builtin
        default:
            return
        }
        switch setup {
        case .add:
            mode = .addingFunction(kind)
        case .update(let function):
            beginFunctionDetails(kind: kind, existing: function) { [weak self] name, target in
                // Commit only after the entire replacement is selected.
                function.name = name
                function.target = target
                self?.persist()
                self?.mode = .navigating
            }
        }
    }

    /// Key → name → target (→ the builtin's argument, if it takes one).
    /// The function is only added once it has a target, so cancelling at
    /// any step leaves nothing behind.
    private func handleAddingFunctionTap(_ keyCode: CGKeyCode, kind: FunctionKind) {
        if keyCode == KeyCode.escape {
            mode = .navigating
            return
        }
        guard isUnoccupied(keyCode) else { return }

        let parent = currentState
        let add = { [weak self] (name: String, target: FunctionTarget) in
            parent.actions[keyCode] = .function(DiscreteFunction(name: name, target: target))
            self?.persist()
            self?.mode = .navigating
        }
        beginFunctionDetails(kind: kind, save: add)
    }

    /// Name → target → optional argument, shared by add and update. Keeping
    /// drafts in closures leaves an existing function intact on cancellation.
    private func beginFunctionDetails(kind: FunctionKind, existing: DiscreteFunction? = nil,
                                      save: @escaping (String, FunctionTarget) -> Void) {
        let cancel: () -> Void = { [weak self] in self?.mode = .navigating }
        mode = .editingText(TextEditRequest(
            prompt: existing == nil ? "name the new function" : "update function name",
            buffer: TextBuffer(text: existing?.name ?? ""),
            save: { [weak self] name in
                switch kind {
                case .resource:
                    self?.mode = .selectingFile(FileSelectRequest(
                        prompt: "choose a script, app, or file for \"\(name)\"",
                        save: { url in save(name, .file(url)) },
                        cancel: cancel
                    ))
                    self?.onRequestFileSelect?()
                case .builtin:
                    self?.mode = .selectingBuiltin(BuiltinSelectRequest(
                        prompt: "choose a builtin function for \"\(name)\"",
                        save: { builtin in
                            self?.collectBuiltinArguments(builtin, save: { argument in
                                save(name, .builtin(id: builtin.id, argument: argument))
                            }, cancel: cancel)
                        },
                        cancel: cancel
                    ))
                }
            },
            cancel: cancel
        ))
    }

    private func collectBuiltinArguments(_ builtin: BuiltinFunction, values: [String] = [],
                                         save: @escaping (String?) -> Void, cancel: @escaping () -> Void) {
        guard values.count < builtin.argumentPrompts.count else {
            save(builtin.encodeArguments(values))
            return
        }
        mode = .editingText(TextEditRequest(
            prompt: builtin.argumentPrompts[values.count],
            save: { [weak self] value in
                self?.collectBuiltinArguments(builtin, values: values + [value], save: save, cancel: cancel)
            },
            cancel: cancel
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
        case .update:
            mode = .choosingFunctionKind(.update(function))
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

    // MARK: - state.builtin_select

    /// Folders open in place, a builtin function (a leaf) is chosen, Esc
    /// cancels the whole selection.
    private func handleBuiltinSelectTap(_ keyCode: CGKeyCode, request: BuiltinSelectRequest) {
        if keyCode == KeyCode.escape {
            mode = .navigating
            request.cancel()
            return
        }
        let slots = KeyList.builtinFolderSlots(for: request.folder)
        if keyCode == slots.system {
            if let parent = request.folder.parent {
                show(parent, in: request)
            } else {
                mode = .searchingBuiltins(BuiltinSearchSession(request: request))
            }
            return
        }
        switch slots.entries[keyCode] {
        case .folder(let folder):
            show(folder, in: request)
        case .function(let builtin):
            mode = .navigating
            request.save(builtin)
        case nil:
            return
        }
    }

    private func show(_ folder: BuiltinFolder, in request: BuiltinSelectRequest) {
        var request = request
        request.folder = folder
        mode = .selectingBuiltin(request)
    }

    /// state.search's typing and digit keys, over the builtin toolkit only.
    /// Esc goes back to the toolkit's root folder.
    private func handleBuiltinSearchTyped(_ key: TypedKey, session: BuiltinSearchSession) {
        if let rank = KeyCode.digits.firstIndex(of: key.keyCode) {
            guard session.results.indices.contains(rank) else { return }
            switch session.results[rank].entry {
            case .folder(let folder):
                show(folder, in: session.request)
            case .function(let builtin):
                mode = .navigating
                session.request.save(builtin)
            }
            return
        }
        switch key.keyCode {
        case KeyCode.escape:
            show(BuiltinToolkit.root, in: session.request)
        case KeyCode.enter, KeyCode.keypadEnter:
            return
        default:
            var session = session
            session.buffer.apply(key)
            session.results = BuiltinSearch.results(for: session.buffer.text, limit: settings.maxSearchResults)
            mode = .searchingBuiltins(session)
        }
    }

    // MARK: - Helpers

    /// Free for a new user binding in the current state. The keys shown
    /// for configure/back count as free — binding one just moves them.
    private func isUnoccupied(_ keyCode: CGKeyCode) -> Bool {
        KeyList.isBindable(keyCode) && currentState.actions[keyCode] == nil
    }

    private func persist() {
        saveGraph(root)
    }
}
