import CoreGraphics
import Foundation

/// Which screen discrete is on for the current state. `.navigating` is
/// state.? itself; the others are state.?.conf and its sub-states, plus
/// the reusable state.text_string / state.file_select / state.builtin_select editors.
enum DiscreteMode {
    case navigating

    /// state.?.conf — the configure menu.
    case configuring

    /// state.?.conf.del_state — waiting for the delete key a second time.
    case confirmingDelete

    /// state.?.conf.add_state — waiting for the new state's trigger key.
    case addingState

    /// state.?.conf.add_func — choosing what kind of function to add.
    case choosingFunctionKind

    /// state.?.conf.add_func.trigger — waiting for the new function's trigger key.
    case addingFunction(FunctionKind)

    /// del_func / name_func / set_input_func — waiting for a function's own trigger key.
    case pickingFunction(FunctionPickerPurpose)

    /// set_input_func.set_input — waiting for `function`'s new trigger key.
    case pickingNewTrigger(oldKey: CGKeyCode, function: DiscreteFunction)

    /// state.text_string.
    case editingText(TextEditRequest)

    /// state.file_select — the system file picker is open.
    case selectingFile(FileSelectRequest)

    /// state.search — typing a query over everything discrete can open.
    case searching(SearchSession)

    /// state.builtin_select — browsing the builtin toolkit.
    case selectingBuiltin(BuiltinSelectRequest)

    /// state.builtin_select.search — typing a query over the builtin toolkit.
    case searchingBuiltins(BuiltinSearchSession)
}

/// What a new function's target is chosen from.
enum FunctionKind {
    /// A script, app, or file, from the system file picker.
    case resource
    /// A function from the builtin toolkit.
    case builtin
}

enum FunctionPickerPurpose {
    case delete
    case rename
    case setTrigger
}

/// state.text_string[save, exit, cancel]. `save` stores the text and then
/// transitions to "exit"; `cancel` transitions without saving anything.
struct TextEditRequest {
    let prompt: String
    var buffer = TextBuffer()
    let save: (String) -> Void
    let cancel: () -> Void
}

/// state.search: the query being typed and its current suggestions, best
/// first (digit key 1 opens `results[0]`).
struct SearchSession {
    var buffer = TextBuffer()
    var results: [SearchResult] = []
}

/// state.file_select[save, exit, cancel].
struct FileSelectRequest {
    let prompt: String
    let save: (URL) -> Void
    let cancel: () -> Void
}

/// state.builtin_select[save, exit, cancel], showing `folder`.
struct BuiltinSelectRequest {
    let prompt: String
    var folder = BuiltinToolkit.root
    let save: (BuiltinFunction) -> Void
    let cancel: () -> Void
}

/// state.builtin_select.search: the query being typed and its current
/// suggestions, best first. `request` is the builtin_select it belongs to.
struct BuiltinSearchSession {
    let request: BuiltinSelectRequest
    var buffer = TextBuffer()
    var results: [BuiltinSearchResult] = []
}
