import AppKit

/// Routes Space changes through Dock's native transition rather than mutating
/// WindowServer's current-Space pointer. Only one gesture is in flight, and a
/// canceled request waits for that gesture to settle before releasing the queue.
enum NativeSpaceSwitcher {
    private struct Request {
        let target: UInt64
        let display: String
        let isCurrent: () -> Bool
        let completion: (Bool) -> Void
    }

    private static var requests: [Request] = []
    private static var busy = false

    static func switchToSpace(_ target: UInt64, onDisplay display: String,
                              isCurrent: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                switchToSpace(target, onDisplay: display, isCurrent: isCurrent, completion: completion)
            }
            return
        }
        requests.append(Request(target: target, display: display, isCurrent: isCurrent, completion: completion))
        if !busy { advance() }
    }

    private static func advance() {
        guard !requests.isEmpty else { busy = false; return }
        busy = true
        step(requests.removeFirst())
    }

    private static func finish(_ request: Request, success: Bool) {
        // Keep busy during the callback, which may enqueue another request.
        request.completion(success && request.isCurrent())
        advance()
    }

    private static func step(_ request: Request) {
        guard request.isCurrent(),
              let display = ApplicationSpaces.displays()?.first(where: { $0.id == request.display }),
              let current = display.spaces.firstIndex(of: display.currentSpace),
              let target = display.spaces.firstIndex(of: request.target) else { finish(request, success: false); return }
        guard current != target else { finish(request, success: true); return }
        let next = display.spaces[current + (target > current ? 1 : -1)]
        guard let location = gestureLocation(displayID: request.display),
              postGesture(right: target > current, location: location) else { finish(request, success: false); return }
        settle(request, progress: NativeSpaceTransition(origin: display.currentSpace, expected: next), attempts: 50)
    }

    private static func settle(_ request: Request, progress: NativeSpaceTransition, attempts: Int) {
        guard let display = ApplicationSpaces.displays()?.first(where: { $0.id == request.display }) else {
            finish(request, success: false); return
        }
        var progress = progress
        switch progress.observe(space: display.currentSpace, at: ProcessInfo.processInfo.systemUptime,
                                isCurrent: request.isCurrent()) {
        case .interrupted: finish(request, success: false)
        case .settled: step(request)
        case .waiting:
            guard attempts > 0 else { finish(request, success: false); return }
            let nextProgress = progress
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                settle(request, progress: nextProgress, attempts: attempts - 1)
            }
        }
    }

    private static func gestureLocation(displayID: String) -> CGPoint? {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return false }
            return CFUUIDCreateString(nil, uuid) as String == displayID
        }) ?? (ApplicationSpaces.displays()?.count == 1 ? screens.first : nil),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let frame = CGDisplayBounds(number.uint32Value)
        let pointer = CGEvent(source: nil)?.location ?? CGPoint(x: frame.midX, y: frame.midY)
        return frame.contains(pointer) ? pointer : CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Gesture field definitions/protocol documented by InstantSpaceSwitcher:
    /// https://github.com/jurplel/InstantSpaceSwitcher/blob/main/Sources/ISS/ISS.c
    /// Three phases close the gesture cleanly, including Mission Control state.
    private static func postGesture(right: Bool, location: CGPoint) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        // macOS 27 uses a different HID payload. Use the native system keyboard
        // shortcut there, verifying its result, rather than writing Space state.
        if #available(macOS 27, *) {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: right ? 124 : 123, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: right ? 124 : 123, keyDown: false) else { return false }
            down.flags = .maskControl; up.flags = .maskControl
            down.location = location; up.location = location
            down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
            return true
        }
        let sign = right ? 1.0 : -1.0
        // Construct the entire gesture before sending anything; an allocation
        // failure must not leave Dock with an unfinished began phase.
        let phases: [Int64] = [1, 2, 4]
        let events = phases.compactMap { phase -> CGEvent? in
            guard let event = CGEvent(source: nil) else { return nil }
            event.location = location
            event.flags = []
            func integer(_ field: UInt32, _ value: Int64) {
                event.setIntegerValueField(CGEventField(rawValue: field)!, value: value)
            }
            func double(_ field: UInt32, _ value: Double) {
                event.setDoubleValueField(CGEventField(rawValue: field)!, value: value)
            }
            integer(55, 30) // Dock-control event
            integer(110, 23) // IOHID Dock swipe
            integer(123, 1) // horizontal motion
            integer(132, phase)
            double(124, sign * 0.000016)
            double(129, sign * 2000)
            double(130, sign * 2000)
            return event
        }
        guard events.count == phases.count else { return false }
        events.forEach { $0.post(tap: .cgSessionEventTap) }
        return true
    }
}
