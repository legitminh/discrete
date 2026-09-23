import Carbon.HIToolbox
import CoreGraphics

/// Virtual key codes. These identify *physical* keys (kVK_ANSI_A is the
/// key in the QWERTY "A" position whatever the layout), and left/right
/// modifiers have distinct codes — exactly the key identity the spec asks for.
nonisolated enum KeyCode {
    static let leftCommand: CGKeyCode = 55
    static let rightCommand: CGKeyCode = 54
    static let leftOption: CGKeyCode = 58
    static let rightOption: CGKeyCode = 61
    static let leftControl: CGKeyCode = 59
    static let rightControl: CGKeyCode = 62
    static let leftShift: CGKeyCode = 56
    static let rightShift: CGKeyCode = 60
    static let function: CGKeyCode = 63
    static let capsLock: CGKeyCode = 57

    static let tab: CGKeyCode = 48
    static let escape: CGKeyCode = 53
    static let backtick: CGKeyCode = 50
    static let delete: CGKeyCode = 51
    static let enter: CGKeyCode = 36
    static let keypadEnter: CGKeyCode = 76
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let downArrow: CGKeyCode = 125
    static let upArrow: CGKeyCode = 126

    static let fKeys: [CGKeyCode] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
        105, 107, 113, 106, 64, 79, 80, 90                         // F13–F20
    ]

    /// a–z, in alphabetical order of the QWERTY letter at that position.
    static let letters: [CGKeyCode] = [
        0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
        45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6
    ]

    static let modifiers: [CGKeyCode] = [
        leftCommand, rightCommand, leftOption, rightOption,
        leftControl, rightControl, leftShift, rightShift
    ]

    static let keypad: Set<CGKeyCode> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
}

/// The spec's ordered key list. Its order is both the display order of a
/// state's actions and the order system keys (configure, back, the
/// configure menu) are handed out in. Hard-coded; it doesn't depend on the
/// connected keyboard, so a system key can land on a key a given keyboard
/// lacks (e.g. R⌃ on a MacBook) — accepted by the spec for now.
enum KeyList {
    /// Everything the spec names explicitly, in spec order. Any other key
    /// comes after these, by key code; CapsLock is never in the list.
    static let namedKeys: [CGKeyCode] =
        KeyCode.modifiers
        + [KeyCode.tab, KeyCode.escape, KeyCode.backtick]
        + KeyCode.fKeys
        + [KeyCode.delete, KeyCode.enter]
        + [KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.downArrow, KeyCode.upArrow]
        + KeyCode.letters

    private static let namedOrder: [CGKeyCode: Int] = Dictionary(
        uniqueKeysWithValues: namedKeys.enumerated().map { ($0.element, $0.offset) }
    )

    /// Keys system actions may be assigned to, in key-list order: every key
    /// except CapsLock (reserved) and Esc (always "exit" in configuration).
    static let assignableKeys: [CGKeyCode] = {
        let named = namedKeys.filter(isBindable)
        let others = (CGKeyCode(0)...CGKeyCode(127)).filter { namedOrder[$0] == nil && isBindable($0) }
        return named + others
    }()

    /// Neither CapsLock nor Esc can ever be a trigger: CapsLock leaves
    /// discrete, and every screen that picks a trigger uses Esc to exit.
    nonisolated static func isBindable(_ keyCode: CGKeyCode) -> Bool {
        keyCode != KeyCode.capsLock && keyCode != KeyCode.escape
    }

    /// Where `keyCode` sits in the key list, for display ordering.
    static func displayOrder(of keyCode: CGKeyCode) -> Int {
        namedOrder[keyCode] ?? (namedKeys.count + Int(keyCode))
    }

    // MARK: - Symbols

    static let capsLockSymbol = "⇪"

    private static let fixedSymbols: [CGKeyCode: String] = {
        var symbols: [CGKeyCode: String] = [
            KeyCode.leftCommand: "⌘", KeyCode.rightCommand: "R⌘",
            KeyCode.leftOption: "⌥", KeyCode.rightOption: "R⌥",
            KeyCode.leftControl: "⌃", KeyCode.rightControl: "R⌃",
            KeyCode.leftShift: "⇧", KeyCode.rightShift: "R⇧",
            KeyCode.function: "fn", KeyCode.capsLock: "⇪",
            KeyCode.tab: "⇥", KeyCode.escape: "⎋", KeyCode.backtick: "`",
            KeyCode.delete: "⌫", KeyCode.enter: "⏎", KeyCode.keypadEnter: "⌤",
            KeyCode.leftArrow: "←", KeyCode.rightArrow: "→",
            KeyCode.downArrow: "↓", KeyCode.upArrow: "↑",
            49: "␣", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 71: "⌧"
        ]
        for (index, keyCode) in KeyCode.fKeys.enumerated() {
            symbols[keyCode] = "F\(index + 1)"
        }
        return symbols
    }()

    /// A distinct symbol per key. Special keys have fixed symbols; letters
    /// and other character keys show what they type in the current layout.
    static func symbol(for keyCode: CGKeyCode) -> String {
        if let fixed = fixedSymbols[keyCode] { return fixed }
        let character = KeyboardLayout.character(for: keyCode) ?? "?\(keyCode)"
        return KeyCode.keypad.contains(keyCode) ? "kp\(character)" : character
    }

    // MARK: - System key assignment

    struct ReservedSlots {
        let configure: CGKeyCode?
        let back: CGKeyCode?
    }

    /// configure = 1st unoccupied key; back = 2nd, and only if there is a
    /// previous state. "Unoccupied" = not bound to one of `state`'s actions.
    static func reservedSlots(for state: DiscreteState) -> ReservedSlots {
        var free = assignableKeys.lazy.filter { state.actions[$0] == nil }.makeIterator()
        let configure = free.next()
        let back = state.parent != nil ? free.next() : nil
        return ReservedSlots(configure: configure, back: back)
    }

    /// The configure menu's keys: 1st, 2nd, ... assignable key, in the
    /// spec's document order. state.?.conf is its own state with no user
    /// bindings, so these never depend on the configured state. Items that
    /// don't apply (`deleteState` at root, the function items when the
    /// state has no functions) keep their slots, hidden and inert, so no
    /// key ever shifts.
    enum ConfigureSlots {
        static let nameState = assignableKeys[0]
        static let deleteState = assignableKeys[1]
        static let newState = assignableKeys[2]
        static let addFunction = assignableKeys[3]
        static let deleteFunction = assignableKeys[4]
        static let renameFunction = assignableKeys[5]
        static let setFunctionTrigger = assignableKeys[6]
    }
}
