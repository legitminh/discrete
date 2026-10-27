import Foundation

@main struct NativeSpaceTransitionTests {
    static var checks = 0
    static func expect(_ actual: NativeSpaceTransition.Observation, _ expected: NativeSpaceTransition.Observation, _ reason: String) {
        checks += 1
        precondition(actual == expected, reason)
    }
    static func main() {
        var normal = NativeSpaceTransition(origin: 1, expected: 2)
        expect(normal.observe(space: 1, at: 0, isCurrent: true), .waiting, "Posting isn't completion")
        expect(normal.observe(space: 2, at: 0.1, isCurrent: true), .waiting, "First pointer arrival must not start another swipe")
        expect(normal.observe(space: 2, at: 0.4, isCurrent: true), .waiting, "Native transition needs a stable settle period")
        expect(normal.observe(space: 2, at: 0.5, isCurrent: true), .settled, "Stable native destination can complete")
        var bounced = NativeSpaceTransition(origin: 1, expected: 2)
        expect(bounced.observe(space: 2, at: 0, isCurrent: true), .waiting, "First arrival")
        expect(bounced.observe(space: 1, at: 0.2, isCurrent: true), .waiting, "Bounce resets settle period")
        expect(bounced.observe(space: 2, at: 0.4, isCurrent: true), .waiting, "Second arrival starts a fresh settle period")
        expect(bounced.observe(space: 2, at: 0.6, isCurrent: true), .waiting, "Old arrival time cannot complete the second transition")
        expect(bounced.observe(space: 2, at: 0.8, isCurrent: true), .settled, "Fresh settle period completes")
        var canceled = NativeSpaceTransition(origin: 1, expected: 2)
        expect(canceled.observe(space: 1, at: 0, isCurrent: false), .waiting, "Cancellation must let the already-posted gesture finish")
        expect(canceled.observe(space: 2, at: 0.1, isCurrent: false), .waiting, "Canceled gesture still needs to settle")
        expect(canceled.observe(space: 2, at: 0.5, isCurrent: false), .interrupted, "Canceled request must never post another hop")
        var fullscreen = NativeSpaceTransition(origin: 1, expected: 2)
        expect(fullscreen.observe(space: 3, at: 0.1, isCurrent: true), .interrupted, "User/fullscreen Space takes precedence before landing")
        var afterArrival = NativeSpaceTransition(origin: 1, expected: 2)
        expect(afterArrival.observe(space: 2, at: 0, isCurrent: true), .waiting, "Pending settle")
        expect(afterArrival.observe(space: 3, at: 0.1, isCurrent: true), .interrupted, "Fullscreen during settling must not be reversed")
        print("Native Space transition: \(checks) checks passed")
    }
}
