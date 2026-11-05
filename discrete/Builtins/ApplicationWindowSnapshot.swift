import CoreGraphics
import Foundation

/// WindowServer's complete inventory and current on-screen membership are
/// separate queries. In particular, .optionAll may omit kCGWindowIsOnscreen.
struct ApplicationWindowSnapshot {
    let records: [[String: Any]]
    let onScreenIDs: Set<CGWindowID>

    init?(allWindows: [[String: Any]]?, onScreenWindows: [[String: Any]]?) {
        guard let allWindows, let onScreenWindows else { return nil }
        records = allWindows
        onScreenIDs = Set(onScreenWindows.compactMap {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
    }

    static func capture() -> ApplicationWindowSnapshot? {
        ApplicationWindowSnapshot(
            allWindows: CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
            onScreenWindows: CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        )
    }

    /// AX identifies ordinary document/dialog windows. For windows omitted
    /// from AX on inactive fullscreen Spaces, Dock identifies the actual
    /// fullscreen documents. Other layer-zero CG records can be retained
    /// panels (Mail's Junk Mail panel, for example), not windows to summon.
    func activationWindowIDs(pid: pid_t, accessibilityDocuments: Set<CGWindowID>,
                             fullscreenWindowIDs: Set<CGWindowID>) -> Set<CGWindowID> {
        let fullscreen = records.compactMap { record -> CGWindowID? in
            guard (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  fullscreenWindowIDs.contains(id) else { return nil }
            return id
        }
        return accessibilityDocuments.union(fullscreen)
    }
}
