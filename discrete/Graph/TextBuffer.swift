import CoreGraphics

/// state.text_string's internal text: a string plus a cursor, edited like
/// a normal text field — characters insert at the cursor, delete removes
/// the one before it, left/right move it.
struct TextBuffer {
    private(set) var characters: [Character] = []
    private(set) var cursor = 0

    init(text: String = "") {
        characters = Array(text)
        cursor = characters.count
    }

    var text: String { String(characters) }

    /// The text with a caret drawn at the cursor, for the overlay.
    var displayText: String {
        String(characters[..<cursor]) + "▏" + String(characters[cursor...])
    }

    /// Applies one typed key. Keys that aren't text editing (tab, F-keys,
    /// up/down, ...) are ignored. Enter/Esc are handled by the caller.
    mutating func apply(_ key: TypedKey) {
        switch key.keyCode {
        case KeyCode.delete:
            guard cursor > 0 else { return }
            characters.remove(at: cursor - 1)
            cursor -= 1
        case KeyCode.leftArrow:
            cursor = max(0, cursor - 1)
        case KeyCode.rightArrow:
            cursor = min(characters.count, cursor + 1)
        default:
            // ⌘/⌃ combos are shortcuts, not text.
            guard !key.flags.contains(.maskCommand), !key.flags.contains(.maskControl) else { return }
            let printable = key.characters.unicodeScalars.filter(Self.isPrintable)
            for character in String(String.UnicodeScalarView(printable)) {
                characters.insert(character, at: cursor)
                cursor += 1
            }
        }
    }

    /// Excludes control characters and the private-use range AppKit uses
    /// for function/arrow keys.
    nonisolated static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .privateUse, .format, .surrogate, .unassigned:
            return false
        default:
            return true
        }
    }
}
