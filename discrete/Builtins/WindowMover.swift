import AppKit
import ApplicationServices

/// The "move window to next monitor" builtin. Moves the frontmost app's
/// focused window to the next monitor, ordered left to right (then top
/// to bottom) and wrapping around, keeping its size (shrunk if it doesn't
/// fit) and its relative place on the screen. Uses the Accessibility API,
/// which discrete already has permission for.
enum WindowMover {
    static func moveFocusedWindowToNextMonitor() {
        let screens = NSScreen.screens.sorted {
            ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY)
        }
        guard screens.count > 1,
              let app = NSWorkspace.shared.frontmostApplication,
              let window = focusedWindow(of: app),
              let frame = frame(of: window),
              let current = screens.max(by: { overlap($0, frame) < overlap($1, frame) }),
              let index = screens.firstIndex(of: current) else {
            print("🪟 No focused window to move, or only one monitor")
            return
        }
        let next = screens[(index + 1) % screens.count]
        let moved = place(frame, from: current.visibleFrame, to: next.visibleFrame)
        print("🪟 Moving \(app.localizedName ?? "window") to \(next.localizedName)")

        // Size, then position, then size again: some apps refuse a size
        // that doesn't fit the screen the window is still on.
        setSize(moved.size, of: window)
        setPosition(moved.origin, of: window)
        setSize(moved.size, of: window)
    }

    /// Keeps the window's size (capped to the target) and its relative
    /// place: a window flush right stays flush right, a centred one stays centred.
    private static func place(_ frame: CGRect, from: CGRect, to: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, to.width), height: min(frame.height, to.height))
        func offset(_ position: CGFloat, _ length: CGFloat, _ fromStart: CGFloat, _ fromLength: CGFloat, _ toLength: CGFloat, _ newLength: CGFloat) -> CGFloat {
            let room = fromLength - length
            let fraction = room > 0 ? min(max((position - fromStart) / room, 0), 1) : 0
            return fraction * (toLength - newLength)
        }
        return CGRect(
            x: to.minX + offset(frame.minX, frame.width, from.minX, from.width, to.width, size.width),
            y: to.minY + offset(frame.minY, frame.height, from.minY, from.height, to.height, size.height),
            width: size.width,
            height: size.height
        )
    }

    private static func overlap(_ screen: NSScreen, _ frame: CGRect) -> CGFloat {
        let intersection = screen.frame.intersection(frame)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    // MARK: - Accessibility

    private static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// The window's frame in AppKit coordinates (origin bottom-left of the
    /// primary screen, y up). Accessibility uses top-left, y down.
    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = position(of: window), let size = size(of: window) else { return nil }
        return CGRect(x: position.x, y: primaryScreenTop - position.y - size.height, width: size.width, height: size.height)
    }

    private static func setPosition(_ origin: CGPoint, of window: AXUIElement) {
        // `origin` is the bottom-left corner in AppKit coordinates; convert
        // back to the top-left corner Accessibility expects.
        let size = size(of: window) ?? .zero
        var point = CGPoint(x: origin.x, y: primaryScreenTop - origin.y - size.height)
        if let axValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
        }
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        if let axValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
        }
    }

    private static func position(of window: AXUIElement) -> CGPoint? {
        guard let value = axValue(of: window, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(of window: AXUIElement) -> CGSize? {
        guard let value = axValue(of: window, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func axValue(of window: AXUIElement, _ attribute: String) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        return (raw as! AXValue)
    }

    private static var primaryScreenTop: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }
}
