import Foundation

nonisolated struct SpotlightFileMatch: Sendable {
    let url: URL
    let lastOpened: Date?
    let isContentMatch: Bool
    var nameScore: Double? = nil

    func merging(_ other: SpotlightFileMatch) -> SpotlightFileMatch {
        SpotlightFileMatch(url: url, lastOpened: [lastOpened, other.lastOpened].compactMap { $0 }.max(),
                           isContentMatch: isContentMatch || other.isContentMatch,
                           nameScore: [nameScore, other.nameScore].compactMap { $0 }.max())
    }
}

/// The main thread only schedules work and receives a small ranked snapshot.
/// Spotlight and result enumeration run on a dedicated serial operation queue.
final class SpotlightFileSearch {
    private let worker = Worker()
    private var pending: DispatchWorkItem?
    private var cancellation: Cancellation?
    private var generation = 0
    private(set) var isSearching = false

    func search(_ text: String, limit: Int = 8, hasNameMatches: Bool = false,
                completion: @escaping ([SpotlightFileMatch]) -> Void) {
        stop()
        guard !SearchMatcher.words(of: text).isEmpty else { return }
        isSearching = true
        let request = generation
        let cancellation = Cancellation()
        self.cancellation = cancellation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == request else { return }
            self.worker.search(text, request: request, cancellation: cancellation, limit: limit, hasNameMatches: hasNameMatches,
                               recencyWindow: UserSettings.searchRecencyWindow) { [weak self] matches, final in
                DispatchQueue.main.async {
                    guard let self, self.generation == request else { return }
                    self.isSearching = !final
                    completion(matches)
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
    }

    func stop() {
        generation += 1
        isSearching = false
        cancellation?.cancel()
        cancellation = nil
        pending?.cancel()
        pending = nil
        worker.cancel()
    }

    nonisolated static func namePredicate(_ text: String) -> NSPredicate {
        compound(SearchMatcher.words(of: text).map {
            NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\($0)*")
        }, and: true)
    }

    nonisolated static func fallbackPredicate(_ text: String, fuzzy: Bool) -> NSPredicate {
        compound(SearchMatcher.words(of: text).map { word in
            var patterns = ["*\(word)*"] + SearchMatcher.relatedWords(to: word).map { "*\($0)*" }
            if fuzzy, (2...4).contains(word.count) {
                patterns.append("*" + word.map(String.init).joined(separator: "*") + "*")
            }
            if fuzzy, word.count >= 4 {
                let letters = Array(word)
                if letters.count <= 5 {
                    for index in letters.indices {
                        patterns.append("*" + letters.enumerated().filter { $0.offset != index }.map { String($0.element) }.joined(separator: "*") + "*")
                    }
                } else {
                    // A few contiguous anchors, only in the deferred fallback.
                    // Never construct dozens of interleaved wildcard patterns.
                    let size = max(2, letters.count / 3)
                    for start in stride(from: 0, through: letters.count - size, by: size) {
                        patterns.append("*\(String(letters[start..<start + size]))*")
                    }
                }
            }
            return compound(Array(Set(patterns)).map { NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, $0) }, and: false)
        }, and: true)
    }

    nonisolated static func contentPredicate(_ text: String) -> NSPredicate {
        let words = SearchMatcher.words(of: text).map { NSPredicate(format: "%K ==[cd] %@", "kMDItemTextContent", $0) }
        let types = compound([
            NSPredicate(format: "%K == %@", "kMDItemContentTypeTree", "public.text"),
            NSPredicate(format: "%K == %@", "kMDItemContentTypeTree", "com.adobe.pdf")
        ], and: false)
        return compound(words + [types], and: true)
    }

    nonisolated private static func compound(_ predicates: [NSPredicate], and: Bool) -> NSPredicate {
        if predicates.count == 1 { return predicates[0] }
        return and ? NSCompoundPredicate(andPredicateWithSubpredicates: predicates) : NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    nonisolated static func isUserFile(_ path: String) -> Bool { SearchFilePolicy.isUserFile(path) }

    /// Contents are a fallback for a failed name search, never filler for
    /// unused rows. Exhaust name scopes before beginning a content query.
    nonisolated enum Phase {
        case names, relaxedPersonal, relaxedHome, contentPersonal, contentHome

        var isContent: Bool { self == .contentPersonal || self == .contentHome }

        func next(hasNames: Bool, hasContent: Bool, hasPersonalScope: Bool, allowsFallback: Bool = true) -> Phase? {
            guard !hasNames, allowsFallback else { return nil }
            switch self {
            case .names: return hasPersonalScope ? .relaxedPersonal : .relaxedHome
            case .relaxedPersonal: return .relaxedHome
            case .relaxedHome: return hasPersonalScope ? .contentPersonal : .contentHome
            case .contentPersonal: return hasContent ? nil : .contentHome
            case .contentHome: return nil
            }
        }
    }

    nonisolated private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    nonisolated private final class Worker: @unchecked Sendable {
        private let queue: OperationQueue = {
            let queue = OperationQueue()
            queue.name = "discrete.spotlight"
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .userInitiated
            return queue
        }()
        // All mutable fields below are confined to queue.
        private var activeRequest: Int?
        private var query: NSMetadataQuery?
        private var observer: NSObjectProtocol?

        func cancel() {
            queue.addOperation { [self] in
                activeRequest = nil
                stopQuery()
            }
        }

        func search(_ text: String, request: Int, cancellation: Cancellation, limit: Int, hasNameMatches: Bool, recencyWindow: TimeInterval,
                    completion: @escaping @Sendable ([SpotlightFileMatch], Bool) -> Void) {
            queue.addOperation { [self] in
                guard !cancellation.isCancelled else { return }
                stopQuery()
                activeRequest = request
                let prepared = SearchMatcher.Query(text)
                let home = FileManager.default.homeDirectoryForCurrentUser
                let personal = ["Documents", "Desktop", "Downloads", "Library/Mobile Documents/com~apple~CloudDocs", "Library/CloudStorage"]
                    .map { home.appendingPathComponent($0).path }.filter { FileManager.default.fileExists(atPath: $0) }
                let fallbackScopes = personal.isEmpty ? [home.path] : personal
                var matches: [String: SpotlightFileMatch] = [:]

                func run(_ phase: Phase) {
                    guard activeRequest == request, !cancellation.isCancelled else { return }
                    let predicate: NSPredicate
                    switch phase {
                    case .names: predicate = SpotlightFileSearch.namePredicate(text)
                    case .relaxedPersonal, .relaxedHome: predicate = SpotlightFileSearch.fallbackPredicate(text, fuzzy: true)
                    case .contentPersonal, .contentHome: predicate = SpotlightFileSearch.contentPredicate(text)
                    }
                    let scopes = phase == .relaxedPersonal || phase == .contentPersonal ? fallbackScopes : [home.path]
                    start(predicate, scopes: scopes, request: request) { [self] metadata in
                        let now = Date()
                        var stageMatches = 0
                        for index in 0..<metadata.resultCount {
                            if index.isMultiple(of: 32), cancellation.isCancelled { return }
                            guard let item = metadata.result(at: index) as? NSMetadataItem,
                                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                                  SearchFilePolicy.isUserFile(path) else { continue }
                            let url = URL(fileURLWithPath: path)
                            let score = prepared.score(name: url.lastPathComponent)
                            guard score != nil || phase.isContent else { continue }
                            stageMatches += 1
                            let match = SpotlightFileMatch(url: url, lastOpened: item.value(forAttribute: "kMDItemLastUsedDate") as? Date,
                                                           isContentMatch: phase.isContent, nameScore: score)
                            matches[path] = matches[path].map { $0.merging(match) } ?? match
                        }
                        guard !cancellation.isCancelled else { return }
                        let best = matches.values.map { match in
                            let score = match.nameScore ?? 0
                            let relevance = score + SearchFilePolicy.locationBonus(match.url)
                                + SearchFilePolicy.recentBonus(match.lastOpened, now: now, window: recencyWindow)
                            return (match, SearchFilePolicy.tier(score), relevance)
                        }.sorted { l, r in
                            if l.1 != r.1 { return l.1 < r.1 }
                            return l.2 == r.2 ? l.0.url.path < r.0.url.path : l.2 > r.2
                        }.prefix(256).map { $0.0 }
                        matches = Dictionary(uniqueKeysWithValues: best.map { ($0.url.path, $0) })
                        let next = phase.next(
                            hasNames: hasNameMatches || best.contains { $0.nameScore != nil },
                            hasContent: phase.isContent && stageMatches > 0,
                            hasPersonalScope: fallbackScopes != [home.path],
                            allowsFallback: prepared.phrase.count >= 3
                        )
                        completion(best, next == nil)
                        if let next {
                            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) { [self] in
                                queue.addOperation { run(next) }
                            }
                        }
                    }
                }
                run(.names)
            }
        }

        private func start(_ predicate: NSPredicate, scopes: [String], request: Int, finished: @escaping (NSMetadataQuery) -> Void) {
            stopQuery()
            let query = NSMetadataQuery()
            query.operationQueue = queue
            query.notificationBatchingInterval = 0.05
            query.searchScopes = scopes
            query.predicate = predicate
            self.query = query
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil) { [weak self] notification in
                guard let self, self.activeRequest == request, let metadata = notification.object as? NSMetadataQuery,
                      self.query === metadata else { return }
                metadata.disableUpdates()
                finished(metadata)
                self.stopQuery()
            }
            if !query.start() { finished(query); stopQuery() }
        }

        private func stopQuery() {
            query?.stop()
            query = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}
