import Foundation

/// Shared by background Spotlight reduction and final mixed-result ranking.
nonisolated enum SearchFilePolicy {
    private static let dependencies: Set<String> = ["node_modules", "site-packages", "dist-packages", "__pycache__", "venv", ".venv", "deriveddata", "pods", "carthage", "packagecache", "build", "dist", "target", "cache", "caches"]
    private static let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    static func isUserFile(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        if components.contains(where: { component in
            let lower = component.lowercased()
            return component.hasPrefix(".") || lower.hasSuffix(".app") || dependencies.contains(lower)
        }) { return false }
        let library = homePath + "/Library/"
        return !path.hasPrefix(library) || path.hasPrefix(library + "Mobile Documents/") || path.hasPrefix(library + "CloudStorage/")
    }

    static func relativePath(_ url: URL) -> String {
        let home = homePath
        let path = url.standardizedFileURL.path
        for prefix in [home + "/Library/Mobile Documents/com~apple~CloudDocs/", home + "/Library/CloudStorage/", home + "/"] {
            if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        }
        return path
    }

    static func depth(_ url: URL) -> Int {
        max(0, (relativePath(url) as NSString).pathComponents.count - 1)
    }

    static func locationBonus(_ url: URL) -> Double {
        let components = (relativePath(url) as NSString).pathComponents
        let archived = components.dropLast().contains {
            SearchMatcher.words(of: $0).contains { ["archive", "archives", "archived", "backup", "backups"].contains($0) }
        }
        let rootFolder = components.count == 1 ? 15.0 : 0.0
        return rootFolder - Double(min(depth(url), 16)) - (archived ? 35 : 0)
    }

    static func recentBonus(_ date: Date?, now: Date, window: TimeInterval) -> Double {
        guard let date, date <= now, now.timeIntervalSince(date) <= window else { return 0 }
        // Recency helps comparable results; it cannot turn a weak match into
        // a better name or bury Documents under an archived copy.
        return 4 + 4 * (1 - now.timeIntervalSince(date) / window)
    }

    static func tier(_ score: Double) -> Int {
        score >= 70 ? 0 : (score >= 45 ? 1 : (score > 0 ? 2 : 3))
    }
}
