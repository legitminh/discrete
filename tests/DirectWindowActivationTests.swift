@main struct DirectWindowActivationTests {
    static var count = 0
    static func expect(_ value: DirectWindowActivationProgress.Observation, _ expected: DirectWindowActivationProgress.Observation, _ reason: String) {
        count += 1
        precondition(value == expected, reason)
    }
    static func main() {
        let jump = DirectWindowActivationProgress(origin: 1, target: 8)
        expect(jump.observe(space: 1, windowIsVisible: false, isCurrent: true, expired: false), .waiting, "Accepted focus isn't a visible window")
        expect(jump.observe(space: 8, windowIsVisible: false, isCurrent: true, expired: false), .waiting, "A pointer change alone isn't success")
        expect(jump.observe(space: 1, windowIsVisible: true, isCurrent: true, expired: false), .waiting, "Visibility on the wrong desktop isn't success")
        expect(jump.observe(space: 8, windowIsVisible: true, isCurrent: true, expired: false), .activated, "Correct window and target desktop complete a distant jump")
        expect(jump.observe(space: 1, windowIsVisible: false, isCurrent: true, expired: true), .unavailable, "An unchanged desktop can fall back to native navigation")
        expect(jump.observe(space: 8, windowIsVisible: false, isCurrent: true, expired: true), .interrupted, "Don't navigate over a partial native transition")
        expect(jump.observe(space: 8, windowIsVisible: true, isCurrent: true, expired: true), .activated, "An arrived window wins over the timeout boundary")
        expect(jump.observe(space: 3, windowIsVisible: false, isCurrent: true, expired: false), .interrupted, "User/fullscreen transition interrupts the direct request")
        expect(jump.observe(space: 3, windowIsVisible: true, isCurrent: true, expired: true), .interrupted, "Timeout must not force a user's desktop back")
        expect(jump.observe(space: 1, windowIsVisible: false, isCurrent: false, expired: false), .interrupted, "A superseded request must not fall back")
        expect(jump.observe(space: 8, windowIsVisible: true, isCurrent: false, expired: false), .interrupted, "An old success must not refocus after a new command")
        print("Direct window activation: \(count) checks passed")
    }
}
