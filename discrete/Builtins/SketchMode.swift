import AppKit
import CoreGraphics

/// The "trackpad functions" builtins. While sketch mode is on, a single
/// finger on the trackpad works like a pen on a drawing tablet mapped onto
/// the screen under the pointer: the finger's place on the trackpad is the
/// pointer's place on the screen (centre to centre, corner to corner),
/// touching presses the left mouse button there, moving drags, and lifting
/// releases it and leaves the pointer where it is. Touches with two or
/// more fingers are left alone, so scrolling, right clicks and gestures
/// work as usual.
///
/// Finger positions come from the private MultitouchSupport framework. The
/// trackpad's own pointer events are held back with an event tap while a
/// single finger is down, and the button presses and moves are posted in
/// their place. Needs Accessibility permission, which discrete already
/// asks for.
nonisolated final class SketchMode: @unchecked Sendable {
    static let shared = SketchMode()

    /// How long a lone finger must stay alone before it presses, so the
    /// first finger of a two-finger scroll or click doesn't draw a dot.
    private static let settleTime: TimeInterval = 0.06
    /// How long after a stroke the trackpad's own left clicks (tap to
    /// click, which arrives after the finger lifts) are still held back.
    private static let clickGrace: TimeInterval = 0.5
    /// Marks the events posted here, so the event tap lets them through.
    private static let marker: Int64 = 0x736B_6574_6368

    private enum Phase {
        case idle
        /// One finger is down but hasn't been alone for `settleTime` yet.
        case settling(since: TimeInterval, start: CGPoint)
        /// One finger is down and the left button is pressed.
        case drawing
        /// Two or more fingers touched: ignored until every finger lifts.
        case multiFinger
    }

    private let lock = NSLock()
    private var isOn = false
    private var phase = Phase.idle
    private var sessionDevice: UnsafeMutableRawPointer?
    private var screen = CGRect.zero
    private var lastPoint = CGPoint.zero
    private var graceUntil: TimeInterval = 0
    private var heldBackButtonDown = false

    private var devices: [UnsafeMutableRawPointer] = []
    private var deviceList: CFArray?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    private init() {}

    func toggle() {
        lock.lock()
        let on = isOn
        lock.unlock()
        on ? deactivate() : activate()
    }

    /// Called on the main thread, like `deactivate`. The framework is
    /// called without `lock` held, since it may wait for a frame callback
    /// that is waiting for the lock.
    func activate() {
        guard !isOn else { return }
        guard let multitouch = Multitouch.shared else {
            print("✏️ Sketch mode unavailable: MultitouchSupport not found")
            return
        }
        guard startEventTap() else { return }

        let list = multitouch.createList().takeRetainedValue()
        let found = (0..<CFArrayGetCount(list)).compactMap {
            CFArrayGetValueAtIndex(list, $0).map { UnsafeMutableRawPointer(mutating: $0) }
        }
        lock.lock()
        isOn = true
        phase = .idle
        lock.unlock()
        deviceList = list
        devices = found
        for device in devices {
            multitouch.register(device, Self.frameCallback)
            _ = multitouch.start(device, 0)
        }
        print("✏️ Sketch mode ON (\(devices.count) trackpad(s))")
    }

    func deactivate() {
        lock.lock()
        guard isOn else {
            lock.unlock()
            return
        }
        isOn = false
        endSession()
        lock.unlock()

        if let multitouch = Multitouch.shared {
            for device in devices {
                multitouch.unregister(device, Self.frameCallback)
                _ = multitouch.stop(device)
            }
        }
        devices = []
        deviceList = nil
        stopEventTap()
        print("✏️ Sketch mode OFF")
    }

    // MARK: - Touches (MultitouchSupport's thread)

    private static let frameCallback: Multitouch.FrameCallback = { device, touches, count, _, _ in
        SketchMode.shared.handleFrame(device: device, touches: touches, count: Int(count))
        return 0
    }

    private func handleFrame(device: UnsafeMutableRawPointer?, touches: UnsafeMutableRawPointer?, count: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard isOn else { return }
        if case .idle = phase {} else if device != sessionDevice { return }

        let down = Multitouch.touchingFingers(touches, count: count)
        let now = ProcessInfo.processInfo.systemUptime

        switch (phase, down.count) {
        case (.idle, 0), (.multiFinger, 1...):
            return
        case (.idle, 1):
            sessionDevice = device
            screen = screenUnderPointer()
            let point = map(down[0])
            CGAssociateMouseAndMouseCursorPosition(0)
            post(.mouseMoved, at: point)
            phase = .settling(since: now, start: point)
        case (.idle, _):
            sessionDevice = device
            phase = .multiFinger
        case (.settling(let since, let start), 1):
            let point = map(down[0])
            if now - since >= Self.settleTime {
                post(.leftMouseDown, at: start)
                post(.leftMouseDragged, at: point)
                phase = .drawing
            } else {
                post(.mouseMoved, at: point)
            }
        case (.settling, 0):
            // A quick tap: a click where the finger touched.
            post(.leftMouseDown, at: lastPoint)
            post(.leftMouseUp, at: lastPoint)
            endSession()
        case (.drawing, 1):
            post(.leftMouseDragged, at: map(down[0]))
        case (.drawing, 0):
            endSession()
        case (.settling, _), (.drawing, _):
            endSession()
            phase = .multiFinger
            sessionDevice = device
        case (.multiFinger, _):
            sessionDevice = nil
            phase = .idle
        }
    }

    /// Releases the button if a stroke is in progress and gives the
    /// pointer back to the trackpad. Call with `lock` held.
    private func endSession() {
        if case .drawing = phase {
            post(.leftMouseUp, at: lastPoint)
        }
        switch phase {
        case .settling, .drawing:
            graceUntil = ProcessInfo.processInfo.systemUptime + Self.clickGrace
            CGAssociateMouseAndMouseCursorPosition(1)
        case .idle, .multiFinger:
            break
        }
        phase = .idle
        sessionDevice = nil
    }

    /// The display under the pointer, in global (top-left origin) coordinates.
    private func screenUnderPointer() -> CGRect {
        let pointer = CGEvent(source: nil)?.location ?? .zero
        var display = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(pointer, 1, &display, &count)
        return CGDisplayBounds(display)
    }

    /// Trackpad coordinates run 0...1 left to right and bottom to top.
    private func map(_ finger: CGPoint) -> CGPoint {
        let x = min(max(finger.x, 0), 1), y = min(max(finger.y, 0), 1)
        return CGPoint(
            x: min(screen.minX + x * screen.width, screen.maxX - 1),
            y: min(screen.minY + (1 - y) * screen.height, screen.maxY - 1)
        )
    }

    private func post(_ type: CGEventType, at point: CGPoint) {
        lastPoint = point
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        if type != .mouseMoved {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Holding back the trackpad's own pointer events

    private func startEventTap() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                SketchMode.shared.handle(type: type, event: event)
            },
            userInfo: nil
        ) else {
            print("❌ Failed to create sketch mode event tap")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("❌ Failed to create run loop source for sketch mode")
            return false
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func stopEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(eventTap)
        self.eventTap = nil
        self.runLoopSource = nil
    }

    /// Returning nil swallows the event. While a lone finger is down every
    /// pointer move and left click from the hardware is held back (the
    /// ones posted here go through); for a moment after, so are the
    /// trackpad's tap-to-click presses, with their matching releases.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock()
        defer { lock.unlock() }

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap, isOn { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        default:
            break
        }
        guard isOn, event.getIntegerValueField(.eventSourceUserData) != Self.marker else {
            return Unmanaged.passUnretained(event)
        }

        let inSession: Bool
        switch phase {
        case .settling, .drawing: inSession = true
        case .idle, .multiFinger: inSession = false
        }
        let inGrace = ProcessInfo.processInfo.systemUptime < graceUntil

        switch type {
        case .leftMouseDown where inSession || inGrace:
            heldBackButtonDown = true
            return nil
        case .leftMouseUp where heldBackButtonDown:
            heldBackButtonDown = false
            return nil
        case .mouseMoved, .leftMouseDragged, .leftMouseUp:
            return inSession ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

/// The few MultitouchSupport (private framework) calls sketch mode needs,
/// looked up at runtime.
nonisolated private struct Multitouch: @unchecked Sendable {
    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    let createList: @convention(c) () -> Unmanaged<CFArray>
    let register: @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
    let unregister: @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
    let start: @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    let stop: @convention(c) (UnsafeMutableRawPointer) -> Int32

    static let shared: Multitouch? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let createList = symbol("MTDeviceCreateList", as: (@convention(c) () -> Unmanaged<CFArray>).self),
              let register = symbol("MTRegisterContactFrameCallback", as: (@convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void).self),
              let unregister = symbol("MTUnregisterContactFrameCallback", as: (@convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void).self),
              let start = symbol("MTDeviceStart", as: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Int32).self),
              let stop = symbol("MTDeviceStop", as: (@convention(c) (UnsafeMutableRawPointer) -> Int32).self) else { return nil }
        return Multitouch(createList: createList, register: register, unregister: unregister, start: start, stop: stop)
    }()

    // The framework's per-finger record (MTTouch): 96 bytes, with the
    // touch state at byte 20, the finger it was recognized as at byte 24,
    // and the normalized position at bytes 32 and 36.
    private static let touchStride = 96
    private static let stateOffset = 20
    private static let fingerOffset = 24
    private static let positionOffset = 32
    /// "making touch" and "touching"; the other states are hovering,
    /// lifting or gone.
    private static let touchingStates: ClosedRange<Int32> = 3...4
    /// Thumb, index, middle, ring and little finger. Any other kind of
    /// contact (the side of a resting hand shows up as 7 or 10, pinned to
    /// the trackpad's edge) is ignored, as macOS's palm rejection does.
    private static let fingertips: ClosedRange<Int32> = 1...5

    /// Normalized positions (0...1, origin bottom-left) of the fingertips
    /// currently on the surface.
    static func touchingFingers(_ touches: UnsafeMutableRawPointer?, count: Int) -> [CGPoint] {
        guard let touches else { return [] }
        return (0..<count).compactMap { index in
            let touch = touches + index * touchStride
            guard touchingStates.contains(touch.load(fromByteOffset: stateOffset, as: Int32.self)),
                  fingertips.contains(touch.load(fromByteOffset: fingerOffset, as: Int32.self)) else { return nil }
            return CGPoint(
                x: CGFloat(touch.load(fromByteOffset: positionOffset, as: Float.self)),
                y: CGFloat(touch.load(fromByteOffset: positionOffset + 4, as: Float.self))
            )
        }
    }
}

