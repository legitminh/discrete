import CoreGraphics
import Foundation

/// In-memory key-down order for one potential CapsLock activation. Releases
/// only track which keys still need draining after synthetic replay; they do
/// not determine replay order. No input is retained between CapsLock presses.
struct CapsLockActivationBuffer<Input> {
    private(set) var startedAt: TimeInterval?
    private var inputs: [Input] = []
    private var heldKeys: Set<CGKeyCode> = []

    var isPending: Bool { startedAt != nil }

    mutating func begin(at time: TimeInterval) {
        guard !isPending else { return }
        startedAt = time
        inputs.removeAll()
        heldKeys.removeAll()
    }

    @discardableResult
    mutating func keyDown(_ keyCode: CGKeyCode, input: Input) -> Bool {
        guard isPending, heldKeys.insert(keyCode).inserted else { return false }
        inputs.append(input)
        return true
    }

    @discardableResult
    mutating func keyUp(_ keyCode: CGKeyCode) -> Bool {
        heldKeys.remove(keyCode) != nil
    }

    func containsHeldKey(_ keyCode: CGKeyCode) -> Bool {
        heldKeys.contains(keyCode)
    }

    mutating func finish() -> (inputs: [Input], heldKeys: Set<CGKeyCode>) {
        let result = (inputs, heldKeys)
        cancel()
        return result
    }

    mutating func cancel() {
        startedAt = nil
        inputs.removeAll()
        heldKeys.removeAll()
    }
}
