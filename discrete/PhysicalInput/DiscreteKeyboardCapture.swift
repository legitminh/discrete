import Cocoa

/// Captures the WHOLE keyboard while discrete is active, swallowing every
/// key event — ordinary keys, modifier presses, and the media events the
/// F-row sends in its default mode — so none of it reaches the frontmost app.
///
/// Distinct from `PhysicalKeyMonitor`: CapsLock alone needs the raw-HID
/// path (see that file's doc comment) to see genuinely quick taps, and
/// keeps using it. Everything else goes through this BLOCKING tap, which
/// only exists between `start()` and `stop()`, so normal typing is
/// completely untouched while discrete is inactive.
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

    var mode: Mode = .triggers {
        didSet {
            guard mode != oldValue else { return }
            sequencer.reset()
        }
    }

    var onTap: ((CGKeyCode) -> Void)?
    var onTyped: ((TypedKey) -> Void)?

    init(settings: UserSettings) {
        sequencer = TapSequencer(settings: settings)
        sequencer.onTap = { [weak self] keyCode in
            DispatchQueue.main.async {
                self?.onTap?(keyCode)
            }
        }
    }

    func start() {
        guard eventTap == nil else { return }
        sequencer.reset()

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
            return
        }
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("⌨️ Discrete keyboard capture ON — keys are being swallowed")
    }

    func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        self.runLoopSource = nil
        sequencer.reset()
        print("⌨️ Discrete keyboard capture OFF")
    }

    // MARK: - Event handling

    /// NX_SYSDEFINED — media/brightness keys arrive as these, not as key events.
    private static let systemDefined = CGEventType(rawValue: 14)!

    /// Returning nil swallows the event — it never reaches the focused app.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let now = ProcessInfo.processInfo.systemUptime

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = Self.normalized(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
            switch mode {
            case .triggers:
                sequencer.keyDown(keyCode, at: now)
            case .typing:
                let typed = TypedKey(keyCode: keyCode, flags: event.flags, characters: Self.characters(of: event))
                DispatchQueue.main.async { [weak self] in
                    self?.onTyped?(typed)
                }
            }
            return nil

        case .keyUp:
            if mode == .triggers {
                let keyCode = Self.normalized(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
                sequencer.keyUp(keyCode, at: now)
            }
            return nil

        case .flagsChanged:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            // CapsLock has its own raw-HID listener; don't interfere with it.
            if keyCode == KeyCode.capsLock { return Unmanaged.passUnretained(event) }
            if mode == .triggers, let isDown = Self.isModifierDown(keyCode, flags: event.flags) {
                if isDown {
                    sequencer.keyDown(keyCode, at: now)
                } else {
                    sequencer.keyUp(keyCode, at: now)
                }
            }
            return nil

        case Self.systemDefined:
            guard let media = Self.mediaKey(from: event) else { return Unmanaged.passUnretained(event) }
            // Media keys with no F-key equivalent are still swallowed, just not inputs.
            if mode == .triggers, !media.isRepeat, let keyCode = media.keyCode {
                if media.isDown {
                    sequencer.keyDown(keyCode, at: now)
                } else {
                    sequencer.keyUp(keyCode, at: now)
                }
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
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
