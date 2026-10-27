import AppKit
import ApplicationServices

/// Follow the final summoned window, after activation has settled. Correlating
/// browser windows must not move the pointer through intermediate candidates.
enum SummonedWindowPointer {
    private static var generation = 0

    struct Request {
        fileprivate let generation: Int

        func follow(_ app: NSRunningApplication, windowID: CGWindowID? = nil,
                    completion: @escaping () -> Void = {}) {
            SummonedWindowPointer.follow(app, windowID: windowID, request: generation, completion: completion)
        }
    }

    static func begin() -> Request {
        generation += 1
        return Request(generation: generation)
    }

    private static func follow(_ app: NSRunningApplication, windowID: CGWindowID?, request: Int,
                               attempts: Int = 20, completion: @escaping () -> Void) {
        guard request == generation, !app.isTerminated,
              NSScreen.screens.count > 1, AXIsProcessTrusted() else { completion(); return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
           let focusedID = focusedWindowID(app), windowID == nil || windowID == focusedID,
           let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
           let record = records.first(where: {
               ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == focusedID
                   && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier
           }), let bounds = record[kCGWindowBounds as String] as? [String: Any],
           let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
           let pointer = CGEvent(source: nil)?.location {
            let displays = NSScreen.screens.compactMap { screen -> CGRect? in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
                return CGDisplayBounds(id.uint32Value)
            }
            if let destination = PointerMonitorPolicy.destination(pointer: pointer, window: frame, displays: displays) {
                CGWarpMouseCursorPosition(destination)
            }
            completion()
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                follow(app, windowID: windowID, request: request, attempts: attempts - 1, completion: completion)
            }
        } else {
            completion()
        }
    }

    private static func focusedWindowID(_ app: NSRunningApplication) -> CGWindowID? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return ApplicationSpaces.windowID(of: value as! AXUIElement)
    }
}
