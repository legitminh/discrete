import Foundation
@testable import discrete

/// Link against the Debug module; all candidates and recency dates are fixtures.
@main struct SearchTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func score(_ name: String, _ query: String) -> Double? {
        SearchMatcher.score(name: name, query: query, allowsMeaning: true)
    }
    static func file(_ name: String, depth: Int = 1, opened: Date? = nil, content: Bool = false) -> SearchEngine.Candidate {
        SearchEngine.Candidate(result: SearchResult(item: .file(URL(fileURLWithPath: "/fixture/\(depth)/\(name)")),
                                                    name: name, detail: "depth \(depth)"),
                               lastOpened: opened, pathDepth: depth, isContentMatch: content)
    }
    static func main() {
        expect(score("Linear Algebra and Its Applications.pdf", "Linear Algebra") == 90, "The textbook must match")
        expect(score("LINEAR_algebra.pdf", "  Línear   ALGEBRA \n") == 90, "Normalize case, accents, separators and whitespace")
        expect(score("Algebra — Linear.pdf", "linear algebra") != nil, "Word order must not prevent a name match")
        expect(score("Linear Algebra.pdf", "linaer algbra") != nil, "Accept transposition and missing-letter typos")
        expect(score("Visual Studio Code", "vsc") != nil, "Keep initialism matching")
        expect(score("Lecture Memos.txt", "lecture notes") != nil, "Synonyms must work for file names")
        expect(score("Inbox", "mail algebra") == nil, "Every query word must match, including for synonyms")
        expect(score("Linear.pdf", "linear algebra") == nil, "One matching word must not satisfy a phrase")
        expect(score("anything", " \n ") == nil, "Empty searches have no matches")
        expect(score("Preferences", "settings") == 30, "Common synonyms work without an embedding")
        expect(SearchMatcher.score(name: "Preferences", query: "settings", allowsMeaning: false) == nil, "Respect meaning opt-out")

        // Every one-edit typo accepted locally must also survive Spotlight retrieval.
        for original in ["word", "notes", "linear", "algebra", "document"] {
            let letters = Array(original)
            var variants: [String] = []
            for i in letters.indices {
                var substitution = letters; substitution[i] = "z"; variants.append(String(substitution))
                var deletion = letters; deletion.remove(at: i); variants.append(String(deletion))
                var insertion = letters; insertion.insert("z", at: i); variants.append(String(insertion))
                if i + 1 < letters.count {
                    var swap = letters; swap.swapAt(i, i + 1); variants.append(String(swap))
                }
            }
            for query in variants where score(original, query) != nil {
                expect(SpotlightFileSearch.fallbackPredicate(query, fuzzy: true).evaluate(with: ["kMDItemFSName": original]),
                       "Retrieval lost \(query) → \(original)")
            }
        }
        expect(SpotlightFileSearch.fallbackPredicate("lecture notes", fuzzy: false).evaluate(with: ["kMDItemFSName": "Lecture Memos.txt"]), "Retrieve synonyms before ranking")
        expect(SpotlightFileSearch.fallbackPredicate("vsc", fuzzy: true).evaluate(with: ["kMDItemFSName": "Visual Studio Code"]), "Retrieve initialisms before ranking")

        // In-memory predicate evaluation misses Spotlight's stricter syntax
        // rules. Starting real queries catches singleton AND/OR crashes.
        for text in ["a", "vsc", "notes", "orthogonalization", "linear algebra"] {
            for predicate in [SpotlightFileSearch.namePredicate(text), SpotlightFileSearch.fallbackPredicate(text, fuzzy: true), SpotlightFileSearch.contentPredicate(text)] {
                let query = NSMetadataQuery()
                query.searchScopes = ["/tmp"]
                query.predicate = predicate
                expect(query.start(), "Spotlight must accept predicates for \(text)")
                query.stop()
            }
        }
        let cancelled = SpotlightFileSearch()
        cancelled.search("linear algebra") { _ in fatalError("Cancelled searches must never deliver results") }
        cancelled.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let shallow = file("Document", depth: 0)
        let deep = file("Document", depth: 3)
        func ranked(_ candidates: [SearchEngine.Candidate], _ query: String = "document", limit: Int = 8) -> [SearchResult] {
            SearchEngine.ranked(candidates, query: query, limit: limit, now: now)
        }
        expect(ranked([deep, shallow]).first?.detail == "depth 0", "Prefer the high-level Document folder")
        let recent = file("Document", depth: 3, opened: now.addingTimeInterval(-60))
        expect(ranked([shallow, recent]).first?.detail == "depth 3", "A recent open outranks path depth")
        let older = file("Document old", depth: 3, opened: now.addingTimeInterval(-120))
        let newer = file("Document new", depth: 3, opened: now.addingTimeInterval(-60))
        expect(ranked([older, newer]).first?.name == "Document new", "Use recency for comparable name matches")
        let expired = file("Document", depth: 3, opened: now.addingTimeInterval(-UserSettings.searchRecencyWindow - 1))
        expect(ranked([expired, shallow]).first?.detail == "depth 0", "Ignore opens older than the configured week")
        let future = file("Document", depth: 3, opened: now.addingTimeInterval(60))
        expect(ranked([future, shallow]).first?.detail == "depth 0", "Ignore invalid future dates")
        let boundary = file("Document", depth: 3, opened: now.addingTimeInterval(-UserSettings.searchRecencyWindow))
        expect(ranked([shallow, boundary]).first?.detail == "depth 3", "The recency boundary is inclusive")
        let duplicateURL = URL(fileURLWithPath: "/fixture/Workbook.pdf")
        let broadName = SpotlightFileMatch(url: duplicateURL, lastOpened: nil, isContentMatch: false)
        let bodyMatch = SpotlightFileMatch(url: duplicateURL, lastOpened: now, isContentMatch: true)
        expect(broadName.merging(bodyMatch).isContentMatch, "Broad name retrieval must not suppress content evidence")
        expect(bodyMatch.merging(broadName).isContentMatch, "Content evidence must survive either arrival order")
        expect(bodyMatch.merging(broadName).lastOpened == now, "Deduplication keeps the newer open date")
        let content = file("Matrix Textbook.pdf", depth: 0, opened: now, content: true)
        expect(ranked([content, file("Linear Algebra.pdf", depth: 4)], "linear algebra").map(\.name) == ["Linear Algebra.pdf"], "Content-only files must not fill a successful name search")
        expect(ranked([content], "linear algebra").count == 1, "Content-only matches must survive local name filtering")
        expect(ranked([file("unrelated.pdf")], "linear algebra").isEmpty, "Broad retrieval candidates still need a match")
        let many = (1...250).map { file("Document \($0)", depth: 3) } + [shallow]
        expect(ranked(many, limit: 1).first?.name == "Document", "Apply the result limit only after ranking all candidates")
        expect(ranked([shallow], limit: 0).isEmpty, "Respect zero result limit")
        expect(ranked([shallow], "").isEmpty, "Don't turn an empty prompt into content results")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        expect(SpotlightFileSearch.isUserFile(home + "/Library/Mobile Documents/com~apple~CloudDocs/Math.pdf"), "Include iCloud documents")
        expect(SpotlightFileSearch.isUserFile(home + "/Library/CloudStorage/Drive/Math.pdf"), "Include cloud provider documents")
        expect(!SpotlightFileSearch.isUserFile(home + "/Library/Caches/Math.pdf"), "Exclude Library internals")
        expect(!SpotlightFileSearch.isUserFile(home + "/.hidden/Math.pdf"), "Exclude hidden files")
        expect(!SpotlightFileSearch.isUserFile(home + "/Apps/Tool.APP/Math.pdf"), "Exclude app internals regardless of case")
        expect(SearchEngine.pathDepth(of: URL(fileURLWithPath: home + "/Document")) < SearchEngine.pathDepth(of: URL(fileURLWithPath: home + "/Archive/Icloud/Document")), "Use real path hierarchy")
        expect(SearchEngine.pathDepth(of: URL(fileURLWithPath: home + "/Documents/Math.pdf")) == SearchEngine.pathDepth(of: URL(fileURLWithPath: home + "/Library/Mobile Documents/com~apple~CloudDocs/Documents/Math.pdf")), "Cloud container paths must not penalize folder depth")
        for path in ["Projects/repo/node_modules/tool/Document.js", "Projects/repo/.venv/math/LinearAlgebra.py", "Projects/repo/venv/lib/site-packages/torch/LinearAlgebra.h", "Projects/game/Library/PackageCache/tool/Documentation"] {
            expect(!SpotlightFileSearch.isUserFile(home + "/" + path), "Dependency internals must not pollute results: \(path)")
        }
        func realFile(_ path: String, opened: Date? = nil) -> SearchEngine.Candidate {
            let url = URL(fileURLWithPath: path)
            return SearchEngine.Candidate(result: SearchResult(item: .file(url), name: url.lastPathComponent, detail: path), lastOpened: opened)
        }
        let documents = realFile(home + "/Documents")
        let archive = realFile(home + "/iCloud Drive (Archive)/Documents", opened: now)
        expect(ranked([archive, documents]).first?.detail == home + "/Documents", "The actual Documents folder beats a freshly accessed archive")
        let book = realFile(home + "/Documents/books/Linear Algebra.pdf")
        let weak = realFile(home + "/polynomial.h", opened: now)
        expect(ranked([weak, book], "linear algebra").count == 1, "Semantic neighbours must not become textbook matches")
        expect(score("ApplyStringOrNumericBinaryOperator.js", "linear algebra") == nil, "Scattered identifier letters are not a title match")
        expect(ranked([book, book], "linear algebra").count == 1, "Seed and Spotlight copies appear only once")
        let recentTypo = realFile(home + "/Linaer Algbra.txt", opened: now)
        expect(ranked([recentTypo, book], "linear algebra").first?.name == "Linear Algebra.pdf", "A recent typo cannot displace a literal title")
        expect(!SpotlightFileSearch.namePredicate("linear algebra").evaluate(with: ["kMDItemFSName": "Polynomial.h"]), "Fast queries don't expand semantic neighbours")
        let phase = SpotlightFileSearch.Phase.names
        expect(phase.next(hasNames: true, hasContent: false, hasPersonalScope: true) == nil, "A title match must finish without a content query")
        expect(phase.next(hasNames: false, hasContent: false, hasPersonalScope: true) == .relaxedPersonal, "Try relaxed names before content")
        expect(SpotlightFileSearch.Phase.relaxedPersonal.next(hasNames: false, hasContent: false, hasPersonalScope: true) == .relaxedHome, "Exhaust home filenames before contents")
        expect(SpotlightFileSearch.Phase.relaxedHome.next(hasNames: false, hasContent: false, hasPersonalScope: true) == .contentPersonal, "Only failed name searches reach content")
        expect(SpotlightFileSearch.Phase.contentPersonal.next(hasNames: false, hasContent: false, hasPersonalScope: true) == .contentHome, "Empty personal content can broaden to home")
        expect(SpotlightFileSearch.Phase.relaxedPersonal.next(hasNames: true, hasContent: false, hasPersonalScope: true) == nil, "A typo match must finish without unrelated body hits")
        let retained = SearchEngine.mergeNameMatches(existing: [book], incoming: [content], query: "linear algebra")
        expect(ranked(retained, "linear algebra").map(\.name) == ["Linear Algebra.pdf"], "A content refresh cannot replace the textbook")
        expect(SearchEngine.mergeNameMatches(existing: [book], incoming: [], query: "linear algebra").count == 1, "An empty snapshot cannot erase a valid cached title")
        expect(SearchEngine.mergeNameMatches(existing: [content], incoming: [], query: "linear algebra").isEmpty, "Don't retain unrelated body matches as names")
        expect(SearchEngine.mergeNameMatches(existing: [book], incoming: [book], query: "linear algebra").count == 1, "Merged name snapshots stay deduplicated")
        let suite = "discrete-search-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = SearchUsageStore(defaults: defaults)
        let resource = URL(fileURLWithPath: "/fixture/book.pdf")
        usage.recordOpen(resource, at: now)
        expect(usage.lastOpened(resource, indexedDate: nil) == now, "Remember opens before Spotlight updates")
        expect(usage.lastOpened(resource, indexedDate: now.addingTimeInterval(-10)) == now, "Prefer the newer local date")
        expect(usage.lastOpened(resource, indexedDate: now.addingTimeInterval(10)) == now.addingTimeInterval(10), "Prefer a newer Spotlight date")
        expect(SearchUsageStore(defaults: defaults).lastOpened(resource, indexedDate: nil) == now, "Recent opens survive app relaunch")
        print("Search: \(checks) checks passed")
    }
}
