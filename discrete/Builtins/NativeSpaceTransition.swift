import Foundation

/// A native swipe must settle before another is posted. A user/fullscreen
/// transition to a third Space interrupts the request instead of being undone.
struct NativeSpaceTransition {
    enum Observation: Equatable { case waiting, settled, interrupted }
    let origin: UInt64
    let expected: UInt64
    private var landedAt: TimeInterval?

    init(origin: UInt64, expected: UInt64) {
        self.origin = origin
        self.expected = expected
    }

    mutating func observe(space: UInt64, at time: TimeInterval, isCurrent: Bool) -> Observation {
        guard space == origin || space == expected else { return .interrupted }
        guard space == expected else { landedAt = nil; return .waiting }
        let firstArrival = landedAt ?? time
        landedAt = firstArrival
        guard time - firstArrival >= 0.35 else { return .waiting }
        return isCurrent ? .settled : .interrupted
    }
}
