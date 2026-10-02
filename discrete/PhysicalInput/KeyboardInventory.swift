import Carbon.HIToolbox
import CoreGraphics
import IOKit.hid

/// Which keys physically exist on the connected keyboards. HID descriptors
/// can't answer this — the built-in MacBook keyboard's descriptor declares
/// right Control, which it doesn't have — so each connected keyboard is
/// matched to a known profile instead, and the result is the union of
/// their keys.
nonisolated enum KeyboardInventory {
    private enum Profile: String {
        /// Built-in laptop keyboards and Magic Keyboards without a keypad.
        case appleCompact
        /// Magic Keyboard with Numeric Keypad.
        case appleNumeric
        /// Anything else: a full standard (PC-style) keyboard.
        case standard
    }

    private static let appleVendorIDs: Set<Int> = [0x05AC, 0x004C]

    /// Devices that report themselves as keyboards but aren't one.
    private static let ignoredProductWords = ["yubikey", "security key", "mouse"]

    static func availableKeys() -> Set<CGKeyCode> {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []

        let profiles = devices.compactMap(profile(of:))
        // Nothing recognizable connected: assume a full keyboard rather
        // than leave keys out.
        let keys = (profiles.isEmpty ? [.standard] : profiles).reduce(into: Set<CGKeyCode>()) {
            $0.formUnion(keys(for: $1))
        }
        print("⌨️ Keyboards: \(profiles.map(\.rawValue)) → \(keys.count) keys available")
        return keys
    }

    private static func profile(of device: IOHIDDevice) -> Profile? {
        func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }

        let name = (property(kIOHIDProductKey) as? String ?? "").lowercased()
        if ignoredProductWords.contains(where: name.contains) { return nil }

        let isBuiltIn = (property("Built-In") as? Bool) ?? false
        let vendor = property(kIOHIDVendorIDKey) as? Int
        let isApple = isBuiltIn || vendor.map(appleVendorIDs.contains) ?? false || name.hasPrefix("apple") || name.hasPrefix("magic keyboard")
        guard isApple else { return .standard }
        return name.contains("numeric keypad") ? .appleNumeric : .appleCompact
    }

    // MARK: - Key sets

    /// Keys every keyboard has: letters, digits, punctuation, tab, space,
    /// return, delete, esc, CapsLock, arrows, F1–F12, and every modifier
    /// except right Control.
    private static let core: Set<CGKeyCode> = {
        var keys = Set(KeyCode.letters)
        keys.formUnion([18, 19, 20, 21, 23, 22, 26, 28, 25, 29])                 // 1–0
        keys.formUnion([24, 27, 33, 30, 39, 41, 42, 43, 44, 47, KeyCode.backtick]) // = - [ ] ' ; \ , / . `
        keys.formUnion([KeyCode.tab, 49, KeyCode.enter, KeyCode.delete, KeyCode.escape, KeyCode.capsLock])
        keys.formUnion([KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.downArrow, KeyCode.upArrow])
        keys.formUnion(KeyCode.fKeys.prefix(12))
        keys.formUnion(KeyCode.modifiers.filter { $0 != KeyCode.rightControl })
        return keys
    }()

    private static let navigationCluster: Set<CGKeyCode> = [114, 115, 116, 117, 119, 121] // help/insert, home, pgup, fwd delete, end, pgdn

    /// Keys that exist only on some physical layouts: ISO's extra key next
    /// to left shift, JIS's extra keys.
    private static var layoutExtras: Set<CGKeyCode> {
        switch KBGetLayoutType(Int16(LMGetKbdType())) {
        case OSType(kKeyboardISO): return [10]
        case OSType(kKeyboardJIS): return [93, 94, 95, 102, 104]
        default: return []
        }
    }

    private static func keys(for profile: Profile) -> Set<CGKeyCode> {
        switch profile {
        case .appleCompact:
            return core.union([KeyCode.function]).union(layoutExtras)
        case .appleNumeric:
            return core.union([KeyCode.function])
                .union(KeyCode.fKeys[12..<19])      // F13–F19
                .union(navigationCluster)
                .union(KeyCode.keypad)
                .union(layoutExtras)
        case .standard:
            return core.union([KeyCode.rightControl])
                .union(navigationCluster)
                .union(KeyCode.keypad)
                .union(layoutExtras)
        }
    }
}
