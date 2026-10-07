import Foundation

/// One state.builtin_select.search suggestion: the builtin function or
/// folder it opens, and its path of folders.
struct BuiltinSearchResult {
    let entry: BuiltinEntry
    let name: String
    let detail: String

    fileprivate var kindOrder: Int {
        if case .function = entry { return 0 }
        return 1
    }
}

/// state.builtin_select.search's suggestions: state.search's matching and
/// ranking, over the builtin toolkit only. Ties: functions before folders,
/// then shorter name, then alphabetical.
enum BuiltinSearch {
    static func results(for query: String, limit: Int) -> [BuiltinSearchResult] {
        let scored = candidates().compactMap { candidate -> (Double, BuiltinSearchResult)? in
            SearchMatcher.score(name: candidate.name, query: query, allowsMeaning: true).map { ($0, candidate) }
        }
        return scored.sorted { lhs, rhs in
            let (lScore, l) = lhs, (rScore, r) = rhs
            if lScore != rScore { return lScore > rScore }
            if l.kindOrder != r.kindOrder { return l.kindOrder < r.kindOrder }
            if l.name.count != r.name.count { return l.name.count < r.name.count }
            return l.name.localizedStandardCompare(r.name) == .orderedAscending
        }
        .prefix(max(0, limit))
        .map(\.1)
    }

    /// Every function and folder below the toolkit root, described by the
    /// path of folders it lives in.
    private static func candidates() -> [BuiltinSearchResult] {
        var candidates: [BuiltinSearchResult] = []
        func walk(_ folder: BuiltinFolder, path: [String]) {
            let location = path.joined(separator: " › ")
            for entry in folder.entries {
                switch entry {
                case .function(let function):
                    candidates.append(BuiltinSearchResult(entry: entry, name: function.name, detail: "builtin in \(location)"))
                case .folder(let child):
                    candidates.append(BuiltinSearchResult(entry: entry, name: child.name, detail: "folder in \(location)"))
                    walk(child, path: path + [child.name])
                }
            }
        }
        walk(BuiltinToolkit.root, path: [BuiltinToolkit.root.name])
        return candidates
    }
}
