import CoreGraphics
import Foundation

/// Which screen discrete is on for the current state. `.navigating` is
/// state.? itself; the others are state.?.conf and its sub-states, plus
/// the reusable state.text_string / state.file_select editors.
enum DiscreteMode {
    case navigating

    /// state.?.conf — the configure menu.
    case configuring

    /// state.?.conf.del_state — waiting for the delete key a second time.
    case confirmingDelete

    /// state.?.conf.add_state — waiting for the new state's trigger key.
    case addingState

    /// state.?.conf.add_func — waiting for the new function's trigger key.
    case addingFunction

    /// del_func / name_func / set_input_func — waiting for a function's own trigger key.
    case pickingFunction(FunctionPickerPurpose)

    /// set_input_func.set_input — waiting for `function`'s new trigger key.
    case pickingNewTrigger(oldKey: CGKeyCode, function: DiscreteFunction)

    /// state.text_string.
    case editingText(TextEditRequest)

    /// state.file_select — the system file picker is open.
    case selectingFile(FileSelectRequest)
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

/// state.file_select[save, exit, cancel].
struct FileSelectRequest {
    let prompt: String
    let save: (URL) -> Void
    let cancel: () -> Void
}
