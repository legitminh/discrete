import AppKit

/// Build with the PhysicalInput files named in tests/activation-input-manual.txt.
/// The transport checks require a GUI session and Accessibility permission.
/// Events are fed directly to the handler; deferred hold events are collected
/// by an injected sink, never posted to another application.
@main
struct ActivationInputTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func key(_ code: CGKeyCode, down: Bool = true, repeated: Bool = false,
                    text: String = "", flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
        let characters = Array(text.utf16)
        if !characters.isEmpty { event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters) }
        return event
    }

    static func send(_ capture: DiscreteKeyboardCapture, _ code: CGKeyCode, down: Bool = true,
                     repeated: Bool = false, text: String = "", flags: CGEventFlags = []) -> Bool {
        capture.handle(type: down ? .keyDown : .keyUp,
                       event: key(code, down: down, repeated: repeated, text: text, flags: flags)) == nil
    }

    static func main() {
        // Pure queue regressions do not require an event tap or permission.
        var buffer = CapsLockActivationBuffer<String>()
        expect(!buffer.keyDown(11, input: "b"), "Inactive input must not be retained")
        buffer.begin(at: 1)
        buffer.keyDown(11, input: "b")
        buffer.keyDown(0, input: "a")
        buffer.keyUp(0)
        buffer.keyUp(11)
        expect(buffer.finish().inputs == ["b", "a"], "Replay must follow down order, not release order")
        buffer.begin(at: 2)
        buffer.keyDown(11, input: "b")
        expect(!buffer.keyDown(11, input: "repeat"), "Repeated down must not create another input")
        let held = buffer.finish()
        expect(held.inputs == ["b"] && held.heldKeys == [11], "Held input must replay once and drain its release")
        buffer.begin(at: 3)
        buffer.keyDown(11, input: "b1")
        buffer.keyUp(11)
        buffer.keyDown(11, input: "b2")
        expect(buffer.finish().inputs == ["b1", "b2"], "Two physical presses of one key must both replay")
        buffer.begin(at: 4)
        buffer.keyDown(11, input: "old")
        buffer.cancel()
        buffer.begin(at: 5)
        expect(buffer.finish().inputs.isEmpty, "A cancelled CapsLock hold must not leak into the next activation")
        print("Activation queue: 6 checks passed")

        guard AXIsProcessTrusted(), !NSScreen.screens.isEmpty else {
            print("Transport tests require a GUI session and Accessibility permission")
            exit(2)
        }

        func capture() -> DiscreteKeyboardCapture {
            let settings = UserSettings()
            settings.clickHoldThreshold = 10 // Keep synchronous tests independent of machine speed.
            return DiscreteKeyboardCapture(settings: settings, postDeferredEvent: { _ in
                fatalError("Tap input must not be forwarded to the foreground app")
            })
        }

        do {
            let input = capture()
            expect(!send(input, 11), "Ordinary inactive key-down must pass through")
            expect(!send(input, 11, down: false), "Ordinary inactive key-up must pass through")
        }
        do {
            let input = capture()
            var taps: [CGKeyCode] = []
            input.onTap = { taps.append($0) }
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            expect(send(input, 11), "Early key-down must be deferred")
            expect(send(input, 11, down: false), "Early key-up must be deferred")
            input.start()
            input.replayActivation()
            expect(taps == [11], "A key released before CapsLock must still run exactly once")
            input.stop()
        }
        do {
            let input = capture()
            var taps: [CGKeyCode] = []
            input.onTap = { taps.append($0) }
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            _ = send(input, 11)
            _ = send(input, 0)
            _ = send(input, 0, down: false)
            _ = send(input, 11, down: false)
            input.start()
            input.replayActivation()
            expect(taps == [11, 0], "Overlapping activation keys must run oldest first")
            input.stop()
        }
        do {
            let input = capture()
            var taps: [CGKeyCode] = []
            input.onTap = { taps.append($0) }
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            _ = send(input, 11)
            _ = send(input, 11, repeated: true)
            input.start()
            input.replayActivation()
            input.stop()
            expect(send(input, 11, repeated: true), "A replayed held key must not auto-repeat into another app")
            expect(send(input, 11, down: false), "Its eventual release must be drained even after the action exits")
            expect(taps == [11], "Repeats and a later release must not duplicate a replayed trigger")
            expect(!send(input, 11), "A fresh key-down after release must work normally")
        }
        do {
            let input = capture()
            var taps: [CGKeyCode] = []
            input.onTap = { taps.append($0) }
            _ = send(input, 11)
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            expect(!send(input, 11, repeated: true), "A key held before CapsLock must stay outside the buffer")
            expect(!send(input, 11, down: false), "Its release must pass through")
            input.start()
            input.replayActivation()
            expect(taps.isEmpty, "A pre-existing held key must not activate a command")
            input.stop()
        }
        do {
            let input = capture()
            var outputs: [String] = []
            input.onTap = { code in outputs.append("tap:\(code)"); input.mode = .typing }
            input.onTyped = { typed in
                expect(typed.flags.contains(.maskShift), "Buffered typing must retain its modifier flags")
                outputs.append(typed.characters)
            }
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            _ = send(input, 11)
            let shift = key(KeyCode.leftShift, flags: CGEventFlags(rawValue: 0x0000_0002))
            expect(input.handle(type: .flagsChanged, event: shift) == nil, "Modifier down must buffer")
            _ = send(input, 0, text: "A", flags: .maskShift)
            input.start()
            input.replayActivation()
            expect(outputs == ["tap:11", "A"], "Replay must use each input's resulting mode and not type modifier keys")
            input.stop()
            input.onTap = nil
        }
        do {
            let input = capture()
            var taps: [CGKeyCode] = []
            input.onTap = { code in taps.append(code); input.stop() }
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            _ = send(input, 11)
            _ = send(input, 0)
            input.start()
            input.replayActivation()
            expect(taps == [11], "Replay must stop when a command exits or opens a file picker")
            expect(send(input, 0, down: false), "Unused buffered keys must not leak their release after exit")
            input.onTap = nil
        }
        do {
            let settings = UserSettings()
            var forwarded: [CGEvent] = []
            let input = DiscreteKeyboardCapture(settings: settings, postDeferredEvent: { forwarded.append($0) })
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            _ = send(input, 11, text: "b")
            _ = send(input, 11, down: false)
            input.cancelActivation()
            expect(forwarded.map(\.type) == [.keyDown, .keyUp], "Hold cancellation must forward original events in order")
            expect(input.handle(type: .keyDown, event: forwarded[0]) != nil, "Reposted hold input must bypass buffering")
            expect(!send(input, 0), "Normal typing must resume after a CapsLock hold")
        }
        do {
            let settings = UserSettings()
            var forwarded: [CGEvent] = []
            let input = DiscreteKeyboardCapture(settings: settings, postDeferredEvent: { forwarded.append($0) })
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime - 1)
            _ = send(input, 11)
            expect(forwarded.count == 1, "A hold must expire even if its timer hasn't run yet")
            expect(!send(input, 11, down: false), "Held CapsLock must not retain subsequent key-up events")
        }
        do {
            let input = capture()
            var taps: [CGKeyCode] = []
            input.onTap = { taps.append($0) }
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            let caps = key(KeyCode.capsLock, flags: .maskAlphaShift)
            expect(input.handle(type: .flagsChanged, event: caps) != nil, "The independent CapsLock HID path must remain intact")
            _ = send(input, 160) // Mission Control top-row event maps to F3.
            input.start()
            input.replayActivation()
            expect(taps == [KeyCode.fKeys[2]], "Buffered top-row keys must use the usual F-key normalization")
            input.stop()
        }
        do {
            let input = capture()
            var typed: [TypedKey] = []
            input.onTap = { _ in input.mode = .typing }
            input.onTyped = { typed.append($0) }
            input.beginActivation(at: ProcessInfo.processInfo.systemUptime)
            _ = send(input, 11)
            let command = key(KeyCode.leftCommand, flags: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x8))
            expect(input.handle(type: .flagsChanged, event: command) == nil, "Buffered Command must be consumed")
            _ = send(input, KeyCode.c, text: "c", flags: .maskCommand)
            input.start()
            input.replayActivation()
            expect(typed.map(\.keyCode) == [KeyCode.leftCommand, KeyCode.c], "Activation replay delivers Command before its clipboard action")
            expect(typed[1].flags.contains(.maskCommand), "The clipboard shortcut keeps its modifier")
            input.stop()
            input.onTap = nil
        }
        print("Activation keyboard transport: 11 scenarios passed")
    }
}
