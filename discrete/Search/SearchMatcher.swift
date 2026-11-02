import Foundation

/// Literal names are cheap and authoritative. Typos and explicit synonyms
/// are fallbacks; long words never match scattered letters in identifiers.
nonisolated enum SearchMatcher {
    struct Query: Sendable {
        let words: [String]
        let phrase: String

        init(_ text: String) {
            words = SearchMatcher.words(of: text)
            phrase = words.joined(separator: " ")
        }

        func score(name: String, allowsMeaning: Bool = true) -> Double? {
            guard !words.isEmpty else { return nil }
            let nameWords = SearchMatcher.words(of: name)
            guard !nameWords.isEmpty else { return nil }
            let name = nameWords.joined(separator: " ")
            if name == phrase { return 100 }
            if name.hasPrefix(phrase) { return 90 }
            if name.contains(phrase) { return 80 }
            if words.allSatisfy({ word in nameWords.contains { $0.hasPrefix(word) } }) { return 75 }
            if words.allSatisfy({ word in nameWords.contains { $0.contains(word) } }) { return 70 }
            if words.allSatisfy({ word in nameWords.contains { $0.contains(word) || isTypo(word, of: $0) } }) { return 50 }
            if words.count == 1, phrase.count <= 4, nameWords.count > 1 {
                let initials = nameWords.compactMap(\.first).map(String.init).joined()
                if initials.hasPrefix(phrase) { return 45 }
            }
            if allowsMeaning, words.allSatisfy({ word in
                let alternatives = relatedWords(to: word)
                return nameWords.contains { $0.contains(word) || alternatives.contains($0) }
            }) { return 30 }
            return nil
        }
    }

    static func score(name: String, query: String, allowsMeaning: Bool) -> Double? {
        Query(query).score(name: name, allowsMeaning: allowsMeaning)
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func words(of text: String) -> [String] {
        normalized(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

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

    // Small, predictable expansions: no model loading or semantic neighbours
    // such as polynomial/PyTorch for an ordinary book-title query.
    private static let synonymGroups = [
        ["document", "documents", "doc", "docs"],
        ["textbook", "textbooks", "book", "books", "manual"],
        ["photo", "photos", "picture", "pictures", "image", "images"],
        ["mail", "email", "inbox"], ["settings", "preferences", "configuration"],
        ["notes", "note", "memo", "memos"], ["folder", "directory"],
        ["movie", "movies", "film", "video"], ["music", "song", "audio"],
        ["presentation", "slides", "slideshow"], ["spreadsheet", "worksheet"]
    ]

    static func relatedWords(to word: String) -> [String] {
        synonymGroups.first { $0.contains(word) }?.filter { $0 != word } ?? []
    }
}
