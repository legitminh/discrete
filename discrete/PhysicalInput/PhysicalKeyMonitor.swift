import CoreGraphics
import Foundation
import IOKit.hid

/// Watches the raw HID input-report stream for down/up transitions of a
/// single key (identified by USB HID usage page/usage) and reports them as
/// `PhysicalKeyEvent`s.
///
/// This deliberately uses `IOHIDManager` rather than `CGEventTap`: macOS
/// debounces the Caps Lock key above the raw HID layer, to stop an
/// accidental bump from toggling it — a hold survives that filter and
/// reaches a `CGEventTap`, but a genuine quick tap is swallowed before any
/// `CGEvent` is ever generated, so it's invisible no matter what event
/// types a `CGEventTap` listens for. Reading raw HID input reports observes
/// every physical press/release below that debounce, so both register.
final class PhysicalKeyMonitor {
    private let usagePage: Int
    private let usage: Int
    private var manager: IOHIDManager?

    var onEvent: ((PhysicalKeyEvent) -> Void)?

    init(usagePage: Int, usage: Int) {
        self.usagePage = usagePage
        self.usage = usage
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<PhysicalKeyMonitor>.fromOpaque(context).takeUnretainedValue().handle(value)
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)

        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if status == kIOReturnSuccess {
            print("✅ Physical key monitor listening for HID usage page \(usagePage) usage \(usage)")
        } else {
            print("❌ Failed to open HID manager (status \(status)) — check System Settings > Privacy & Security > Input Monitoring")
        }
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        self.manager = nil
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == usagePage,
              IOHIDElementGetUsage(element) == usage else { return }

        let phase: PhysicalKeyEvent.Phase = IOHIDValueGetIntegerValue(value) != 0 ? .down : .up
        let timestamp = ProcessInfo.processInfo.systemUptime
        let physicalEvent = PhysicalKeyEvent(keyCode: CGKeyCode(usage), phase: phase, timestamp: timestamp)

        print("⌨️ Physical \(phase) — HID usage \(usage) at \(timestamp)")

        // The callback fires on whatever run loop the manager was scheduled
        // against (main, in this app). Hop through main explicitly anyway so
        // callers never have to reason about which thread delivers events.
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(physicalEvent)
        }
    }
}
