import Foundation

/// Produces state.search's suggestions. The graph's functions and states
/// and the installed apps are gathered once when search opens and
/// matched on every keystroke; files come from Spotlight a moment later,
/// at which point `onUpdate` fires with the re-ranked list.
final class SearchEngine {
    /// File results arrived and `results` changed.
    var onUpdate: (() -> Void)?
    private(set) var results: [SearchResult] = []

    struct Candidate {
        var result: SearchResult
        var lastOpened: Date? = nil
        var pathDepth: Int? = nil
        var isContentMatch = false
        var nameScore: Double? = nil
    }

    private let settings: UserSettings
    private let fileSearch = SpotlightFileSearch()
    private var catalog: [Candidate] = []
    private var files: [Candidate] = []
    private var query = ""
    private var cache: [String: [Candidate]] = [:]
    var isSearching: Bool { fileSearch.isSearching }

    init(settings: UserSettings) {
        self.settings = settings
    }

    func begin(root: DiscreteState) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let homeEntries = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let recent = SearchUsageStore.shared.recentURLs(since: Date().addingTimeInterval(-UserSettings.searchRecencyWindow))
        let seeds = Array(Set(homeEntries + recent)).filter { SearchFilePolicy.isUserFile($0.path) }.map {
            Self.fileCandidate(SpotlightFileMatch(url: $0, lastOpened: nil, isContentMatch: false))
        }
        catalog = Self.graphCandidates(under: root) + AppCatalog.apps().map { Self.appCandidate($0) } + seeds
        update(query: "")
    }

    func update(query: String) {
        self.query = query
        let key = SearchMatcher.Query(query).phrase
        // Keep useful names while Spotlight refreshes. Content evidence belongs
        // only to the exact query that produced it.
        files = cache[key] ?? files.map { candidate in
            var candidate = candidate
            candidate.isContentMatch = false
            candidate.nameScore = nil
            if candidate.result.detail.hasPrefix("content in ") {
                let result = candidate.result
                candidate.result = SearchResult(item: result.item, name: result.name, detail: String(result.detail.dropFirst(11)))
            }
            return candidate
        }
        rank()
        let prepared = SearchMatcher.Query(query)
        let hasNames = results.contains { (prepared.score(name: $0.name) ?? 0) >= 70 }
        fileSearch.search(query, limit: settings.maxSearchResults, hasNameMatches: hasNames) { [weak self] matches in
            guard let self else { return }
            self.files = matches.map { Self.fileCandidate($0) }
            if self.cache.count >= 32 { self.cache.removeAll() }
            self.cache[key] = self.files
            self.rank()
            self.onUpdate?()
        }
    }

    func end() {
        fileSearch.stop()
        catalog = []
        files = []
        results = []
        query = ""
    }

    // MARK: - Ranking

    private func rank() {
        results = Self.ranked(catalog + files, query: query, limit: settings.maxSearchResults)
    }

    /// Relevance comes first. Recency is a bounded boost within a matching
    /// tier, never permission for fuzzy names to outrank a real title.
    static func ranked(_ candidates: [Candidate], query: String, limit: Int, now: Date = Date()) -> [SearchResult] {
        let prepared = SearchMatcher.Query(query)
        guard !prepared.words.isEmpty, limit > 0 else { return [] }
        struct Scored {
            let candidate: Candidate
            let score: Double
            let relevance: Double
        }
        let scored = candidates.compactMap { candidate -> Scored? in
            let nameScore = candidate.nameScore ?? prepared.score(name: candidate.result.name)
            guard let score = nameScore ?? (candidate.isContentMatch ? 0 : nil) else { return nil }
            var location = -Double(min(candidate.pathDepth ?? 0, 16))
            if case .file(let url) = candidate.result.item { location = SearchFilePolicy.locationBonus(url) }
            let recent = SearchFilePolicy.recentBonus(candidate.lastOpened, now: now, window: UserSettings.searchRecencyWindow)
            return Scored(candidate: candidate, score: score, relevance: score + location + recent)
        }
        let sorted = scored.sorted { lhs, rhs in
            let l = lhs.candidate, r = rhs.candidate
            let lt = SearchFilePolicy.tier(lhs.score), rt = SearchFilePolicy.tier(rhs.score)
            if lt != rt { return lt < rt }
            if lhs.relevance != rhs.relevance { return lhs.relevance > rhs.relevance }
            if l.lastOpened != r.lastOpened {
                let cutoff = now.addingTimeInterval(-UserSettings.searchRecencyWindow)
                let ld = l.lastOpened.flatMap { $0 >= cutoff && $0 <= now ? $0 : nil }
                let rd = r.lastOpened.flatMap { $0 >= cutoff && $0 <= now ? $0 : nil }
                if ld != rd { return (ld ?? .distantPast) > (rd ?? .distantPast) }
            }
            if l.result.item.kindOrder != r.result.item.kindOrder { return l.result.item.kindOrder < r.result.item.kindOrder }
            if l.result.name.count != r.result.name.count { return l.result.name.count < r.result.name.count }
            let order = l.result.name.localizedStandardCompare(r.result.name)
            if order != .orderedSame { return order == .orderedAscending }
            return l.result.detail < r.result.detail
        }
        var seen: Set<URL> = []
        var results: [SearchResult] = []
        for match in sorted {
            if case .file(let url) = match.candidate.result.item, !seen.insert(url.standardizedFileURL).inserted { continue }
            results.append(match.candidate.result)
            if results.count == limit { break }
        }
        return results
    }

    // MARK: - Candidates

    /// Every function and every state below `root`, described by the path
    /// of states it lives in.
    private static func graphCandidates(under root: DiscreteState) -> [Candidate] {
        var candidates: [Candidate] = []
        func walk(_ state: DiscreteState, path: [String]) {
            let location = path.joined(separator: " › ")
            for action in state.actions.values {
                switch action {
                case .function(let function):
                    let result = SearchResult(item: .function(function), name: function.name, detail: "function in \(location)")
                    candidates.append(Candidate(result: result))
                case .transition(let child):
                    let result = SearchResult(item: .state(child), name: child.name, detail: "state in \(location)")
                    candidates.append(Candidate(result: result))
                    walk(child, path: path + [child.name])
                }
            }
        }
        walk(root, path: [root.name])
        return candidates
    }

    private static func appCandidate(_ url: URL) -> Candidate {
        let name = FileManager.default.displayName(atPath: url.path)
        let result = SearchResult(item: .app(url), name: (name as NSString).deletingPathExtension, detail: "app")
        return Candidate(result: result, lastOpened: SearchUsageStore.shared.lastOpened(url, indexedDate: nil), pathDepth: 0)
    }

    private static func fileCandidate(_ match: SpotlightFileMatch) -> Candidate {
        let url = match.url
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        let contentOnly = match.isContentMatch && match.nameScore == nil
        let result = SearchResult(item: .file(url), name: url.lastPathComponent,
                                  detail: contentOnly ? "content in \(folder)" : folder)
        return Candidate(result: result, lastOpened: SearchUsageStore.shared.lastOpened(url, indexedDate: match.lastOpened),
                         pathDepth: pathDepth(of: url), isContentMatch: match.isContentMatch, nameScore: match.nameScore)
    }

    static func pathDepth(of url: URL) -> Int { SearchFilePolicy.depth(url) }
}
