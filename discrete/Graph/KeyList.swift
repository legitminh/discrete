import CoreGraphics

struct KeyDescriptor {
    let keyCode: CGKeyCode
    let symbol: String
}

/// The hardcoded "list of possible keys" the spec calls for. A-Z only for
/// now (workplan Open Question #4) — reserved system actions are handed
/// out from the end of this list, per state, skipping whatever keys that
/// state already uses for a user-defined transition.
enum KeyList {
    static let letters: [KeyDescriptor] = [
        .init(keyCode: 0, symbol: "A"), .init(keyCode: 11, symbol: "B"),
        .init(keyCode: 8, symbol: "C"), .init(keyCode: 2, symbol: "D"),
        .init(keyCode: 14, symbol: "E"), .init(keyCode: 3, symbol: "F"),
        .init(keyCode: 5, symbol: "G"), .init(keyCode: 4, symbol: "H"),
        .init(keyCode: 34, symbol: "I"), .init(keyCode: 38, symbol: "J"),
        .init(keyCode: 40, symbol: "K"), .init(keyCode: 37, symbol: "L"),
        .init(keyCode: 46, symbol: "M"), .init(keyCode: 45, symbol: "N"),
        .init(keyCode: 31, symbol: "O"), .init(keyCode: 35, symbol: "P"),
        .init(keyCode: 12, symbol: "Q"), .init(keyCode: 15, symbol: "R"),
        .init(keyCode: 1, symbol: "S"), .init(keyCode: 17, symbol: "T"),
        .init(keyCode: 32, symbol: "U"), .init(keyCode: 9, symbol: "V"),
        .init(keyCode: 13, symbol: "W"), .init(keyCode: 7, symbol: "X"),
        .init(keyCode: 16, symbol: "Y"), .init(keyCode: 6, symbol: "Z")
    ]

    /// Not part of `letters` — home's own hardcoded default mapping, per spec.
    static let delete = KeyDescriptor(keyCode: 51, symbol: "⌫")
    static let capsLockSymbol = "⇪"

    /// `bindNewAction` (the "set node arguments" mini-mode) will accept any
    /// key the user presses as a transition trigger, not just `letters` —
    /// so display needs symbols for everything reasonably reachable from a
    /// standard ANSI keyboard, not just A-Z. Kept separate from `letters`
    /// since only `letters` participates in reserved-slot allocation.
    private static let otherSymbols: [CGKeyCode: String] = [
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
        23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        24: "=", 27: "-", 33: "[", 30: "]", 39: "'",
        41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        36: "⏎", 48: "⇥", 49: "␣", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    static func symbol(for keyCode: CGKeyCode) -> String {
        if keyCode == delete.keyCode { return delete.symbol }
        if let letter = letters.first(where: { $0.keyCode == keyCode }) { return letter.symbol }
        if let other = otherSymbols[keyCode] { return other }
        // Still unknown (an ISO/JIS extra key, a media key, etc.) — show
        // the raw code rather than a bare "?" so different unmapped keys
        // are at least distinguishable from one another in the overlay.
        return "?\(keyCode)"
    }

    struct ReservedSlots {
        let name: KeyDescriptor?
        let arguments: KeyDescriptor?
        let back: KeyDescriptor?
        let pickScript: KeyDescriptor?
    }

    /// `name`/`arguments`/`back` are the last/2nd-last/3rd-last unoccupied
    /// keys, per the spec. `pickScript` — the leaf-only "open file system
    /// to pick a script" action — is deliberately given the *4th*-last
    /// slot instead of reusing `back`'s slot as a literal reading of the
    /// spec would have it: that reading leaves a leaf state with no way
    /// back except exiting discrete entirely. This plan keeps `back`
    /// always available and adds `pickScript` as an extra slot for leaves.
    /// See workplan Open Question #3.
    static func reservedSlots(for state: DiscreteState) -> ReservedSlots {
        let used = Set(state.children.keys)
        let unoccupied = letters.filter { !used.contains($0.keyCode) }

        func slot(fromEnd n: Int) -> KeyDescriptor? {
            let index = unoccupied.count - n
            guard index >= 0 else { return nil }
            return unoccupied[index]
        }

        return ReservedSlots(
            name: slot(fromEnd: 1),
            arguments: slot(fromEnd: 2),
            back: slot(fromEnd: 3),
            pickScript: state.isLeaf ? slot(fromEnd: 4) : nil
        )
    }
}
