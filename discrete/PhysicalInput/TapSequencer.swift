import CoreGraphics
import Foundation

/// Turns per-key down/up transitions into trigger taps, per the spec's tap
/// rule: a key released within the tap duration is a tap and fires on
/// release; one held longer is a hold and never fires. Overlapping taps
/// fire in the order the keys went *down* — a key released early waits
/// until every key pressed before it has resolved — so a quick ⇧+a fires
/// ⇧ and then a. The multi-key generalization of `DiscreteSignalGenerator`.
final class TapSequencer {
    private enum Outcome {
        case tap
        case hold
    }

    private struct Press {
        let keyCode: CGKeyCode
        let downAt: TimeInterval
        var outcome: Outcome?
    }

    private let settings: UserSettings
    private var pending: [Press] = []

    var onTap: ((CGKeyCode) -> Void)?

    init(settings: UserSettings) {
        self.settings = settings
    }

    func keyDown(_ keyCode: CGKeyCode, at time: TimeInterval) {
        // Auto-repeat, or a down we already track.
        guard !pending.contains(where: { $0.keyCode == keyCode && $0.outcome == nil }) else { return }
        pending.append(Press(keyCode: keyCode, downAt: time))

        // A key still down past the threshold must resolve as a hold on its
        // own, or every tap pressed after it would wait for its release.
        let threshold = settings.clickHoldThreshold
        DispatchQueue.main.asyncAfter(deadline: .now() + threshold) { [weak self] in
            self?.flush(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func keyUp(_ keyCode: CGKeyCode, at time: TimeInterval) {
        guard let index = pending.firstIndex(where: { $0.keyCode == keyCode && $0.outcome == nil }) else { return }
        let held = time - pending[index].downAt
        pending[index].outcome = held < settings.clickHoldThreshold ? .tap : .hold
        flush(now: time)
    }

    func reset() {
        pending.removeAll()
    }

    private func flush(now: TimeInterval) {
        let threshold = settings.clickHoldThreshold
        for index in pending.indices where pending[index].outcome == nil && now - pending[index].downAt >= threshold {
            pending[index].outcome = .hold
        }
        while let first = pending.first, let outcome = first.outcome {
            pending.removeFirst()
            if outcome == .tap {
                onTap?(first.keyCode)
            }
        }
    }
}
