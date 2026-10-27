import AppKit
import ApplicationServices

/// A native AX raise can jump straight to a window's Space. Verify the actual
/// window is displayed before reporting success; accepting focus alone isn't
/// evidence that the desktop changed.
enum DirectWindowActivation {
    static func raise(window: AXUIElement?, id: CGWindowID, app: NSRunningApplication,
                      target: UInt64, displayID: String, resolveWindow: () -> AXUIElement?,
                      isCurrent: @escaping () -> Bool,
                      completion: @escaping (NativeSpaceSwitcher.ActivationResult) -> Void) {
        guard isCurrent() else { completion(.interrupted); return }
        guard let origin = ApplicationSpaces.displays()?.first(where: { $0.id == displayID })?.currentSpace,
              ApplicationSpaces.spaces(for: id)?.contains(target) == true else { completion(.interrupted); return }
        app.unhide()
        // Making the exact target key can also publish its AXFocusedWindow
        // reference when Chrome omits it from the inactive-Space window list.
        guard ApplicationSpaces.focus(windowID: id, pid: app.processIdentifier) else {
            completion(.unavailable); return
        }
        func valid(_ element: AXUIElement) -> Bool {
            var role: CFTypeRef?
            return ApplicationSpaces.windowID(of: element) == id
                && AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success
        }
        let existing = window.flatMap { valid($0) ? $0 : nil }
        guard let element = existing ?? resolveWindow(), valid(element) else { completion(.unavailable); return }
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success else {
            completion(.unavailable); return
        }
        verify(id: id, displayID: displayID, progress: DirectWindowActivationProgress(origin: origin, target: target),
               deadline: ProcessInfo.processInfo.systemUptime + 0.6, isCurrent: isCurrent, completion: completion)
    }

    private static func verify(id: CGWindowID, displayID: String, progress: DirectWindowActivationProgress,
                               deadline: TimeInterval, isCurrent: @escaping () -> Bool,
                               completion: @escaping (NativeSpaceSwitcher.ActivationResult) -> Void) {
        guard let display = ApplicationSpaces.displays()?.first(where: { $0.id == displayID }) else {
            completion(.interrupted); return
        }
        let outcome = progress.observe(space: display.currentSpace,
                                       windowIsVisible: ApplicationWindowSnapshot.capture()?.onScreenIDs.contains(id) == true,
                                       isCurrent: isCurrent(), expired: ProcessInfo.processInfo.systemUptime >= deadline)
        switch outcome {
        case .activated: completion(.activated)
        case .interrupted: completion(.interrupted)
        case .unavailable: completion(.unavailable)
        case .waiting:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                verify(id: id, displayID: displayID, progress: progress, deadline: deadline,
                       isCurrent: isCurrent, completion: completion)
            }
        }
    }
}
