/// Focus acceptance alone isn't completion: the correct Space AND window must
/// be visible. A user/fullscreen Space change cancels fallback navigation too.
struct DirectWindowActivationProgress {
    enum Observation: Equatable { case waiting, activated, unavailable, interrupted }
    let origin: UInt64
    let target: UInt64

    func observe(space: UInt64, windowIsVisible: Bool, isCurrent: Bool, expired: Bool) -> Observation {
        guard isCurrent, space == origin || space == target else { return .interrupted }
        if space == target && windowIsVisible { return .activated }
        // A partial native transition is still owned by Dock; don't start a
        // second navigation sequence while its destination is appearing.
        if expired { return space == origin ? .unavailable : .interrupted }
        return .waiting
    }
}
