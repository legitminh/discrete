import CoreGraphics

/// A key pressed while discrete mode owns the keyboard — the raw key code
/// plus whatever character it types (empty for non-printing keys), used to
/// build a name in `.namingState` mode.
struct CapturedKeyDown {
    let keyCode: CGKeyCode
    let characters: String
}
