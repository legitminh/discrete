import Foundation

/// The installed apps state.search offers: every .app in the standard
/// application folders and their direct sub-folders (e.g. Utilities).
enum AppCatalog {
    private static var folders: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
    }

    static func apps() -> [URL] {
        var apps: [URL] = []
        for folder in folders {
            for entry in contents(of: folder) {
                if entry.pathExtension == "app" {
                    apps.append(entry)
                } else if isDirectory(entry) {
                    apps += contents(of: entry).filter { $0.pathExtension == "app" }
                }
            }
        }
        return apps
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
