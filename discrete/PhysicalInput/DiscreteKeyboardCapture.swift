import Cocoa

/// Captures the WHOLE keyboard while discrete is active, swallowing every
/// key event — ordinary keys, modifier presses, and the media events the
/// F-row sends in its default mode — so none of it reaches the frontmost app.
///
/// Distinct from `PhysicalKeyMonitor`: CapsLock alone needs the raw-HID
/// path (see that file's doc comment) to see genuinely quick taps, and
/// keeps using it. Everything else goes through this BLOCKING tap, which
/// remains installed while inactive, passing normal input through. Between
/// CapsLock-down and its tap/hold decision it temporarily buffers shortcut
/// keys; a tap replays them to discrete and a hold returns them to the app.
///
/// Two ways of reading keys, per the spec:
///   - `.triggers`: the tap rule — down/up pairs go through `TapSequencer`
///     and come out as `onTap` in press order.
///   - `.typing`: state.text_string — every key-down (including
///     auto-repeat) comes out as `onTyped`, like a normal text field.
final class DiscreteKeyboardCapture {
    enum Mode {
        case triggers
        case typing
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let sequencer: TapSequencer
    private let settings: UserSettings
    private let postDeferredEvent: (CGEvent) -> Void
    private var isCapturing = false
    private var deliveryGeneration = 0
    private var activationGeneration = 0
    private var activation = CapsLockActivationBuffer<BufferedInput>()
    private var deferredEvents: [CGEvent] = []
    private var keysDown: Set<CGKeyCode> = []
    private var ignoredUntilRelease: Set<CGKeyCode> = []

    private struct BufferedInput {
        let keyCode: CGKeyCode
        /// Only ordinary key-downs type; modifiers/media keys are triggers.
        let typed: TypedKey?
    }

    private struct KeyEvent {
        let keyCode: CGKeyCode
        let isDown: Bool
        let isRepeat: Bool
        let typed: TypedKey?
    }

    /// Reposted hold input must pass through without being buffered again.
    private static let deferredEventTag: Int64 = 0x4449_5343_5245_5445

    var mode: Mode = .triggers {
        didSet {
            guard mode != oldValue else { return }
            sequencer.reset()
        }
    }

    var onTap: ((CGKeyCode) -> Void)?
    var onTyped: ((TypedKey) -> Void)?

    init(settings: UserSettings, postDeferredEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }) {
        self.settings = settings
        self.postDeferredEvent = postDeferredEvent
        sequencer = TapSequencer(settings: settings)
        sequencer.onTap = { [weak self] keyCode in
            guard let self else { return }
            let generation = self.deliveryGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCapturing, self.deliveryGeneration == generation else { return }
                self.onTap?(keyCode)
            }
        }
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource { CFRunLoopSourceInvalidate(runLoopSource) }
    }

    /// Install before the CapsLock HID listener starts, closing the activation
    /// gap without consuming normal inactive input.
    func observe() {
        guard eventTap == nil else { return }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, Self.systemDefined]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let capture = Unmanaged<DiscreteKeyboardCapture>.fromOpaque(refcon).takeUnretainedValue()
                return capture.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            print("❌ Failed to create discrete keyboard capture tap")
            return
        }
        eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("❌ Failed to create run loop source for keyboard capture")
            self.eventTap = nil
            return
        }
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("⌨️ Keyboard observer ready — inactive input passes through")
    }

    func start() {
        observe()
        guard eventTap != nil, !isCapturing else { return }
        isCapturing = true
        deliveryGeneration += 1
        sequencer.reset()
        print("⌨️ Discrete keyboard capture ON — keys are being swallowed")
    }

    func stop() {
        guard isCapturing else { return }
        isCapturing = false
        deliveryGeneration += 1
        sequencer.reset()
        print("⌨️ Discrete keyboard capture OFF")
    }

    func beginActivation(at time: TimeInterval) {
        observe()
        guard eventTap != nil, !isCapturing, !activation.isPending else { return }
        activation.begin(at: time)
        deferredEvents.removeAll()
        activationGeneration += 1
        let generation = activationGeneration
        let remaining = max(0, settings.clickHoldThreshold - (ProcessInfo.processInfo.systemUptime - time))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.activationGeneration == generation else { return }
            self.cancelActivation()
        }
    }

    /// A hold is regular computer use, so return its deferred input in order.
    func cancelActivation() {
        guard activation.isPending else { return }
        activationGeneration += 1
        activation.cancel()
        let events = deferredEvents
        deferredEvents.removeAll()
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.deferredEventTag)
            postDeferredEvent(event)
        }
    }

    /// Treat each buffered down as one immediate release, oldest first. The
    /// callbacks run synchronously so mode changes take effect between inputs.
    func replayActivation() {
        guard activation.isPending else { return }
        guard isCapturing else { cancelActivation(); return }
        activationGeneration += 1
        let buffered = activation.finish()
        deferredEvents.removeAll()
        ignoredUntilRelease.formUnion(buffered.heldKeys)
        for input in buffered.inputs {
            guard isCapturing else { break } // An action exited, or opened a picker.
            switch mode {
            case .triggers:
                onTap?(input.keyCode)
            case .typing:
                if let typed = input.typed { onTyped?(typed) }
            }
        }
    }

    // MARK: - Event handling

    /// NX_SYSDEFINED — media/brightness keys arrive as these, not as key events.
    private static let systemDefined = CGEventType(rawValue: 14)!

    /// Returning nil swallows the event — it never reaches the focused app.
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.deferredEventTag {
            return Unmanaged.passUnretained(event)
        }
        let now = ProcessInfo.processInfo.systemUptime
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            cancelActivation()
            keysDown.removeAll()
            ignoredUntilRelease.removeAll()
            return Unmanaged.passUnretained(event)
        }

        guard let key = Self.keyEvent(type: type, event: event) else {
            // CapsLock remains on its independent raw-HID path.
            if type == .flagsChanged,
               CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == KeyCode.capsLock {
                return Unmanaged.passUnretained(event)
            }
            if isCapturing, type == .flagsChanged || (type == Self.systemDefined && Self.mediaKey(from: event) != nil) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        let isNewDown: Bool
        if key.isDown {
            isNewDown = keysDown.insert(key.keyCode).inserted && !key.isRepeat
        } else {
            keysDown.remove(key.keyCode)
            isNewDown = false
        }
        if ignoredUntilRelease.contains(key.keyCode) {
            if !key.isDown { ignoredUntilRelease.remove(key.keyCode) }
            return nil
        }
        if activation.isPending {
            let belongsToActivation = activation.containsHeldKey(key.keyCode) || isNewDown
            if belongsToActivation {
                if let original = event.copy() { deferredEvents.append(original) }
                if key.isDown {
                    if isNewDown {
                        activation.keyDown(key.keyCode, input: BufferedInput(keyCode: key.keyCode, typed: key.typed))
                    }
                } else {
                    activation.keyUp(key.keyCode)
                }
            }
            if let start = activation.startedAt, now - start >= settings.clickHoldThreshold {
                cancelActivation()
            }
            return belongsToActivation ? nil : Unmanaged.passUnretained(event)
        }
        guard isCapturing else { return Unmanaged.passUnretained(event) }

        switch mode {
        case .triggers:
            if key.isDown {
                if !key.isRepeat { sequencer.keyDown(key.keyCode, at: now) }
            } else {
                sequencer.keyUp(key.keyCode, at: now)
            }
        case .typing:
            if key.isDown, let typed = key.typed {
                let generation = deliveryGeneration
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCapturing, self.deliveryGeneration == generation else { return }
                    self.onTyped?(typed)
                }
            }
        }
        return nil
    }

    private static func keyEvent(type: CGEventType, event: CGEvent) -> KeyEvent? {
        switch type {
        case .keyDown, .keyUp:
            let code = normalized(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
            guard code != KeyCode.capsLock else { return nil }
            let typed = type == .keyDown ? TypedKey(keyCode: code, flags: event.flags, characters: characters(of: event)) : nil
            return KeyEvent(keyCode: code, isDown: type == .keyDown,
                            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, typed: typed)
        case .flagsChanged:
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard code != KeyCode.capsLock, let down = isModifierDown(code, flags: event.flags) else { return nil }
            return KeyEvent(keyCode: code, isDown: down, isRepeat: false, typed: nil)
        case systemDefined:
            guard let media = mediaKey(from: event), let code = media.keyCode else { return nil }
            return KeyEvent(keyCode: code, isDown: media.isDown, isRepeat: media.isRepeat, typed: nil)
        default: return nil
        }
    }

    private static func characters(of event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: - Modifiers

    /// Device-dependent flag bits (IOLLEvent.h NX_DEVICE*KEYMASK) — the only
    /// way to tell which side of a modifier pair went down or up.
    private static let modifierDeviceMasks: [CGKeyCode: UInt64] = [
        KeyCode.leftControl: 0x0000_0001,
        KeyCode.leftShift: 0x0000_0002,
        KeyCode.rightShift: 0x0000_0004,
        KeyCode.leftCommand: 0x0000_0008,
        KeyCode.rightCommand: 0x0000_0010,
        KeyCode.leftOption: 0x0000_0020,
        KeyCode.rightOption: 0x0000_0040,
        KeyCode.rightControl: 0x0000_2000
    ]

    private static func isModifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool? {
        if keyCode == KeyCode.function {
            return flags.contains(.maskSecondaryFn)
        }
        guard let mask = modifierDeviceMasks[keyCode] else { return nil }
        return flags.rawValue & mask != 0
    }

    // MARK: - F-row in media mode

    /// Newer Macs send some top-row keys as ordinary key events with their
    /// own codes (Mission Control, Spotlight, ...) — map those back to the
    /// F-key at that position. NEEDS VERIFICATION per keyboard model.
    private static let specialTopRowKeys: [CGKeyCode: CGKeyCode] = [
        160: KeyCode.fKeys[2],  // Mission Control → F3
        131: KeyCode.fKeys[3],  // Launchpad → F4
        177: KeyCode.fKeys[3],  // Spotlight → F4
        176: KeyCode.fKeys[4],  // Dictation → F5
        178: KeyCode.fKeys[5]   // Do Not Disturb → F6
    ]

    private static func normalized(_ keyCode: CGKeyCode) -> CGKeyCode {
        specialTopRowKeys[keyCode] ?? keyCode
    }

    /// NX_KEYTYPE_* (ev_keymap.h) → the F-key that sends it on an Apple keyboard.
    private static let mediaKeyFKeys: [Int: CGKeyCode] = [
        3: KeyCode.fKeys[0],   // brightness down → F1
        2: KeyCode.fKeys[1],   // brightness up → F2
        22: KeyCode.fKeys[4],  // illumination down → F5
        21: KeyCode.fKeys[5],  // illumination up → F6
        20: KeyCode.fKeys[6], 18: KeyCode.fKeys[6],  // rewind / previous → F7
        16: KeyCode.fKeys[7],  // play → F8
        19: KeyCode.fKeys[8], 17: KeyCode.fKeys[8],  // fast / next → F9
        7: KeyCode.fKeys[9],   // mute → F10
        1: KeyCode.fKeys[10],  // volume down → F11
        0: KeyCode.fKeys[11]   // volume up → F12
    ]

    private static func mediaKey(from event: CGEvent) -> (keyCode: CGKeyCode?, isDown: Bool, isRepeat: Bool)? {
        // Subtype 8 = NX_SUBTYPE_AUX_CONTROL_BUTTONS; other system-defined
        // events (mouse aux buttons, etc.) aren't keys and pass through.
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return nil }
        let data1 = nsEvent.data1
        let keyType = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0xFFFF
        let state = (keyFlags & 0xFF00) >> 8
        return (mediaKeyFKeys[keyType], state == 0x0A, keyFlags & 0x1 != 0)
    }
}
