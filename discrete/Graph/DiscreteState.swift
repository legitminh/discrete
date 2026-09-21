import CoreGraphics
import Foundation

/// A single node in the discrete graph. Root ("home") has `parent == nil`.
/// Any state can have `scriptURL` set (via the "set action" step of
/// editing one of its parent's actions) — a state with a script runs it
/// the instant you navigate into it, instead of showing its own menu,
/// whether or not it also has children. This is how CapsLock+<key>
/// "opens VSCode"-style shortcuts from the spec's intro paragraph and the
/// formal tap-to-navigate graph in the "entry" section turn out to be the
/// same mechanism: a shortcut is just navigating into a state with a
/// script attached.
final class DiscreteState {
    let id: UUID
    var name: String?
    weak var parent: DiscreteState?
    var children: [CGKeyCode: DiscreteState] = [:]
    var scriptURL: URL?

    init(id: UUID = UUID(), name: String? = nil, parent: DiscreteState? = nil) {
        self.id = id
        self.name = name
        self.parent = parent
    }
}

/// Identity equality — two `DiscreteState`s are equal iff they're the same node.
extension DiscreteState: Equatable {
    static func == (lhs: DiscreteState, rhs: DiscreteState) -> Bool {
        lhs === rhs
    }
}
