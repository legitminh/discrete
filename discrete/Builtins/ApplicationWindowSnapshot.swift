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
}
