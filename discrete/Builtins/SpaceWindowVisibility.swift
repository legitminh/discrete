import Foundation

/// A target window being visible doesn't prove a Space transition completed:
/// the old Space can still be composited behind it. Inspect every visible
/// document window belonging to the affected display's Spaces.
struct SpaceWindowVisibility {
    struct Window {
        let id: UInt32
        let spaces: Set<UInt64>
    }
    let windows: [Window]
    let displaySpaces: Set<UInt64>
    let otherVisibleSpaces: Set<UInt64>
    let target: UInt64

    func isReady(visibleIDs: Set<UInt32>) -> Bool {
        let allowed = otherVisibleSpaces.union([target])
        let relevant = windows.filter { !$0.spaces.isDisjoint(with: displaySpaces) }
        let wrongSpaceVisible = relevant.contains {
            visibleIDs.contains($0.id) && $0.spaces.isDisjoint(with: allowed)
        }
        // The destination may legitimately have only hidden/minimized windows.
        // NativeSpaceTransition separately verifies its active-Space identity;
        // focusing/restoring the selected app window happens after that switch.
        return !wrongSpaceVisible
    }
}
