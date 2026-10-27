import Foundation

/// A function shipped with discrete itself. Functions the user adds store
/// its `id` (not its name), so the user's own name for the function and
/// the builtin's name stay independent. Every builtin is listed, with what
/// it does, in builtins.txt at the repository root.
final class BuiltinFunction {
    enum Behavior {
        /// Opens state.search, the same search the root's search action opens.
        case openSearch
        /// Moves the focused window to the next monitor (see `WindowMover`).
        case moveWindowToNextMonitor
        /// Opens a new webpage tab in the default browser (see `BrowserTabOpener`).
        case newTabOfWebpage
        /// Focuses/cycles matching tabs in the default browser before opening.
        case openWebpageIfNotPresent
        /// Cycles or brings an app's windows to the pointer's monitor.
        case openApplicationIntelligently
        /// Toggles native fullscreen for the focused window.
        case toggleFullScreen
        /// Turns sketch mode on if it's off, off if it's on (see `SketchMode`).
        case toggleSketchMode
        /// Turns sketch mode on (see `SketchMode`).
        case activateSketchMode
        /// Turns sketch mode off (see `SketchMode`).
        case deactivateSketchMode
    }

    let id: String
    let name: String
    let behavior: Behavior

    init(id: String, name: String, behavior: Behavior) {
        self.id = id
        self.name = name
        self.behavior = behavior
    }

    /// Builtins exit discrete after they run, like a file target, unless
    /// they say otherwise.
    var staysActive: Bool {
        switch behavior {
        case .openSearch: return true
        case .moveWindowToNextMonitor, .newTabOfWebpage, .openWebpageIfNotPresent, .openApplicationIntelligently, .toggleFullScreen,
             .toggleSketchMode, .activateSketchMode, .deactivateSketchMode: return false
        }
    }

    /// Asked in order after selection. Single arguments retain their original
    /// plain-string storage; multiple answers share the existing argument field
    /// as a JSON array, so saved graphs need no migration.
    var argumentPrompts: [String] {
        switch behavior {
        case .newTabOfWebpage: return ["webpage url"]
        case .openWebpageIfNotPresent: return ["webpage url", "url prefix to determine what counts as existing"]
        case .openApplicationIntelligently: return ["application name, bundle id, or .app path"]
        case .openSearch, .moveWindowToNextMonitor, .toggleFullScreen,
             .toggleSketchMode, .activateSketchMode, .deactivateSketchMode: return []
        }
    }

    func encodeArguments(_ values: [String]) -> String? {
        guard values.count == argumentPrompts.count, !values.isEmpty else { return nil }
        if values.count == 1 { return values[0] }
        guard let data = try? JSONEncoder().encode(values) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func decodeArguments(_ argument: String?) -> [String]? {
        guard !argumentPrompts.isEmpty else { return [] }
        guard let argument else { return nil }
        if argumentPrompts.count == 1 { return [argument] }
        guard let data = argument.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data),
              values.count == argumentPrompts.count else { return nil }
        return values
    }
}

/// A folder of the builtin toolkit. Like a state, but fixed and read-only.
final class BuiltinFolder {
    let name: String
    private(set) var entries: [BuiltinEntry] = []
    private(set) weak var parent: BuiltinFolder?

    init(name: String, entries: [BuiltinEntry]) {
        self.name = name
        self.entries = entries
        for case .folder(let child) in entries {
            child.parent = self
        }
    }
}

extension BuiltinFolder: Equatable {
    static func == (lhs: BuiltinFolder, rhs: BuiltinFolder) -> Bool {
        lhs === rhs
    }
}

enum BuiltinEntry {
    case folder(BuiltinFolder)
    case function(BuiltinFunction)

    var name: String {
        switch self {
        case .folder(let folder): return folder.name
        case .function(let function): return function.name
        }
    }
}

/// The fixed tree of builtin functions that ships with discrete, in
/// toolkit order.
enum BuiltinToolkit {
    static let root = BuiltinFolder(name: "builtin functions", entries: [
        .function(BuiltinFunction(id: "search", name: "search", behavior: .openSearch)),
        .function(BuiltinFunction(id: "move-window-to-next-monitor", name: "move window to next monitor", behavior: .moveWindowToNextMonitor)),
        .folder(BuiltinFolder(name: "browser functions", entries: [
            // Preserve the original ID so existing website bindings still run.
            .function(BuiltinFunction(id: "open-website", name: "new tab of webpage", behavior: .newTabOfWebpage)),
            .function(BuiltinFunction(id: "open-webpage-if-not-present", name: "open webpage if not present", behavior: .openWebpageIfNotPresent))
        ])),
        .folder(BuiltinFolder(name: "trackpad functions", entries: [
            .function(BuiltinFunction(id: "toggle-sketch-mode", name: "toggle sketch mode", behavior: .toggleSketchMode)),
            .function(BuiltinFunction(id: "activate-sketch-mode", name: "activate sketch mode", behavior: .activateSketchMode)),
            .function(BuiltinFunction(id: "deactivate-sketch-mode", name: "deactivate sketch mode", behavior: .deactivateSketchMode))
        ])),
        .function(BuiltinFunction(id: "open-application-intelligently", name: "open application intelligently", behavior: .openApplicationIntelligently)),
        .function(BuiltinFunction(id: "toggle-full-screen", name: "toggle full-screen", behavior: .toggleFullScreen))
    ])

    /// nil when a later version removed the builtin a function points to.
    static func function(id: String) -> BuiltinFunction? {
        func find(in folder: BuiltinFolder) -> BuiltinFunction? {
            for entry in folder.entries {
                switch entry {
                case .function(let function) where function.id == id:
                    return function
                case .folder(let child):
                    if let found = find(in: child) { return found }
                default:
                    continue
                }
            }
            return nil
        }
        return find(in: root)
    }
}
