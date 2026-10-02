import Foundation
import NaturalLanguage

/// How well a name matches what was typed in state.search. Higher is
/// better; nil is no match. Tiers, best first: exact, prefix, word prefix,
/// substring, letters in order ("vsc" → "Visual Studio Code"), then
/// meaning (a word close to one of the query's words in the system's
/// on-device word embedding). All case- and diacritic-insensitive.
enum SearchMatcher {
    static func score(name: String, query: String, allowsMeaning: Bool) -> Double? {
        let name = normalized(name)
        let query = normalized(query).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !name.isEmpty else { return nil }

        if name == query { return 100 }
        if name.hasPrefix(query) { return 90 }
        let nameWords = words(of: name)
        if nameWords.contains(where: { $0.hasPrefix(query) }) { return 80 }
        if name.contains(query) { return 70 }
        if isSubsequence(query.filter { $0 != " " }, of: name) { return 50 }
        if allowsMeaning, let distance = meaningDistance(query: words(of: query), name: nameWords) {
            // Closer meaning ranks higher, always below every textual match.
            return 30 - distance
        }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(of text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    // MARK: - Meaning

    private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// Word-embedding cosine distance at or under which two words count as
    /// related. Measured: related pairs (mail/email, music/song,
    /// photo/picture, settings/preferences) sit around 0.8–1.12, unrelated
    /// ones from about 1.22 up.
    private static let meaningThreshold = 1.15

    /// Short words have too many loose neighbours to be useful.
    private static let minimumMeaningWordLength = 3

    /// The closest distance between any query word and any name word, if
    /// it's under the threshold.
    private static func meaningDistance(query: [String], name: [String]) -> Double? {
        guard let embedding else { return nil }
        let queryWords = query.filter { $0.count >= minimumMeaningWordLength && embedding.contains($0) }
        let nameWords = name.filter { $0.count >= minimumMeaningWordLength && embedding.contains($0) }
        var best: Double?
        for queryWord in queryWords {
            for nameWord in nameWords {
                let distance = embedding.distance(between: queryWord, and: nameWord)
                if distance <= meaningThreshold, distance < (best ?? .infinity) {
                    best = distance
                }
            }
        }
        return best
    }
}
