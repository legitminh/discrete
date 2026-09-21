import CoreGraphics
import Foundation

private struct StoredState: Codable {
    let id: String
    var name: String?
    var scriptPath: String?
    var children: [String: String]
}

private struct StoredGraph: Codable {
    var rootID: String
    var states: [String: StoredState]
}

/// Saves/loads the discrete graph as JSON in Application Support so it
/// survives relaunches. Local file only, no sync — workplan Open
/// Question #6 didn't have an answer, so this is the simplest thing that
/// could work.
enum GraphPersistence {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("discrete", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("graph.json")
    }

    static func save(root: DiscreteState) {
        var states: [String: StoredState] = [:]

        func visit(_ state: DiscreteState) {
            guard states[state.id.uuidString] == nil else { return }
            var children: [String: String] = [:]
            for (keyCode, child) in state.children {
                children[String(keyCode)] = child.id.uuidString
                visit(child)
            }
            states[state.id.uuidString] = StoredState(
                id: state.id.uuidString,
                name: state.name,
                scriptPath: state.scriptURL?.path,
                children: children
            )
        }
        visit(root)

        let graph = StoredGraph(rootID: root.id.uuidString, states: states)
        do {
            let data = try JSONEncoder().encode(graph)
            try data.write(to: fileURL, options: .atomic)
            print("💾 Saved graph (\(states.count) states)")
        } catch {
            print("❌ Failed to save graph: \(error)")
        }
    }

    static func load() -> DiscreteState? {
        guard let data = try? Data(contentsOf: fileURL),
              let graph = try? JSONDecoder().decode(StoredGraph.self, from: data) else {
            return nil
        }

        var built: [String: DiscreteState] = [:]

        func build(_ id: String, parent: DiscreteState?) -> DiscreteState? {
            if let existing = built[id] { return existing }
            guard let stored = graph.states[id], let uuid = UUID(uuidString: id) else { return nil }

            let state = DiscreteState(id: uuid, name: stored.name, parent: parent)
            state.scriptURL = stored.scriptPath.map { URL(fileURLWithPath: $0) }
            built[id] = state

            for (keyString, childID) in stored.children {
                guard let keyCode = CGKeyCode(keyString), let child = build(childID, parent: state) else { continue }
                state.children[keyCode] = child
            }
            return state
        }

        guard let root = build(graph.rootID, parent: nil) else { return nil }
        print("💾 Loaded graph (\(graph.states.count) states)")
        return root
    }
}
