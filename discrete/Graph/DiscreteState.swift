import CoreGraphics
import Foundation

/// A single node in the discrete graph. Root ("home") has `parent == nil`.
/// A state with no `children` is a "leaf," which changes what its reserved
/// actions offer (see `KeyList.reservedSlots`) — and a leaf with
/// `scriptURL` set runs that script the instant you navigate into it,
/// instead of showing its own (empty) menu. This is how CapsLock+<key>
/// "opens VSCode"-style shortcuts from the spec's intro paragraph and the
/// formal tap-to-navigate graph in the "entry" section turn out to be the
/// same mechanism: a shortcut is just navigating into a leaf.
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

    var isLeaf: Bool { children.isEmpty }
}
