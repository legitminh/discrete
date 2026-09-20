/// Listens for a "click" of the Caps Lock key — a tap, not a hold — by
/// wiring a `PhysicalKeyMonitor` for that key into a `DiscreteSignalGenerator`
/// and surfacing only the `.tap` signal as `onClick`. Callers never see
/// physical events or key codes, just "it was clicked."
final class CapsLockClickListener {
    private let physicalInput: PhysicalKeyMonitor
    private let signalGenerator: DiscreteSignalGenerator

    var onClick: (() -> Void)?

    init() {
        physicalInput = PhysicalKeyMonitor(usagePage: HIDUsage.keyboardOrKeypadPage, usage: HIDUsage.capsLock)
        signalGenerator = DiscreteSignalGenerator()

        physicalInput.onEvent = { [signalGenerator] event in
            signalGenerator.ingest(event)
        }
        signalGenerator.onSignal = { [weak self] signal in
            guard signal == .tap else { return }
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
