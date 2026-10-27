import AppKit
import ApplicationServices

/// The app-only part of opening resources, also exposed as a builtin.
/// Selection is pure (`ApplicationOpenPolicy`); private Spaces calls live in
/// `ApplicationSpaces`, and window geometry stays in `WindowMover`.
enum ApplicationOpener {
    private struct Window {
        let id: CGWindowID
        let app: NSRunningApplication
        let element: AXUIElement?
        let policy: ApplicationOpenPolicy.Window
    }

    private struct Destination {
        let screen: NSScreen
        let displayID: String
        let spacesDisplayID: String
        let currentSpace: UInt64
        let orderedSpaces: [UInt64]
        let allDisplays: [ApplicationSpaces.Display]
    }

    // A later invocation supersedes delayed launch/Space-move completions.
    private static var generation = 0
    // Chrome may omit inactive fullscreen windows from subsequent AXWindows
    // reads. A previously published reference can still raise its exact window.
    private static var rememberedWindows: [pid_t: [CGWindowID: AXUIElement]] = [:]

    static func open(argument: String?) {
        guard let url = applicationURL(argument ?? "") else {
            print("🪟 Application not found: \(argument ?? "")")
            return
        }
        open(url)
    }

    static func open(_ url: URL) {
        generation += 1
        let request = generation
        guard AXIsProcessTrusted(), let destination = destination() else {
            NSWorkspace.shared.open(url)
            return
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
        }
        guard let windows = windows(of: apps, destination: destination) else {
            // Unknown membership is not evidence that a window is hidden.
            NSWorkspace.shared.open(url)
            return
        }
        let action = ApplicationOpenPolicy.choose(
            windows: windows.map(\.policy), display: destination.displayID,
            currentSpace: destination.currentSpace, orderedSpaces: destination.orderedSpaces,
            monitorCount: NSScreen.screens.count, focusedWindowID: focusedWindowID(of: apps)
        )
        switch action {
        case .launch:
            launch(url, destination: destination, request: request)
        case .focus(let id):
            if let window = windows.first(where: { $0.id == id }) {
                focus(window, preferredDisplay: destination.spacesDisplayID, request: request)
            }
        case .bring(let id):
            if let window = windows.first(where: { $0.id == id }) {
                bring(window, destination: destination, request: request)
            }
        }
    }

    /// Focus one known WindowServer window without applying app cycling policy.
    /// Browser automation uses this after correlating its separate window IDs.
    static func focusWindow(id: CGWindowID, app: NSRunningApplication, completion: @escaping () -> Void) {
        generation += 1
        let window = Window(id: id, app: app, element: axWindows(app).first { ApplicationSpaces.windowID(of: $0) == id },
                            policy: .init(id: id, spaces: ApplicationSpaces.spaces(for: id) ?? [],
                                          display: nil, isDisplayed: false))
        focus(window, request: generation, completion: completion)
    }

    /// Resolve a builtin argument without executing arbitrary text or URLs.
    static func applicationURL(_ argument: String) -> URL? {
        let name = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let path = (name as NSString).expandingTildeInPath
        if path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path)
            return url.pathExtension.lowercased() == "app" && FileManager.default.fileExists(atPath: path) ? url : nil
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url }
        let match = (name as NSString).deletingPathExtension
        return AppCatalog.apps().sorted { $0.path < $1.path }.first {
            $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(match) == .orderedSame
        }
    }

    private static func destination() -> Destination? {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }),
              let id = displayID(screen), let displays = ApplicationSpaces.displays(),
              // With "Displays have separate Spaces" disabled, WindowServer
              // reports one shared set of desktops for every physical monitor.
              let display = displays.first(where: { $0.id == id }) ?? (displays.count == 1 ? displays.first : nil) else { return nil }
        return Destination(screen: screen, displayID: id, spacesDisplayID: display.id, currentSpace: display.currentSpace,
                           orderedSpaces: display.spaces, allDisplays: displays)
    }

    private static func displayID(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// CG includes inactive Spaces even when an app's AXWindows does not.
    /// Window titles aren't needed, so Screen Recording permission isn't needed.
    private static func windows(of apps: [NSRunningApplication], destination: Destination) -> [Window]? {
        guard let snapshot = ApplicationWindowSnapshot.capture() else { return nil }
        let livePIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let liveIDs = Set(snapshot.records.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        rememberedWindows = rememberedWindows.filter { livePIDs.contains($0.key) }.mapValues {
            $0.filter { liveIDs.contains($0.key) }
        }
        let currentSpaces = Set(destination.allDisplays.map(\.currentSpace))
        let ordered = destination.allDisplays.flatMap(\.spaces)
        var ranks: [UInt64: Int] = [:]
        for (rank, space) in ordered.enumerated() where ranks[space] == nil { ranks[space] = rank }
        var result: [Window] = []
        for app in apps {
            let accessible = axWindows(app)
            var elements: [CGWindowID: AXUIElement] = [:]
            for element in accessible {
                if let id = ApplicationSpaces.windowID(of: element) { elements[id] = element }
            }
            let accessibleSpaces = Set(elements.compactMap { id, element -> [UInt64]? in
                let subrole = attribute(element, kAXSubroleAttribute) as? String
                guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
                return ApplicationSpaces.spaces(for: id)
            }.flatMap { $0 })
            let records = snapshot.records.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier }
            var ids = Set<CGWindowID>()
            for record in records {
                guard (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      let id = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                      let frame = cgFrame(record), frame.width > 0, frame.height > 0 else { continue }
                ids.insert(id)
            }
            ids.formUnion(elements.keys)
            for id in ids {
                let element = elements[id]
                if let element, let subrole = attribute(element, kAXSubroleAttribute) as? String,
                   subrole != kAXStandardWindowSubrole && subrole != kAXDialogSubrole { continue }
                guard let spaces = ApplicationSpaces.spaces(for: id) else { return nil }
                // Chrome creates transient layer-zero surfaces with no desktop
                // membership. They are not application windows to activate.
                guard !spaces.isEmpty else { continue }
                // Fullscreen Chrome also creates layer-zero toolbar/compositor
                // surfaces. Where AX provides real windows for a Space, trust
                // that list; use CG-only candidates for omitted Spaces only.
                if element == nil && !accessibleSpaces.isDisjoint(with: spaces) { continue }
                let record = records.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }
                let frame = record.flatMap { cgFrame($0) }
                let screen = frame.flatMap { screenForCGFrame($0) }
                let minimized = element.flatMap { attribute($0, kAXMinimizedAttribute) as? Bool } ?? false
                let onScreen = snapshot.onScreenIDs.contains(id)
                result.append(Window(id: id, app: app, element: element, policy: .init(
                    id: id, spaces: spaces, display: screen.flatMap { displayID($0) },
                    isDisplayed: onScreen && !minimized && !app.isHidden && !currentSpaces.isDisjoint(with: spaces)
                )))
            }
        }
        return result.sorted {
            let lhs = $0.policy.spaces.compactMap { ranks[$0] }.min() ?? Int.max
            let rhs = $1.policy.spaces.compactMap { ranks[$0] }.min() ?? Int.max
            return (lhs, $0.id) < (rhs, $1.id)
        }
    }

    private static func cgFrame(_ record: [String: Any]) -> CGRect? {
        guard let bounds = record[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private static func screenForCGFrame(_ frame: CGRect) -> NSScreen? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let converted = CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
        return NSScreen.screens.max {
            func overlap(_ screen: NSScreen) -> CGFloat {
                let area = screen.frame.intersection(converted)
                return area.isNull ? 0 : area.width * area.height
            }
            return overlap($0) < overlap($1)
        }
    }

    private static func bring(_ window: Window, destination: Destination, request: Int) {
        guard request == generation else { return }
        window.app.unhide()
        if let element = window.element {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            WindowMover.move(element, to: destination.screen, isCurrent: { request == generation }, prepare: { done in
                guard request == generation else { done(false); return }
                ApplicationSpaces.move(windowID: window.id, toSpace: destination.currentSpace, completion: done)
            }) { success in
                guard request == generation else { return }
                if !success { print("🪟 Couldn't bring window to the pointer's desktop; focusing its existing Space") }
                focus(window, request: request)
            }
        } else {
            // Inactive-Space AX windows can become accessible after reassignment.
            ApplicationSpaces.move(windowID: window.id, toSpace: destination.currentSpace) { success in
                guard request == generation else { return }
                if success {
                    placeAfterMove(window, destination: destination, request: request, attempts: 10)
                } else {
                    // A native fullscreen window must be made accessible and
                    // leave fullscreen before it can be reassigned to a desktop.
                    focus(window, request: request)
                    recoverAccessibleWindow(window, destination: destination, request: request, attempts: 10)
                }
            }
        }
    }

    private static func placeAfterMove(_ window: Window, destination: Destination, request: Int, attempts: Int) {
        guard request == generation else { return }
        if let element = axWindows(window.app).first(where: { ApplicationSpaces.windowID(of: $0) == window.id }) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            WindowMover.move(element, to: destination.screen, isCurrent: { request == generation }) { _ in
                if request == generation { focus(window, request: request) }
            }
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                placeAfterMove(window, destination: destination, request: request, attempts: attempts - 1)
            }
        } else {
            print("🪟 Window moved Spaces but its geometry isn't accessible")
            focus(window, request: request)
        }
    }

    private static func recoverAccessibleWindow(_ window: Window, destination: Destination, request: Int, attempts: Int) {
        guard request == generation else { return }
        if let element = axWindows(window.app).first(where: { ApplicationSpaces.windowID(of: $0) == window.id }) {
            let recovered = Window(id: window.id, app: window.app, element: element, policy: window.policy)
            bring(recovered, destination: destination, request: request)
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                recoverAccessibleWindow(window, destination: destination, request: request, attempts: attempts - 1)
            }
        } else {
            print("🪟 Window isn't accessible for movement; retaining focus on its existing Space")
        }
    }

    private static func focus(_ window: Window, preferredDisplay: String? = nil, request: Int,
                              completion: @escaping () -> Void = {}) {
        guard request == generation else { completion(); return }
        let spaces = ApplicationSpaces.spaces(for: window.id) ?? window.policy.spaces
        let displays = ApplicationSpaces.displays() ?? []
        let display = displays.first { $0.id == preferredDisplay && !$0.spaces.filter(spaces.contains).isEmpty }
            ?? displays.first { !$0.spaces.filter(spaces.contains).isEmpty }
        guard let display, !spaces.contains(display.currentSpace),
              let target = display.spaces.first(where: spaces.contains) else {
            focusOnActiveSpace(window, request: request, completion: completion)
            return
        }
        let element = window.element ?? rememberedWindows[window.app.processIdentifier]?[window.id]
        let direct: NativeSpaceSwitcher.DirectActivation = { done in
            DirectWindowActivation.raise(window: element, id: window.id, app: window.app,
                                         target: target, displayID: display.id,
                                         resolveWindow: { axWindows(window.app).first { ApplicationSpaces.windowID(of: $0) == window.id } },
                                         isCurrent: { request == generation }, completion: done)
        }
        // Try a single native window activation first. Serialized native
        // navigation remains the fallback for unpublished/stale AX references.
        ApplicationSpaces.switchToSpace(target, onDisplay: display.id, isCurrent: { request == generation },
                                        activateDirectly: direct) { success in
            guard request == generation else { completion(); return }
            guard success else {
                print("🪟 Desktop switch interrupted; retaining the current desktop")
                completion()
                return
            }
            focusOnActiveSpace(window, request: request, completion: completion)
        }
    }

    private static func focusOnActiveSpace(_ window: Window, request: Int, attempts: Int = 10,
                                           completion: @escaping () -> Void = {}) {
        guard request == generation else { completion(); return }
        let candidates = axWindows(window.app).filter {
            let role = attribute($0, kAXSubroleAttribute) as? String
            return role == kAXStandardWindowSubrole || role == kAXDialogSubrole
        }
        let targetSpaces = ApplicationSpaces.spaces(for: window.id) ?? window.policy.spaces
        let element = candidates.first { ApplicationSpaces.windowID(of: $0) == window.id }
            ?? candidates.first {
                guard let id = ApplicationSpaces.windowID(of: $0) else { return false }
                return !(ApplicationSpaces.spaces(for: id) ?? []).filter(targetSpaces.contains).isEmpty
            }
        if element == nil && attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusOnActiveSpace(window, request: request, attempts: attempts - 1, completion: completion)
            }
            return
        }
        window.app.unhide()
        if let element { AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        let id = element.flatMap { ApplicationSpaces.windowID(of: $0) } ?? window.id
        if !ApplicationSpaces.focus(windowID: id, pid: window.app.processIdentifier) { window.app.activate() }
        if let element {
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        completion()
    }

    private static func launch(_ url: URL, destination: Destination, request: Int) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                guard request == generation else { return }
                guard let app else {
                    print("🪟 Couldn't launch application: \(error?.localizedDescription ?? url.path)")
                    return
                }
                awaitFirstWindow(app, destination: destination, request: request, attempts: 40)
            }
        }
    }

    private static func awaitFirstWindow(_ app: NSRunningApplication, destination: Destination, request: Int, attempts: Int) {
        guard request == generation else { return }
        if let window = windows(of: [app], destination: destination)?.first {
            bring(window, destination: destination, request: request)
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                awaitFirstWindow(app, destination: destination, request: request, attempts: attempts - 1)
            }
        } else {
            // Menu-bar apps and apps without accessible windows still activate.
            app.activate()
        }
    }

    private static func axWindows(_ app: NSRunningApplication) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        var windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let value = attribute(application, name), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let element = value as! AXUIElement
                if !windows.contains(where: { CFEqual($0, element) }) { windows.append(element) }
            }
        }
        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.3)
            if let id = ApplicationSpaces.windowID(of: window) {
                rememberedWindows[app.processIdentifier, default: [:]][id] = window
            }
        }
        return windows
    }

    private static func focusedWindowID(of apps: [NSRunningApplication]) -> CGWindowID? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              apps.contains(where: { $0.processIdentifier == frontmost.processIdentifier }),
              let value = attribute(AXUIElementCreateApplication(frontmost.processIdentifier), kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return ApplicationSpaces.windowID(of: value as! AXUIElement)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
