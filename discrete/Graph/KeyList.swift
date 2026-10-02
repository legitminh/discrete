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
/// configure menu) are handed out in. Only keys that exist on the
/// connected keyboards are part of it (`available`, refreshed each time
/// discrete is entered), so a system key never lands on a missing key.
enum KeyList {
    /// The keys on the connected keyboards (see `KeyboardInventory`).
    private(set) static var available: Set<CGKeyCode> = KeyboardInventory.availableKeys()

    /// Re-detects the connected keyboards; the key list, configure/back and
    /// the configure menu keys all follow.
    static func refreshAvailableKeys() {
        available = KeyboardInventory.availableKeys()
    }

    static func isAvailable(_ keyCode: CGKeyCode) -> Bool {
        available.contains(keyCode)
    }

    /// Every key the spec names explicitly, in spec order, available or
    /// not. Any other key comes after these, by key code.
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

    /// The key list itself minus CapsLock and Esc, in order: the keys user
    /// actions can be bound to and system actions are assigned from.
    static var assignableKeys: [CGKeyCode] {
        let named = namedKeys.filter { isBindable($0) }
        let others = available.filter { namedOrder[$0] == nil && isBindable($0) }.sorted()
        return named + others
    }

    /// Available, and neither CapsLock nor Esc: CapsLock leaves discrete,
    /// and every screen that picks a trigger uses Esc to exit.
    static func isBindable(_ keyCode: CGKeyCode) -> Bool {
        keyCode != KeyCode.capsLock && keyCode != KeyCode.escape && isAvailable(keyCode)
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
    /// bindings, so these never depend on the configured state (only on
    /// which keyboards are connected). Items that don't apply
    /// (`deleteState` at root, the function items when the state has no
    /// functions) keep their slots, hidden and inert, so no key shifts.
    enum ConfigureSlots {
        static var nameState: CGKeyCode { assignableKeys[0] }
        static var deleteState: CGKeyCode { assignableKeys[1] }
        static var newState: CGKeyCode { assignableKeys[2] }
        static var addFunction: CGKeyCode { assignableKeys[3] }
        static var deleteFunction: CGKeyCode { assignableKeys[4] }
        static var renameFunction: CGKeyCode { assignableKeys[5] }
        static var setFunctionTrigger: CGKeyCode { assignableKeys[6] }
    }

    /// The key that selects each function in the function pickers
    /// (delete / rename / set trigger), keyed by selection key → the
    /// function's own trigger. Normally a function is picked with its own
    /// trigger; one whose trigger isn't available right now (its keyboard
    /// is disconnected) is given a stand-in: the first assignable key not
    /// used by the state or by another selection.
    static func functionSelectionKeys(for state: DiscreteState) -> [CGKeyCode: CGKeyCode] {
        let triggers = state.actions.compactMap { key, action -> CGKeyCode? in
            if case .function = action { return key }
            return nil
        }
        var selection: [CGKeyCode: CGKeyCode] = [:]
        for trigger in triggers where isAvailable(trigger) {
            selection[trigger] = trigger
        }
        var standIns = assignableKeys.filter { state.actions[$0] == nil }.makeIterator()
        for trigger in triggers.sorted(by: { displayOrder(of: $0) < displayOrder(of: $1) }) where !isAvailable(trigger) {
            guard let standIn = standIns.next() else { break }
            selection[standIn] = trigger
        }
        return selection
    }
}
