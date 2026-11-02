#if DEBUG
import AppKit

/// Opt-in diagnostics run through Launch Services under Discrete's identity.
/// A command-line probe inherits its terminal's file-access context instead.
enum SearchDiagnostics {
    private static var engine: SearchEngine?

    static func startIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--search-diagnostic"), arguments.count > flag + 2 else { return false }
        let text = arguments[flag + 1]
        let output = URL(fileURLWithPath: arguments[flag + 2])
        DispatchQueue.main.async {
            let search = SearchEngine(settings: UserSettings())
            engine = search
            let start = Date()
            var updates: [[String: Any]] = []
            var typedCount = 0
            search.begin(root: DiscreteState(name: "diagnostic"))
            search.onUpdate = {
                updates.append([
                    "typedCount": typedCount,
                    "elapsedMS": Date().timeIntervalSince(start) * 1000,
                    "final": !search.isSearching,
                    "results": search.results.map { ["name": $0.name, "detail": $0.detail] }
                ])
                if typedCount == text.count, !search.isSearching { finish(output, query: text, updates: updates) }
            }
            Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { timer in
                typedCount += 1
                search.update(query: String(text.prefix(typedCount)))
                if typedCount == text.count { timer.invalidate() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if engine != nil { finish(output, query: text, updates: updates) }
            }
        }
        return true
    }

    private static func finish(_ output: URL, query: String, updates: [[String: Any]]) {
        let result: [String: Any] = [
            "query": query,
            "bundle": Bundle.main.bundleIdentifier ?? "",
            "home": FileManager.default.homeDirectoryForCurrentUser.path,
            "updates": updates
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output, options: .atomic)
        }
        engine?.end()
        engine = nil
        NSApplication.shared.terminate(nil)
    }
}
#endif
