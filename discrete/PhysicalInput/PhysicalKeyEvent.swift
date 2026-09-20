import Foundation
import CoreGraphics

/// A raw, uninterpreted physical key transition — just "this key went down"
/// or "this key went up" at some point in time. No notion of taps, clicks,
/// or holds lives here; that interpretation happens one layer up.
struct PhysicalKeyEvent {
    enum Phase {
        case down
        case up
    }

    let keyCode: CGKeyCode
    let phase: Phase
    let timestamp: TimeInterval
}
