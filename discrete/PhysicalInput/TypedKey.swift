import CoreGraphics

/// A key pressed while typing in state.text_string — the raw key code,
/// the modifier flags, and whatever character(s) it types (empty for
/// non-printing keys).
struct TypedKey {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let characters: String
}
