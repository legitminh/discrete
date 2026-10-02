import Foundation

/// Finds files and folders in the user's home folder whose name contains
/// the query, via the system's Spotlight index. Results arrive
/// asynchronously; starting a new search (or `stop()`) abandons the
/// previous one, so a late answer for an old query is never delivered.
final class SpotlightFileSearch {
    /// Spotlight returns matches unranked; this many are handed back to be ranked.
    private static let resultLimit = 200

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?

    func search(_ text: String, completion: @escaping ([URL]) -> Void) {
        stop()
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(Self.escapedForLike(text))*")
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.query === query else { return }
                let urls = Self.urls(from: query)
                self.stop()
                completion(urls)
            }
        }
        self.query = query
        query.start()
    }

    func stop() {
        query?.stop()
        query = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    private static func urls(from query: NSMetadataQuery) -> [URL] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var urls: [URL] = []
        for index in 0..<query.resultCount where urls.count < resultLimit {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  isUserFile(path) else { continue }
            urls.append(URL(fileURLWithPath: path))
        }
        return urls
    }

    /// Leaves out apps (offered on their own) and anything inside them,
    /// hidden files, and ~/Library's internals.
    private static func isUserFile(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        if components.contains(where: { $0.hasSuffix(".app") || $0.hasPrefix(".") }) { return false }
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path + "/"
        return !path.hasPrefix(library)
    }

    /// `*`, `?` and `\` are special in a LIKE pattern.
    private static func escapedForLike(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "*?\\".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
