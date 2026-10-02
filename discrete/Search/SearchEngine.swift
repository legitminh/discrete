import Foundation

/// Produces state.search's suggestions. The graph's functions and states
/// and the installed apps are gathered once when search opens and
/// matched on every keystroke; files come from Spotlight a moment later,
/// at which point `onUpdate` fires with the re-ranked list.
final class SearchEngine {
    /// File results arrived and `results` changed.
    var onUpdate: (() -> Void)?
    private(set) var results: [SearchResult] = []

    private struct Candidate {
        let result: SearchResult
        /// Meaning matching is skipped for files — there are too many
        /// loosely related names for it to help.
        let allowsMeaning: Bool
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
        catalog = Self.graphCandidates(under: root) + AppCatalog.apps().map(Self.appCandidate)
        update(query: "")
    }

    func update(query: String) {
        self.query = query
        files = []
        rank()
        fileSearch.search(query) { [weak self] urls in
            guard let self else { return }
            self.files = urls.map(Self.fileCandidate)
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

    /// Best score first; ties by kind (function, state, app, file), then
    /// shorter name, then alphabetical.
    private func rank() {
        let scored = (catalog + files).compactMap { candidate -> (Double, SearchResult)? in
            let score = SearchMatcher.score(name: candidate.result.name, query: query, allowsMeaning: candidate.allowsMeaning)
            return score.map { ($0, candidate.result) }
        }
        results = scored.sorted { lhs, rhs in
            let (lScore, l) = lhs, (rScore, r) = rhs
            if lScore != rScore { return lScore > rScore }
            if l.item.kindOrder != r.item.kindOrder { return l.item.kindOrder < r.item.kindOrder }
            if l.name.count != r.name.count { return l.name.count < r.name.count }
            return l.name.localizedStandardCompare(r.name) == .orderedAscending
        }
        .prefix(max(0, settings.maxSearchResults))
        .map(\.1)
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
                    candidates.append(Candidate(result: result, allowsMeaning: true))
                case .transition(let child):
                    let result = SearchResult(item: .state(child), name: child.name, detail: "state in \(location)")
                    candidates.append(Candidate(result: result, allowsMeaning: true))
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
        return Candidate(result: result, allowsMeaning: true)
    }

    private static func fileCandidate(_ url: URL) -> Candidate {
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        let result = SearchResult(item: .file(url), name: url.lastPathComponent, detail: folder)
        return Candidate(result: result, allowsMeaning: false)
    }
}
