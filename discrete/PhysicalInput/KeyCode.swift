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

    /// The digit row 1–9, by physical position — state.search's quick keys.
    static let digits: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    static let modifiers: [CGKeyCode] = [
        leftCommand, rightCommand, leftOption, rightOption,
        leftControl, rightControl, leftShift, rightShift
    ]

    static let keypad: Set<CGKeyCode> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
}
