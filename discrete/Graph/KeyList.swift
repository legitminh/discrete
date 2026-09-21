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
    /// since only `letters` participates in reserved-slot allocation, but
    /// it's still part of `orderedKeyCodes` below, for display ordering.
    private static let otherKeys: [KeyDescriptor] = [
        .init(keyCode: 29, symbol: "0"), .init(keyCode: 18, symbol: "1"),
        .init(keyCode: 19, symbol: "2"), .init(keyCode: 20, symbol: "3"),
        .init(keyCode: 21, symbol: "4"), .init(keyCode: 23, symbol: "5"),
        .init(keyCode: 22, symbol: "6"), .init(keyCode: 26, symbol: "7"),
        .init(keyCode: 28, symbol: "8"), .init(keyCode: 25, symbol: "9"),
        .init(keyCode: 24, symbol: "="), .init(keyCode: 27, symbol: "-"),
        .init(keyCode: 33, symbol: "["), .init(keyCode: 30, symbol: "]"),
        .init(keyCode: 39, symbol: "'"), .init(keyCode: 41, symbol: ";"),
        .init(keyCode: 42, symbol: "\\"), .init(keyCode: 43, symbol: ","),
        .init(keyCode: 44, symbol: "/"), .init(keyCode: 47, symbol: "."),
        .init(keyCode: 50, symbol: "`"),
        .init(keyCode: 36, symbol: "⏎"), .init(keyCode: 48, symbol: "⇥"),
        .init(keyCode: 49, symbol: "␣"), .init(keyCode: 53, symbol: "⎋"),
        .init(keyCode: 117, symbol: "⌦"),
        .init(keyCode: 123, symbol: "←"), .init(keyCode: 124, symbol: "→"),
        .init(keyCode: 125, symbol: "↓"), .init(keyCode: 126, symbol: "↑"),
        .init(keyCode: 115, symbol: "↖"), .init(keyCode: 119, symbol: "↘"),
        .init(keyCode: 116, symbol: "⇞"), .init(keyCode: 121, symbol: "⇟"),
        .init(keyCode: 122, symbol: "F1"), .init(keyCode: 120, symbol: "F2"),
        .init(keyCode: 99, symbol: "F3"), .init(keyCode: 118, symbol: "F4"),
        .init(keyCode: 96, symbol: "F5"), .init(keyCode: 97, symbol: "F6"),
        .init(keyCode: 98, symbol: "F7"), .init(keyCode: 100, symbol: "F8"),
        .init(keyCode: 101, symbol: "F9"), .init(keyCode: 109, symbol: "F10"),
        .init(keyCode: 103, symbol: "F11"), .init(keyCode: 111, symbol: "F12")
    ]

    /// The full ordered "list of possible keys on the device" the spec
    /// calls for: Delete first (it's always the leading row per the
    /// spec's own "[delete] settings is the first row" example), then
    /// `letters` in their defined order, then everything else. This is
    /// what display ordering is based on — `letters` alone still governs
    /// reserved-slot allocation, unchanged.
    static let orderedKeyCodes: [CGKeyCode] =
        [delete.keyCode] + letters.map(\.keyCode) + otherKeys.map(\.keyCode)

    private static let displayOrderByKeyCode: [CGKeyCode: Int] = Dictionary(
        uniqueKeysWithValues: orderedKeyCodes.enumerated().map { ($0.element, $0.offset) }
    )

    /// Where `keyCode` sits in the canonical key list, for display
    /// ordering. A key outside the known list sorts after everything
    /// known (by its own raw code, so ordering stays deterministic).
    static func displayOrder(of keyCode: CGKeyCode) -> Int {
        displayOrderByKeyCode[keyCode] ?? (Int(keyCode) + orderedKeyCodes.count)
    }

    static func symbol(for keyCode: CGKeyCode) -> String {
        if keyCode == delete.keyCode { return delete.symbol }
        if let letter = letters.first(where: { $0.keyCode == keyCode }) { return letter.symbol }
        if let other = otherKeys.first(where: { $0.keyCode == keyCode }) { return other.symbol }
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
