import Cocoa

/// Captures the WHOLE keyboard, swallowing every key so it never reaches
/// the frontmost app, for as long as discrete mode is active.
///
/// Distinct from `PhysicalKeyMonitor`: CapsLock alone needs the raw-HID
/// path (see that file's doc comment) to see genuinely quick taps, but
/// ordinary keys don't have that debounce problem — and here we need a
/// BLOCKING tap (`.defaultTap`, not `.listenOnly`), since discrete mode is
/// meant to own the keyboard while its overlay is up, not just observe it.
/// `start()`/`stop()` are called exactly when discrete mode is entered and
/// exited, so normal typing is completely untouched the rest of the time.
final class DiscreteKeyboardCapture {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKeyDown: ((CapturedKeyDown) -> Void)?

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        )

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
        print("⌨️ Discrete keyboard capture OFF")
    }

    /// Returning nil swallows the event — it never reaches the focused app.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return nil }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        let characters = String(utf16CodeUnits: chars, count: length)

        let captured = CapturedKeyDown(keyCode: keyCode, characters: characters)
        DispatchQueue.main.async { [weak self] in
            self?.onKeyDown?(captured)
        }

        return nil
    }
}
