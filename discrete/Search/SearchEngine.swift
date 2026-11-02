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
        let result: SearchResult
        var lastOpened: Date? = nil
        var pathDepth: Int? = nil
        var isContentMatch = false
    }

    private let settings: UserSettings
    private let fileSearch = SpotlightFileSearch()
    private var catalog: [Candidate] = []
    private var files: [Candidate] = []
    private var query = ""

    init(settings: UserSettings) {
        self.settings = settings
    }

    func begin(root: DiscreteState) {
        catalog = Self.graphCandidates(under: root) + AppCatalog.apps().map { Self.appCandidate($0) }
        update(query: "")
    }

    func update(query: String) {
        self.query = query
        files = []
        rank()
        fileSearch.search(query) { [weak self] urls in
            guard let self else { return }
            self.files = urls.map { Self.fileCandidate($0, query: self.query) }
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

    /// Name matches precede content. Within names, recent opens come first;
    /// literal names precede imperfect/meaning matches, then shallower paths.
    /// Old opens are deliberately ignored rather than creating a lifetime bias.
    static func ranked(_ candidates: [Candidate], query: String, limit: Int, now: Date = Date()) -> [SearchResult] {
        guard !SearchMatcher.words(of: query).isEmpty else { return [] }
        struct Scored {
            let candidate: Candidate
            let score: Double
            let recent: Date?
            var matchTier: Int { score >= 70 ? 0 : (score >= 45 ? 1 : 2) }
        }
        let cutoff = now.addingTimeInterval(-UserSettings.searchRecencyWindow)
        let scored = candidates.compactMap { candidate -> Scored? in
            let nameScore = SearchMatcher.score(name: candidate.result.name, query: query, allowsMeaning: true)
            guard let score = nameScore ?? (candidate.isContentMatch ? 0 : nil) else { return nil }
            var candidate = candidate
            // A content query can also find a name match; rank it as a name.
            candidate.isContentMatch = nameScore == nil
            let recent = candidate.lastOpened.flatMap { $0 >= cutoff && $0 <= now ? $0 : nil }
            return Scored(candidate: candidate, score: score, recent: recent)
        }
        return scored.sorted { lhs, rhs in
            let l = lhs.candidate, r = rhs.candidate
            if l.isContentMatch != r.isContentMatch { return !l.isContentMatch }
            if lhs.recent != rhs.recent { return (lhs.recent ?? .distantPast) > (rhs.recent ?? .distantPast) }
            if lhs.matchTier != rhs.matchTier { return lhs.matchTier < rhs.matchTier }
            let ld = l.pathDepth ?? 0, rd = r.pathDepth ?? 0
            if ld != rd { return ld < rd }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if l.result.item.kindOrder != r.result.item.kindOrder { return l.result.item.kindOrder < r.result.item.kindOrder }
            if l.result.name.count != r.result.name.count { return l.result.name.count < r.result.name.count }
            let order = l.result.name.localizedStandardCompare(r.result.name)
            if order != .orderedSame { return order == .orderedAscending }
            return l.result.detail < r.result.detail
        }.prefix(max(0, limit)).map { $0.candidate.result }
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
        return Candidate(result: result, lastOpened: SearchUsageStore.shared.lastOpened(url), pathDepth: 0)
    }

    private static func fileCandidate(_ match: SpotlightFileMatch, query: String) -> Candidate {
        let url = match.url
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        let contentOnly = match.isContentMatch && SearchMatcher.score(name: url.lastPathComponent, query: query, allowsMeaning: true) == nil
        let result = SearchResult(item: .file(url), name: url.lastPathComponent,
                                  detail: contentOnly ? "content in \(folder)" : folder)
        return Candidate(result: result, lastOpened: SearchUsageStore.shared.lastOpened(url, indexedDate: match.lastOpened),
                         pathDepth: pathDepth(of: url), isContentMatch: match.isContentMatch)
    }

    static func pathDepth(of url: URL) -> Int {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = url.standardizedFileURL.path
        // Cloud containers are storage implementation details, not folder depth.
        for prefix in [home + "/Library/Mobile Documents/com~apple~CloudDocs/", home + "/Library/CloudStorage/"] {
            if path.hasPrefix(prefix) { path = String(path.dropFirst(prefix.count)); break }
        }
        if path.hasPrefix(home + "/") { path = String(path.dropFirst(home.count + 1)) }
        return max(0, (path as NSString).pathComponents.count - 1)
    }
}
