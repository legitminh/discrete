import AppKit
import ApplicationServices

/// Toggles native macOS fullscreen for the frontmost app's focused window.
/// The discrete overlay is nonactivating, so it leaves that focus intact.
enum WindowFullscreen {
    @discardableResult
    static func toggleFocusedWindow() -> Bool {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return false }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let window = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.3)

        // AXFullScreen is supported by native fullscreen windows but isn't
        // included among the SDK's Accessibility attribute constants.
        let attribute = "AXFullScreen" as CFString
        var value: CFTypeRef?
        var isSettable = DarwinBoolean(false)
        guard AXUIElementCopyAttributeValue(window, attribute, &value) == .success,
              let isFullscreen = value as? Bool,
              AXUIElementIsAttributeSettable(window, attribute, &isSettable) == .success,
              isSettable.boolValue else { return false }
        let result = AXUIElementSetAttributeValue(window, attribute, (isFullscreen ? kCFBooleanFalse : kCFBooleanTrue)!)
        if result != .success { print("🪟 Couldn't toggle focused window fullscreen: \(result.rawValue)") }
        return result == .success
    }
}
