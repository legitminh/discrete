import CoreGraphics
import Foundation

/// A single node in the discrete graph. Root has `parent == nil`. Each of
/// its `actions` is bound to one physical key (a virtual key code, which
/// is position-based and so survives keyboard layout changes) and either
/// transitions to a sub-state or calls a function.
final class DiscreteState {
    let id: UUID
    /// May be empty — the spec allows any text, including none.
    var name: String
    weak var parent: DiscreteState?
    var actions: [CGKeyCode: DiscreteAction] = [:]

    init(id: UUID = UUID(), name: String = "", parent: DiscreteState? = nil) {
        self.id = id
        self.name = name
        self.parent = parent
    }

    /// Every state below this one, at any depth — what "delete this state"
    /// takes down with it.
    var descendantCount: Int {
        actions.values.reduce(0) { count, action in
            guard case .transition(let child) = action else { return count }
            return count + 1 + child.descendantCount
        }
    }

    /// Whether any action is a function — the function items of the
    /// configure menu only exist when there's a function to configure.
    var hasFunctions: Bool {
        actions.values.contains { action in
            if case .function = action { return true }
            return false
        }
    }

    func key(of child: DiscreteState) -> CGKeyCode? {
        actions.first { _, action in
            if case .transition(let state) = action { return state === child }
            return false
        }?.key
    }
}

/// Identity equality — two `DiscreteState`s are equal iff they're the same node.
extension DiscreteState: Equatable {
    static func == (lhs: DiscreteState, rhs: DiscreteState) -> Bool {
        lhs === rhs
    }
}

/// "action: either a transition or a function." A function is its own
/// kind of action, not a state: a name and a target, no sub-states.
enum DiscreteAction {
    case transition(DiscreteState)
    case function(DiscreteFunction)

    var name: String {
        switch self {
        case .transition(let state): return state.name
        case .function(let function): return function.name
        }
    }
}

/// What a function runs: a file the user picked, or a builtin function
/// (by its stable id) with the argument it was given, if it takes one
/// (e.g. "open website"'s address).
enum FunctionTarget {
    case file(URL)
    case builtin(id: String, argument: String?)
}

/// A leaf that runs something: a file target is opened (app opened,
/// script run, other file opened in its default app) and discrete exits;
/// a builtin does what it does, exiting unless it says otherwise.
final class DiscreteFunction {
    var name: String
    var target: FunctionTarget

    init(name: String, target: FunctionTarget) {
        self.name = name
        self.target = target
    }

    /// A builtin target that no longer exists in this version's toolkit.
    var isTargetMissing: Bool {
        if case .builtin(let id, _) = target { return BuiltinToolkit.function(id: id) == nil }
        return false
    }
}
