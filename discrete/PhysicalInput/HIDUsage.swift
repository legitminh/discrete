import IOKit.hid

/// Identifies a key by its raw USB HID usage — the (page, usage) pair
/// `IOHIDManager` matches elements on, as opposed to a `CGEventTap` virtual
/// key code.
enum HIDUsage {
    static let keyboardOrKeypadPage = Int(kHIDPage_KeyboardOrKeypad)
    static let capsLock = Int(kHIDUsage_KeyboardCapsLock)
}
