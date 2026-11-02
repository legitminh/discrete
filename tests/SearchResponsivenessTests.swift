import Foundation
@testable import discrete

/// Opt-in live-index checks for the reported failures. Uses an in-memory graph,
/// the real graph-store typing path and the user's existing Spotlight index.
@main struct SearchResponsivenessTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func main() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let engine = SearchEngine(settings: UserSettings())
        engine.begin(root: DiscreteState(name: "fixture"))
        var maxKeyTime: TimeInterval = 0
        var maxMainGap: TimeInterval = 0
        var lastBeat = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            let now = Date()
            maxMainGap = max(maxMainGap, now.timeIntervalSince(lastBeat))
            lastBeat = now
        }
        defer { timer.invalidate() }

        func search(_ text: String, expected: @escaping (SearchResult) -> Bool) {
            var final = false
            var firstMatch: TimeInterval?
            let start = Date()
            engine.onUpdate = {
                if firstMatch == nil, engine.results.contains(where: expected) { firstMatch = Date().timeIntervalSince(start) }
                final = !engine.isSearching
            }
            for count in 1...text.count {
                let keyStart = Date()
                engine.update(query: String(text.prefix(count)))
                maxKeyTime = max(maxKeyTime, Date().timeIntervalSince(keyStart))
            }
            if engine.results.contains(where: expected) { firstMatch = Date().timeIntervalSince(start) }
            let deadline = Date().addingTimeInterval(5)
            while !final, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            expect(final, "Search must finish: \(text)")
            expect(engine.results.contains(where: expected), "Expected result missing: \(text)")
            expect(engine.results.allSatisfy { result in
                if case .file(let url) = result.item { return SearchFilePolicy.isUserFile(url.path) }
                return true
            }, "Package/generated files leaked into results")
            print("\(text): first expected result \(Int((firstMatch ?? 5) * 1000))ms; final \(Int(Date().timeIntervalSince(start) * 1000))ms")
            fflush(stdout)
        }

        search("document") { result in
            if case .file(let url) = result.item { return url == home.appendingPathComponent("Documents") }
            return false
        }
        expect(engine.results.first?.name == "Documents", "Documents must stay first after every search phase")
        search("linear algebra") { $0.name.hasPrefix("Linear Algebra") && $0.name.hasSuffix(".pdf") }
        expect(engine.results.first?.name.hasPrefix("Linear Algebra") == true, "A textbook must stay first")
        search("linaer algbra") { $0.name.hasPrefix("Linear Algebra") && $0.name.hasSuffix(".pdf") }
        search("eigenvalues") { $0.name.hasPrefix("Linear Algebra") && $0.detail.hasPrefix("content in ") }
        search("linear algebra") { $0.name.hasPrefix("Linear Algebra") && $0.name.hasSuffix(".pdf") }
        expect(maxKeyTime < 0.1, "Typing must not block on Spotlight or semantic model loading")
        expect(maxMainGap < 0.15, "Background search must keep the main run loop responsive")

        // Exercise the actual overlay session updates, not just a rank fixture.
        let root = DiscreteState(name: "fixture")
        let store = DiscreteGraphStore(settings: UserSettings(), root: root, saveGraph: { _ in })
        store.handleTap(KeyList.reservedSlots(for: root).search!)
        for character in "linear algebra" {
            store.handleTyped(TypedKey(keyCode: 0, flags: [], characters: String(character)))
        }
        let deadline = Date().addingTimeInterval(3)
        var found = false
        while Date() < deadline, !found {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if case .searching(let session) = store.mode {
                expect(session.buffer.text == "linear algebra", "The graph must retain the complete typed query")
                found = session.results.first?.name.hasPrefix("Linear Algebra") == true
            }
        }
        expect(found, "Real graph-store typing must show the textbook first")
        store.handleTyped(TypedKey(keyCode: KeyCode.escape, flags: [], characters: ""))
        engine.onUpdate = { fatalError("A cancelled search delivered stale results") }
        engine.update(query: "document")
        engine.end()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        expect(engine.results.isEmpty, "Exiting search clears all results")
        print("Live search: \(checks) checks passed; slowest key \(Int(maxKeyTime * 1000))ms; max main-loop gap \(Int(maxMainGap * 1000))ms")
    }
}
