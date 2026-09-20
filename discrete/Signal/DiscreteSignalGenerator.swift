import Foundation

/// Consumes a stream of raw `PhysicalKeyEvent`s for a single key and emits a
/// `DiscreteSignal` each time a down/up pair completes: a short press reads
/// as `.tap`, a press held past `settings.clickHoldThreshold` reads as
/// `.hold`. Reads the threshold fresh on every press so a live settings
/// change takes effect immediately.
final class DiscreteSignalGenerator {
    private let settings: UserSettings
    private var pressStartedAt: TimeInterval?

    var onSignal: ((DiscreteSignal) -> Void)?

    init(settings: UserSettings) {
        self.settings = settings
    }

    func ingest(_ event: PhysicalKeyEvent) {
        switch event.phase {
        case .down:
            pressStartedAt = event.timestamp

        case .up:
            guard let pressStartedAt else { return }
            self.pressStartedAt = nil

            let duration = event.timestamp - pressStartedAt
            let signal: DiscreteSignal = duration < settings.clickHoldThreshold ? .tap : .hold
            let description = signal == .tap ? "click" : "hold (activating Caps Lock)"
            print("👆 Finger lifted after \(String(format: "%.3f", duration))s — \(description)")

            onSignal?(signal)
        }
    }
}
