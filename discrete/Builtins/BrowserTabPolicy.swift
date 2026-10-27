import Foundation

/// Browser-independent tab matching and stable cycling. Browser window IDs are
/// session IDs, not WindowServer IDs; never pass them to ApplicationSpaces.
enum BrowserTabPolicy {
    struct Tab: Codable, Equatable {
        let index: Int // one-based, left to right
        let url: String
        let title: String
    }

    struct Window: Codable {
        let id: String
        let index: Int // front to back
        let activeTab: Int
        let bounds: [Double] // x, y, width, height in WindowServer coordinates
        let tabs: [Tab]
    }

    struct Selection: Equatable {
        let windowID: String
        let tabIndex: Int
    }

    /// Add a missing scheme, as for new tabs, and normalize scheme/host case.
    /// Path, query and fragment remain case-sensitive. This is a literal prefix,
    /// so callers can include a trailing slash when a host boundary matters.
    static func normalized(_ address: String) -> String? {
        guard let url = WebsiteOpener.url(from: address),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string
    }

    static func choose(windows: [Window], prefix: String, browserIsFrontmost: Bool) -> Selection? {
        guard let prefix = normalized(prefix) else { return nil }
        // Bringing a window forward changes its index. Use session IDs for a
        // stable cycle across windows, then the tab strip's left-to-right order.
        let ordered = windows.sorted {
            if let left = UInt64($0.id), let right = UInt64($1.id) { return left < right }
            return $0.id < $1.id
        }
        let matches = ordered.flatMap { window in
            window.tabs.sorted { $0.index < $1.index }.compactMap { tab -> Selection? in
                guard let url = normalized(tab.url), url.hasPrefix(prefix) else { return nil }
                return Selection(windowID: window.id, tabIndex: tab.index)
            }
        }
        guard !matches.isEmpty else { return nil }
        if browserIsFrontmost, let front = windows.min(by: { $0.index < $1.index }),
           let current = matches.firstIndex(of: Selection(windowID: front.id, tabIndex: front.activeTab)) {
            return matches[(current + 1) % matches.count]
        }
        return matches[0]
    }
}
