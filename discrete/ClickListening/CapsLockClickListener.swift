import Foundation

/// Listens for a "click" of the Caps Lock key — a tap, not a hold — by
/// wiring a `PhysicalKeyMonitor` for that key into a `DiscreteSignalGenerator`
/// and surfacing only the `.tap` signal as `onClick`. Callers never see
/// key codes. Press start/hold callbacks let the coordinator prepare or cancel
/// the short activation buffer before a click has been classified.
final class CapsLockClickListener {
    private let physicalInput: PhysicalKeyMonitor
    private let signalGenerator: DiscreteSignalGenerator

    var onClick: (() -> Void)?
    var onPressBegan: ((TimeInterval) -> Void)?
    var onHold: (() -> Void)?

    init(settings: UserSettings) {
        physicalInput = PhysicalKeyMonitor(usagePage: HIDUsage.keyboardOrKeypadPage, usage: HIDUsage.capsLock)
        signalGenerator = DiscreteSignalGenerator(settings: settings)

        physicalInput.onEvent = { [weak self] event in
            if event.phase == .down { self?.onPressBegan?(event.timestamp) }
            self?.signalGenerator.ingest(event)
        }
        signalGenerator.onSignal = { [weak self] signal in
            guard signal == .tap else { self?.onHold?(); return }
            print("🖱️ Caps Lock click detected — notifying listener")
            self?.onClick?()
        }
    }

    func start() {
        physicalInput.start()
    }

    func stop() {
        physicalInput.stop()
    }
}
