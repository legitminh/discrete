import Foundation

/// Pure selection rules. Space order comes from Mission Control, never from
/// window z-order (which changes every time a window is activated).
enum ApplicationOpenPolicy {
    struct Window {
        let id: UInt32
        let spaces: [UInt64]
        let display: String?
        let isDisplayed: Bool
    }

    enum Action: Equatable {
        case launch
        case focus(UInt32)
        case bring(UInt32)
    }

    /// `windows` is in desktop order, with stable window IDs breaking ties.
    static func choose(windows: [Window], display: String, currentSpace: UInt64,
                       orderedSpaces: [UInt64], monitorCount: Int, focusedWindowID: UInt32? = nil) -> Action {
        guard let first = windows.first else { return .launch }
        let local = windows.filter { $0.display == display }
        let currentWindows = local.filter { $0.isDisplayed && $0.spaces.contains(currentSpace) }
        let current = currentWindows.first { $0.id == focusedWindowID } ?? currentWindows.first
        if let current {
            let focusedIndex = currentWindows.firstIndex { $0.id == focusedWindowID }
            // Visiting another window on this desktop only changes focus.
            // After its last window, advance to the next app desktop.
            if let focusedIndex, focusedIndex + 1 < currentWindows.count {
                return .focus(currentWindows[focusedIndex + 1].id)
            }
            let start = orderedSpaces.firstIndex(of: currentSpace) ?? 0
            let following = Array(orderedSpaces.dropFirst(start + 1)) + Array(orderedSpaces.prefix(start))
            for space in following {
                // An all-desktops window is already present; it isn't a new stop.
                if let next = local.first(where: { $0.spaces.contains(space) && !$0.spaces.contains(currentSpace) }) {
                    return .focus(next.id)
                }
            }
            if focusedIndex != nil, currentWindows.count > 1 {
                return .focus(currentWindows[0].id)
            }
            return .focus(current.id)
        }
        guard monitorCount > 1 else { return .focus(first.id) }
        return .bring((windows.first { !$0.isDisplayed } ?? first).id)
    }
}
