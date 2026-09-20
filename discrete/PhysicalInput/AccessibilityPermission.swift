import ApplicationServices

/// Monitoring physical key events system-wide requires Accessibility
/// (Input Monitoring) permission — this asks for it once, up front.
enum AccessibilityPermission {
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        print(trusted ? "✅ Accessibility permission granted" : "❌ Accessibility permission NOT granted — grant it in System Settings > Privacy & Security > Accessibility, then relaunch")
        return trusted
    }
}
