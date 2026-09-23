import CoreGraphics
import Foundation

private struct StoredFunction: Codable {
    var name: String
    var path: String
}

/// `children` holds transitions (key → state id) and `functions` holds
/// functions. v0 graphs stored functions as child states carrying a
/// `scriptPath` instead — `load` still reads those and converts them.
private struct StoredState: Codable {
    let id: String
    var name: String?
    var scriptPath: String?
    var children: [String: String]?
    var functions: [String: StoredFunction]?
}

private struct StoredGraph: Codable {
    var rootID: String
    var states: [String: StoredState]
}

/// Saves/loads the discrete graph as JSON in Application Support so it
/// survives relaunches. Local file only, no sync.
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
            var functions: [String: StoredFunction] = [:]
            for (keyCode, action) in state.actions {
                switch action {
                case .transition(let child):
                    children[String(keyCode)] = child.id.uuidString
                    visit(child)
                case .function(let function):
                    functions[String(keyCode)] = StoredFunction(name: function.name, path: function.fileURL.path)
                }
            }
            states[state.id.uuidString] = StoredState(
                id: state.id.uuidString,
                name: state.name,
                children: children,
                functions: functions
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

            let state = DiscreteState(id: uuid, name: stored.name ?? "", parent: parent)
            built[id] = state

            for (keyString, childID) in stored.children ?? [:] {
                guard let keyCode = CGKeyCode(keyString), let child = graph.states[childID] else { continue }
                // v0 format: a "function" was a child state with a script attached.
                if let scriptPath = child.scriptPath {
                    let function = DiscreteFunction(name: child.name ?? "", fileURL: URL(fileURLWithPath: scriptPath))
                    state.actions[keyCode] = .function(function)
                } else if let childState = build(childID, parent: state) {
                    state.actions[keyCode] = .transition(childState)
                }
            }
            for (keyString, stored) in stored.functions ?? [:] {
                guard let keyCode = CGKeyCode(keyString) else { continue }
                let function = DiscreteFunction(name: stored.name, fileURL: URL(fileURLWithPath: stored.path))
                state.actions[keyCode] = .function(function)
            }
            return state
        }

        guard let root = build(graph.rootID, parent: nil) else { return nil }
        print("💾 Loaded graph (\(graph.states.count) states)")
        return root
    }
}
