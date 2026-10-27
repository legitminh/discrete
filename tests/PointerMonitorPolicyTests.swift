import CoreGraphics

/// No cursor movement or GUI session needed:
/// swiftc discrete/Builtins/PointerMonitorPolicy.swift tests/PointerMonitorPolicyTests.swift -o /tmp/discrete-pointer-tests
@main struct PointerMonitorPolicyTests {
    static var checks = 0

    static func expect(_ actual: CGPoint?, _ expected: CGPoint?, _ message: String) {
        checks += 1
        precondition(actual == expected, message)
    }

    static func main() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let displays = [left, right]
        let pointer = CGPoint(x: 1800, y: 300)
        let leftWindow = CGRect(x: -1800, y: 100, width: 1200, height: 800)
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: leftWindow, displays: displays),
               CGPoint(x: -960, y: 540), "Right-to-left summoning centers the pointer on the left monitor")
        expect(PointerMonitorPolicy.destination(pointer: CGPoint(x: -1700, y: 200), window: right, displays: displays),
               CGPoint(x: 1280, y: 720), "Left-to-right summoning uses the target monitor's actual size")
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: right, displays: displays), nil,
               "Same-monitor summoning leaves the pointer at its original position")
        expect(PointerMonitorPolicy.destination(pointer: CGPoint(x: -1900, y: 1000), window: leftWindow, displays: displays), nil,
               "The pointer need not be inside the target window to stay put on its monitor")
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: left, displays: displays),
               CGPoint(x: -960, y: 540), "A fullscreen target uses the monitor center without changing its geometry")
        let above = CGRect(x: 200, y: -1200, width: 1920, height: 1200)
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: above, displays: [above, right]),
               CGPoint(x: 1160, y: -600), "A monitor above the primary screen keeps WindowServer's negative y coordinates")
        let below = CGRect(x: -300, y: 1440, width: 1600, height: 900)
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: below, displays: [right, below]),
               CGPoint(x: 500, y: 1890), "A vertically offset monitor below the primary screen is centered correctly")
        let spanning = CGRect(x: -800, y: 100, width: 1000, height: 800)
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: spanning, displays: displays),
               CGPoint(x: -960, y: 540), "A spanning window belongs to the display with the largest overlap")
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: right, displays: [right]), nil,
               "Single-monitor activation never moves the pointer")
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: CGRect(x: 9000, y: 0, width: 800, height: 600),
                                               displays: displays), nil, "An offscreen target must not choose an arbitrary monitor")
        expect(PointerMonitorPolicy.destination(pointer: CGPoint(x: 9000, y: 9000), window: left, displays: displays), nil,
               "An unknown pointer monitor must not cause a jump")
        expect(PointerMonitorPolicy.destination(pointer: pointer, window: .zero, displays: displays), nil,
               "Missing target geometry must not cause a jump")
        print("Pointer monitor policy: \(checks) checks passed")
    }
}
