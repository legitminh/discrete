import Foundation
import NaturalLanguage

/// The same token vocabulary drives Spotlight retrieval and local ranking.
/// Every query word must match; a single related word cannot satisfy a phrase.
enum SearchMatcher {
    static func score(name: String, query: String, allowsMeaning: Bool) -> Double? {
        let name = normalized(name)
        let queryWords = words(of: query)
        let query = queryWords.joined(separator: " ")
        let nameWords = words(of: name)
        let phrase = nameWords.joined(separator: " ")
        guard !queryWords.isEmpty, !nameWords.isEmpty else { return nil }

        if name == query || phrase == query { return 100 }
        if phrase.hasPrefix(query) { return 90 }
        if phrase.contains(query) { return 80 }
        if queryWords.allSatisfy({ word in nameWords.contains { $0.hasPrefix(word) } }) { return 75 }
        if queryWords.allSatisfy({ word in nameWords.contains { $0.contains(word) } }) { return 70 }
        if queryWords.allSatisfy({ word in nameWords.contains { isTypo(word, of: $0) || isSubsequence(word, of: $0) } }) {
            return 50
        }
        // Initialisms may span words ("vsc" → "Visual Studio Code").
        if queryWords.count == 1, isSubsequence(query, of: phrase) { return 45 }
        if allowsMeaning, queryWords.allSatisfy({ word in
            let alternatives = relatedWords(to: word)
            return nameWords.contains { candidate in
                candidate.contains(word) || isTypo(word, of: candidate)
                    || alternatives.contains { candidate == $0 || candidate.hasPrefix($0) }
            }
        }) { return 30 }
        return nil
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func words(of text: String) -> [String] {
        normalized(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    /// Bounded Damerau–Levenshtein distance also accepts transposed letters.
    /// Short terms stay strict; two edits are allowed only for long words.
    static func typoAllowance(for word: String) -> Int {
        word.count >= 8 ? 2 : (word.count >= 4 ? 1 : 0)
    }

    private static func isTypo(_ query: String, of word: String) -> Bool {
        let limit = typoAllowance(for: query)
        guard limit > 0, abs(query.count - word.count) <= limit else { return false }
        let a = Array(query), b = Array(word)
        var previousPrevious = Array(0...b.count)
        var previous = previousPrevious
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
            }
            previousPrevious = previous
            previous = current
        }
        return previous[b.count] <= limit
    }

    // Deterministic common synonyms still work when the OS embedding is absent.
    private static let synonymGroups = [
        ["document", "documents", "doc", "docs"],
        ["textbook", "textbooks", "book", "books", "manual"],
        ["photo", "photos", "picture", "pictures", "image", "images"],
        ["mail", "email", "inbox"], ["settings", "preferences", "configuration"],
        ["notes", "note", "memo", "memos"], ["folder", "directory"],
        ["movie", "movies", "film", "video"], ["music", "song", "audio"],
        ["presentation", "slides", "slideshow"], ["spreadsheet", "worksheet"]
    ]
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)
    private static var relatedWordCache: [String: [String]] = [:]

    static func relatedWords(to word: String) -> [String] {
        if let cached = relatedWordCache[word] { return cached }
        var related = synonymGroups.filter { $0.contains(word) }.flatMap { $0 }
        if word.count >= 3, let embedding, embedding.contains(word) {
            related += embedding.neighbors(for: word, maximumCount: 8)
                .filter { $0.1 <= 1.05 && words(of: $0.0).count == 1 }
                .map { $0.0 }
        }
        let result = Array(Set(related.map { normalized($0) })).filter { $0 != word }.sorted()
        if relatedWordCache.count >= 512 { relatedWordCache.removeAll() }
        relatedWordCache[word] = result
        return result
    }
}
