import Foundation

/// Consumes a stream of raw `PhysicalKeyEvent`s for a single key and emits a
/// `DiscreteSignal` each time a down/up pair completes: a short press reads
/// as `.tap`, a press held past `holdThreshold` reads as `.hold`.
final class DiscreteSignalGenerator {
    private let holdThreshold: TimeInterval
    private var pressStartedAt: TimeInterval?

    var onSignal: ((DiscreteSignal) -> Void)?

    init(holdThreshold: TimeInterval = 0.35) {
        self.holdThreshold = holdThreshold
    }

    func ingest(_ event: PhysicalKeyEvent) {
        switch event.phase {
        case .down:
            pressStartedAt = event.timestamp

        case .up:
            guard let pressStartedAt else { return }
            self.pressStartedAt = nil

            let duration = event.timestamp - pressStartedAt
            let signal: DiscreteSignal = duration < holdThreshold ? .tap : .hold
            let description = signal == .tap ? "click" : "hold (activating Caps Lock)"
            print("👆 Finger lifted after \(String(format: "%.3f", duration))s — \(description)")

            onSignal?(signal)
        }
    }
}
