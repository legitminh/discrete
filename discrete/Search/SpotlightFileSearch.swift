import Foundation

struct SpotlightFileMatch {
    let url: URL
    let lastOpened: Date?
    /// Content evidence survives broad name retrieval; the ranker decides
    /// whether the name itself qualifies as a match.
    let isContentMatch: Bool

    func merging(_ other: SpotlightFileMatch) -> SpotlightFileMatch {
        SpotlightFileMatch(url: url, lastOpened: [lastOpened, other.lastOpened].compactMap { $0 }.max(),
                           isContentMatch: isContentMatch || other.isContentMatch)
    }
}

/// Spotlight retrieves a superset of possible names, including typos and
/// synonyms. Only the final ranked list is limited, never arbitrary index order.
/// Content is a separate fallback so a matching PDF isn't discarded by name.
final class SpotlightFileSearch {
    private var queries: [NSMetadataQuery] = []
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var generation = 0

    func search(_ text: String, completion: @escaping ([SpotlightFileMatch]) -> Void) {
        stop()
        guard !SearchMatcher.words(of: text).isEmpty else { return }
        let request = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == request else { return }
            var matches: [String: SpotlightFileMatch] = [:]
            for content in [false, true] {
                let query = NSMetadataQuery()
                query.searchScopes = [FileManager.default.homeDirectoryForCurrentUser.path]
                query.predicate = content ? Self.contentPredicate(text) : Self.namePredicate(text)
                let observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
                ) { [weak self] notification in
                    MainActor.assumeIsolated {
                        guard let self, self.generation == request,
                              let finished = notification.object as? NSMetadataQuery else { return }
                        finished.disableUpdates()
                        for index in 0..<finished.resultCount {
                            guard let item = finished.result(at: index) as? NSMetadataItem,
                                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                                  Self.isUserFile(path) else { continue }
                            let match = SpotlightFileMatch(
                                url: URL(fileURLWithPath: path),
                                lastOpened: item.value(forAttribute: "kMDItemLastUsedDate") as? Date,
                                isContentMatch: content
                            )
                            matches[path] = matches[path].map { $0.merging(match) } ?? match
                        }
                        finished.stop()
                        completion(Array(matches.values))
                    }
                }
                self.observers.append(observer)
                self.queries.append(query)
                query.start()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func stop() {
        generation += 1
        pending?.cancel()
        pending = nil
        queries.forEach { $0.stop() }
        queries.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    static func namePredicate(_ text: String) -> NSPredicate {
        let terms = SearchMatcher.words(of: text).map { word -> NSPredicate in
            var patterns = ["*\(word)*"]
            // A subsequence pattern retrieves abbreviations AND insertion typos.
            patterns.append("*" + word.map(String.init).joined(separator: "*") + "*")
            let allowance = SearchMatcher.typoAllowance(for: word)
            if allowance > 0 {
                let characters = Array(word)
                if characters.count <= 24 {
                    // Dropping up to k letters yields a common subsequence for
                    // insertions, deletions, substitutions and transpositions.
                    for first in characters.indices {
                        let once = characters.enumerated().filter { $0.offset != first }.map { String($0.element) }
                        patterns.append("*" + once.joined(separator: "*") + "*")
                        if allowance == 2 {
                            for second in (first + 1)..<characters.count {
                                let twice = characters.enumerated().filter { $0.offset != first && $0.offset != second }.map { String($0.element) }
                                patterns.append("*" + twice.joined(separator: "*") + "*")
                            }
                        }
                    }
                } else {
                    // Long words use chunks: k transpositions affect at most
                    // 2k chunks, so one of 2k+1 chunks always survives.
                    let size = max(1, characters.count / (2 * allowance + 1))
                    for start in stride(from: 0, to: characters.count, by: size) {
                        patterns.append("*\(String(characters[start..<min(start + size, characters.count)]))*")
                    }
                }
            }
            patterns += SearchMatcher.relatedWords(to: word).map { "*\($0)*" }
            let alternatives = Array(Set(patterns)).sorted().map {
                NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, $0)
            }
            // NSMetadataQuery rejects singleton AND/OR predicates, even
            // though NSPredicate can evaluate them successfully in memory.
            return alternatives.count == 1 ? alternatives[0] : NSCompoundPredicate(orPredicateWithSubpredicates: alternatives)
        }
        return terms.count == 1 ? terms[0] : NSCompoundPredicate(andPredicateWithSubpredicates: terms)
    }

    static func contentPredicate(_ text: String) -> NSPredicate {
        let words = SearchMatcher.words(of: text).map {
            NSPredicate(format: "%K ==[cd] %@", "kMDItemTextContent", $0)
        }
        let types = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", "kMDItemContentTypeTree", "public.text"),
            NSPredicate(format: "%K == %@", "kMDItemContentTypeTree", "com.adobe.pdf")
        ])
        return NSCompoundPredicate(andPredicateWithSubpredicates: words + [types])
    }

    /// Include user cloud documents, even though their actual paths are in
    /// ~/Library. Continue excluding caches, hidden entries and app internals.
    static func isUserFile(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        if components.contains(where: { $0.lowercased().hasSuffix(".app") || $0.hasPrefix(".") }) { return false }
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path + "/"
        return !path.hasPrefix(library) || path.hasPrefix(library + "Mobile Documents/")
            || path.hasPrefix(library + "CloudStorage/")
    }
}
