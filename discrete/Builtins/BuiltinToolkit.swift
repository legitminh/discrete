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
        /// Opens the function's website in the default browser (see `WebsiteOpener`).
        case openWebsite
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
        case .moveWindowToNextMonitor, .openWebsite,
             .toggleSketchMode, .activateSketchMode, .deactivateSketchMode: return false
        }
    }

    /// Asked for (with state.text_string) right after this builtin is
    /// chosen, and stored with the function as its argument. nil when the
    /// builtin takes no argument.
    var argumentPrompt: String? {
        switch behavior {
        case .openWebsite: return "website url or ip address"
        case .openSearch, .moveWindowToNextMonitor,
             .toggleSketchMode, .activateSketchMode, .deactivateSketchMode: return nil
        }
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
        .function(BuiltinFunction(id: "open-website", name: "open website", behavior: .openWebsite)),
        .folder(BuiltinFolder(name: "trackpad functions", entries: [
            .function(BuiltinFunction(id: "toggle-sketch-mode", name: "toggle sketch mode", behavior: .toggleSketchMode)),
            .function(BuiltinFunction(id: "activate-sketch-mode", name: "activate sketch mode", behavior: .activateSketchMode)),
            .function(BuiltinFunction(id: "deactivate-sketch-mode", name: "deactivate sketch mode", behavior: .deactivateSketchMode))
        ]))
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
