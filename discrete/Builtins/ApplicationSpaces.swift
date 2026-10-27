import AppKit
import ApplicationServices
import ObjectiveC

/// A small, optional bridge to WindowServer's Spaces information and movement.
/// macOS has no public API for moving another app's window between Spaces.
/// Symbols and Objective-C selectors are checked at runtime, and a move only
/// succeeds once WindowServer confirms the destination. Native full-screen
/// destinations are deliberately excluded; those windows require leaving full
/// screen before they can be moved. No SIP changes or helper process are needed.
///
/// The bridged operation follows DockDoor's PrivateApis.swift implementation:
/// https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/PrivateApis.swift
/// Read-side signatures and Space dictionaries follow yabai's misc/extern.h
/// and display.c: https://github.com/asmvik/yabai/tree/master/src
enum ApplicationSpaces {
    struct Display {
        let id: String
        let currentSpace: UInt64
        /// Mission Control order, including native full-screen Spaces.
        let spaces: [UInt64]
    }

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopyWindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias GetWindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private typealias GetProcessSerialNumber = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias SetFrontProcess = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> Int32
    private typealias PostProcessEvent = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32

    // Keep framework handles open for the lifetime of any resolved pointers.
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let accessibility = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
    private static let mainConnection: MainConnection? = symbol(["SLSMainConnectionID", "CGSMainConnectionID"], from: skyLight)
    private static let copyDisplays: CopyDisplays? = symbol(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], from: skyLight)
    private static let copyWindowSpaces: CopyWindowSpaces? = symbol(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], from: skyLight)
    private static let getWindowID: GetWindowID? = symbol(["_AXUIElementGetWindow"], from: accessibility)
    private static let getProcessSerialNumber: GetProcessSerialNumber? = symbol(["GetProcessForPID"], from: accessibility)
    private static let setFrontProcess: SetFrontProcess? = symbol(["_SLPSSetFrontProcessWithOptions"], from: skyLight)
    private static let postProcessEvent: PostProcessEvent? = symbol(["SLPSPostEventRecordTo"], from: skyLight)

    static func displays() -> [Display]? {
        guard let raw = rawDisplays() else { return nil }
        let result = raw.compactMap { display -> Display? in
            guard let id = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let currentID = spaceID(current),
                  let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
            return Display(id: id, currentSpace: currentID, spaces: spaces.compactMap { spaceID($0) })
        }
        return result.isEmpty ? nil : result
    }

    static func spaces(for windowID: CGWindowID) -> [UInt64]? {
        guard let mainConnection, let copyWindowSpaces,
              let copied = copyWindowSpaces(mainConnection(), 7, [NSNumber(value: windowID)] as CFArray) else { return nil }
        let array = copied.takeRetainedValue() as NSArray
        return array.compactMap { ($0 as? NSNumber)?.uint64Value }
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        guard let getWindowID else { return nil }
        var id: CGWindowID = 0
        return getWindowID(window, &id) == AXError.success.rawValue && id != 0 ? id : nil
    }

    /// Targets one window rather than letting application activation choose its
    /// most recent window. This does not switch desktops: callers must use
    /// switchToSpace first for an inactive Space. The return value only means
    /// the focus request was accepted.
    ///
    /// Event layout and user-generated mode follow yabai's
    /// window_manager_focus_window_with_raise / window_manager_make_key_window:
    /// https://github.com/asmvik/yabai/blob/master/src/window_manager.c
    static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let getProcessSerialNumber, let setFrontProcess, let postProcessEvent else { return false }
        // ProcessSerialNumber is a pair of UInt32s. Raw storage keeps the
        // obsolete Carbon type out of the rest of the application.
        var serialNumber = [UInt32](repeating: 0, count: 2)
        return serialNumber.withUnsafeMutableBytes { serial in
            guard let address = serial.baseAddress,
                  getProcessSerialNumber(pid, address) == 0,
                  setFrontProcess(address, windowID, 0x200) == 0 else { return false }
            var event = [UInt8](repeating: 0, count: 0xf8)
            event[0x04] = 0xf8
            event[0x3a] = 0x10
            for index in 0x20..<0x30 { event[index] = 0xff }
            withUnsafeBytes(of: windowID) { bytes in
                for index in bytes.indices { event[0x3c + index] = bytes[index] }
            }
            event[0x08] = 0x01
            let first = event.withUnsafeMutableBufferPointer { postProcessEvent(address, $0.baseAddress!) }
            event[0x08] = 0x02
            let second = event.withUnsafeMutableBufferPointer { postProcessEvent(address, $0.baseAddress!) }
            return first == 0 && second == 0
        }
    }

    /// The pointer write alone can leave both desktops composited; hide the
    /// origin after separately verifying that the write landed. This sequence
    /// follows https://github.com/KiwiCanopy/KiwiDesk/pull/1031.
    /// Completion also checks the compositor's on-screen window census.
    static func switchToSpace(_ target: UInt64, onDisplay displayID: String,
                              isCurrent: @escaping () -> Bool = { true },
                              completion: @escaping (Bool) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                switchToSpace(target, onDisplay: displayID, isCurrent: isCurrent, completion: completion)
            }
            return
        }
        guard isCurrent(), let display = displays()?.first(where: { $0.id == displayID }),
              display.spaces.contains(target) else { completion(false); return }
        let origin = display.currentSpace
        guard origin != target else { completion(true); return }
        // Resolve both operations first so a missing hide cannot leave a
        // pointer-only transition. A failed set must never blank the origin.
        guard let set = switchOperation(displayID: displayID, space: target),
              let hide = visibilityOperation("SLSBridgedHideSpacesOperation", spaces: [origin]) else {
            completion(false)
            return
        }
        let before = onScreenWindowIDs()
        let records = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var originWindows = Set<CGWindowID>()
        var targetWindows = Set<CGWindowID>()
        for record in records {
            guard (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let membership = spaces(for: id), !membership.isEmpty else { continue }
            // All-desktop windows stay visible and cannot witness a swap.
            if membership.contains(origin) && !membership.contains(target) && before.contains(id) { originWindows.insert(id) }
            if membership.contains(target) && !membership.contains(origin) { targetWindows.insert(id) }
        }
        performOperation(set)
        finishSpaceSwitch(target: target, displayID: displayID, hide: hide,
                          originWindows: originWindows, targetWindows: targetWindows,
                          attempts: 30, didHide: false, isCurrent: isCurrent, completion: completion)
    }

    private static func finishSpaceSwitch(target: UInt64, displayID: String,
                                          hide: AnyObject, originWindows: Set<CGWindowID>, targetWindows: Set<CGWindowID>,
                                          attempts: Int, didHide: Bool, isCurrent: @escaping () -> Bool,
                                          completion: @escaping (Bool) -> Void) {
        let pointerLanded = displays()?.first(where: { $0.id == displayID })?.currentSpace == target
        var hidden = didHide
        if pointerLanded && !hidden {
            // Finish the compositor half of an applied write even if this
            // request was superseded. The current-pointer read immediately
            // above prevents an older request from hiding a desktop that a
            // newer request has already switched back to.
            performOperation(hide)
            hidden = true
        }
        guard isCurrent() else { completion(false); return }
        if pointerLanded && hidden {
            let visible = onScreenWindowIDs()
            let originGone = originWindows.isDisjoint(with: visible)
            let targetVisible = targetWindows.isEmpty || !targetWindows.isDisjoint(with: visible)
            if originGone && targetVisible { completion(true); return }
        }
        guard attempts > 0 else { completion(false); return }
        let nextHidden = hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            finishSpaceSwitch(target: target, displayID: displayID, hide: hide,
                              originWindows: originWindows, targetWindows: targetWindows,
                              attempts: attempts - 1, didHide: nextHidden, isCurrent: isCurrent, completion: completion)
        }
    }

    private static func onScreenWindowIDs() -> Set<CGWindowID> {
        // `.optionAll` can omit kCGWindowIsOnscreen on newer macOS.
        let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(records.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    private static func switchOperation(displayID: String, space: UInt64) -> AnyObject? {
        let selector = NSSelectorFromString("initWithDisplayIdentifier:spaceID:")
        guard skyLight != nil, let cls = NSClassFromString("SLSBridgedManagedDisplaySetCurrentSpaceOperation"),
              let instance = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              instance.responds(to: selector) else { return nil }
        typealias Initialize = @convention(c) (AnyObject, Selector, NSString, UInt64) -> Unmanaged<AnyObject>?
        let initialize = unsafeBitCast(instance.method(for: selector), to: Initialize.self)
        guard let operation = initialize(instance, selector, displayID as NSString, space)?.takeRetainedValue(),
              operation.responds(to: NSSelectorFromString("performWithWMBridgeDelegate")) else { return nil }
        return operation
    }

    private static func visibilityOperation(_ className: String, spaces: [UInt64]) -> AnyObject? {
        let selector = NSSelectorFromString("initWithSpaces:")
        guard skyLight != nil, let cls = NSClassFromString(className),
              let instance = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              instance.responds(to: selector) else { return nil }
        typealias Initialize = @convention(c) (AnyObject, Selector, NSArray) -> Unmanaged<AnyObject>?
        let initialize = unsafeBitCast(instance.method(for: selector), to: Initialize.self)
        guard let operation = initialize(instance, selector, spaces.map { NSNumber(value: $0) } as NSArray)?.takeRetainedValue(),
              operation.responds(to: NSSelectorFromString("performWithWMBridgeDelegate")) else { return nil }
        return operation
    }

    private static func performOperation(_ operation: AnyObject) {
        let selector = NSSelectorFromString("performWithWMBridgeDelegate")
        typealias Perform = @convention(c) (AnyObject, Selector) -> Void
        let perform = unsafeBitCast(operation.method(for: selector), to: Perform.self)
        perform(operation, selector)
    }

    /// Completion runs on the main queue. An accepted operation is asynchronous;
    /// membership is checked for up to one second before reporting success.
    static func move(windowID: CGWindowID, toSpace destination: UInt64, completion: @escaping (Bool) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { move(windowID: windowID, toSpace: destination, completion: completion) }
            return
        }
        guard isUserSpace(destination) else {
            completion(false)
            return
        }
        if spaces(for: windowID)?.contains(destination) == true {
            completion(true)
            return
        }
        guard skyLight != nil,
              let operationClass = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") else {
            completion(false)
            return
        }
        let initialize = NSSelectorFromString("initWithWindows:spaceID:")
        let perform = NSSelectorFromString("performWithWMBridgeDelegate")
        guard let allocated = (operationClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              allocated.responds(to: initialize) else {
            completion(false)
            return
        }
        typealias Initialize = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> Unmanaged<AnyObject>?
        let initializer = unsafeBitCast(allocated.method(for: initialize), to: Initialize.self)
        guard let operation = initializer(allocated, initialize, [NSNumber(value: windowID)] as NSArray, destination)?.takeRetainedValue(),
              operation.responds(to: perform) else {
            completion(false)
            return
        }
        typealias Perform = @convention(c) (AnyObject, Selector) -> Void
        let execute = unsafeBitCast(operation.method(for: perform), to: Perform.self)
        execute(operation, perform)
        verifyMove(windowID: windowID, destination: destination, attempts: 20, completion: completion)
    }

    private static func verifyMove(windowID: CGWindowID, destination: UInt64, attempts: Int, completion: @escaping (Bool) -> Void) {
        if spaces(for: windowID)?.contains(destination) == true {
            completion(true)
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                verifyMove(windowID: windowID, destination: destination, attempts: attempts - 1, completion: completion)
            }
        } else {
            completion(false)
        }
    }

    private static func isUserSpace(_ id: UInt64) -> Bool {
        guard let displays = rawDisplays() else { return false }
        return displays.contains { display in
            (display["Spaces"] as? [[String: Any]] ?? []).contains {
                spaceID($0) == id && ($0["type"] as? NSNumber)?.intValue == 0
            }
        }
    }

    private static func rawDisplays() -> [[String: Any]]? {
        guard let mainConnection, let copyDisplays,
              let copied = copyDisplays(mainConnection()) else { return nil }
        return copied.takeRetainedValue() as? [[String: Any]]
    }

    private static func spaceID(_ dictionary: [String: Any]) -> UInt64? {
        (dictionary["id64"] as? NSNumber)?.uint64Value
            ?? (dictionary["ManagedSpaceID"] as? NSNumber)?.uint64Value
    }

    private static func symbol<T>(_ names: [String], from handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle else { return nil }
        for name in names {
            if let address = dlsym(handle, name) { return unsafeBitCast(address, to: T.self) }
        }
        return nil
    }
}
