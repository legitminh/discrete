import Foundation
import CoreGraphics

/// Run without launching apps or changing the user's desktops:
/// swiftc discrete/Builtins/ApplicationOpenPolicy.swift discrete/Builtins/ApplicationWindowSnapshot.swift tests/ApplicationOpenPolicyTests.swift -o /tmp/discrete-open-policy-tests
/// /tmp/discrete-open-policy-tests
@main
struct ApplicationOpenPolicyTests {
    typealias Window = ApplicationOpenPolicy.Window

    static func main() {
        // Desktop indices 0, 1, 5 have arbitrary WindowServer IDs, deliberately
        // not numerically sorted. Window IDs deliberately differ from z-order.
        let spaces: [UInt64] = [90, 40, 80, 30, 60, 10]
        func choose(_ windows: [Window], current: UInt64 = 40, monitors: Int = 1,
                    ordered: [UInt64] = spaces) -> ApplicationOpenPolicy.Action {
            ApplicationOpenPolicy.choose(windows: windows, display: "left", currentSpace: current,
                                         orderedSpaces: ordered, monitorCount: monitors)
        }
        func window(_ id: UInt32, _ space: UInt64, display: String = "left", shown: Bool = false) -> Window {
            Window(id: id, spaces: [space], display: display, isDisplayed: shown)
        }
        let projects = [window(300, 90), window(100, 40, shown: true), window(200, 10)]
        assert(choose(projects) == .focus(200), "Desktop 1 must advance to desktop 5")
        let afterFirstOpen = [window(300, 90), window(100, 40), window(200, 10, shown: true)]
        assert(choose(afterFirstOpen, current: 10) == .focus(300), "Desktop 5 must wrap to desktop 0")
        assert(choose([window(100, 40, shown: true)]) == .focus(100), "One local window stays put")
        assert(choose([window(100, 40, shown: true), window(101, 40, shown: true)]) == .focus(100),
               "Two windows on one Space must not create an extra desktop stop")
        let pinned = Window(id: 500, spaces: spaces, display: "left", isDisplayed: true)
        assert(choose([pinned, window(200, 10)]) == .focus(200), "An all-desktops window must not block cycling")
        assert(choose([pinned]) == .focus(500), "All-desktops window must not create artificial stops")
        assert(choose([window(300, 90)], current: 40) == .focus(300), "One monitor activates an existing Space")
        assert(choose([window(300, 90, display: "right", shown: true), window(200, 10)], monitors: 2) == .bring(200),
               "Prefer a hidden-Space window over one displayed on another monitor")
        assert(choose([window(300, 90, display: "right", shown: true), window(200, 10, display: "right", shown: true)],
                      monitors: 2) == .bring(300), "If all windows are displayed, bring the first")
        assert(choose([window(300, 90, display: "right", shown: true), window(100, 40)], monitors: 2) == .bring(100),
               "A minimized or hidden current-Space window should be restored locally")
        assert(choose([window(100, 40, shown: true), window(200, 10, display: "right")], monitors: 2) == .focus(100),
               "Cycling a local desktop must leave the other monitor's desktops alone")
        assert(choose([], monitors: 2) == .launch, "No app windows should launch/reopen the app")
        assert(choose([window(100, 40, shown: true), window(200, 10)], ordered: [40, 10]) == .focus(200),
               "Native fullscreen Spaces participate in the supplied desktop order")
        // Regression: the actual .optionAll response on macOS 27 has no
        // kCGWindowIsOnscreen key, even for the current Chrome window.
        let records: [[String: Any]] = [
            [kCGWindowNumber as String: NSNumber(value: 100)],
            [kCGWindowNumber as String: NSNumber(value: 200)]
        ]
        let snapshot = ApplicationWindowSnapshot(allWindows: records, onScreenWindows: [records[0]])!
        assert(snapshot.onScreenIDs.contains(100), "Missing all-windows visibility flags must not hide a displayed window")
        assert(!snapshot.onScreenIDs.contains(200), "An inactive-Space window must stay undisplayed")
        assert(ApplicationWindowSnapshot(allWindows: records, onScreenWindows: nil) == nil,
               "Failed metadata queries must fall back, not report every app window as hidden")
        let sharedDesktop = [window(100, 40, shown: true), window(200, 40, shown: true)]
        assert(ApplicationOpenPolicy.choose(windows: sharedDesktop, display: "left", currentSpace: 40,
                                            orderedSpaces: spaces, monitorCount: 1, focusedWindowID: 100) == .focus(200),
               "Without another app desktop, opening should switch focus to the next window on this desktop")
        assert(ApplicationOpenPolicy.choose(windows: sharedDesktop, display: "left", currentSpace: 40,
                                            orderedSpaces: spaces, monitorCount: 1, focusedWindowID: 200) == .focus(100),
               "Window focus on the same desktop must wrap back to the first")
        let mixedDesktops = sharedDesktop + [window(300, 10)]
        assert(ApplicationOpenPolicy.choose(windows: mixedDesktops, display: "left", currentSpace: 40,
                                            orderedSpaces: spaces, monitorCount: 1, focusedWindowID: 100) == .focus(200),
               "Sharing a Space changes window focus even when another app desktop exists")
        assert(ApplicationOpenPolicy.choose(windows: mixedDesktops, display: "left", currentSpace: 40,
                                            orderedSpaces: spaces, monitorCount: 1, focusedWindowID: 200) == .focus(300),
               "After the final window on this Space, advance to the next app Space")
        print("Application opening policy and window metadata: 20 scenarios passed")
    }
}
