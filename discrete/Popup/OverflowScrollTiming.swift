import Foundation

/// Geometry-independent timing for a looping line of text. Two identical
/// copies, one cycleWidth apart, make the wrap back to offset zero seamless.
struct OverflowScrollTiming {
    static let pauseDuration: TimeInterval = 1.2

    let textWidth: Double
    let visibleWidth: Double
    let characterCount: Int
    let charactersPerSecond: Double

    var isScrolling: Bool {
        textWidth.isFinite && visibleWidth.isFinite && charactersPerSecond.isFinite
            && visibleWidth > 0 && textWidth > visibleWidth + 0.5
            && characterCount > 0 && charactersPerSecond > 0
            && pointsPerSecond.isFinite && pointsPerSecond > 0
    }

    var gap: Double { max(24, averageCharacterWidth * 4) }
    var cycleWidth: Double { textWidth + gap }
    private var averageCharacterWidth: Double { textWidth / Double(max(1, characterCount)) }
    private var pointsPerSecond: Double { averageCharacterWidth * charactersPerSecond }
    var cycleDuration: TimeInterval {
        isScrolling ? Self.pauseDuration + cycleWidth / pointsPerSecond : 0
    }

    func offset(at elapsed: TimeInterval) -> Double {
        guard isScrolling, elapsed.isFinite, elapsed > 0 else { return 0 }
        let phase = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        return max(0, phase - Self.pauseDuration) * pointsPerSecond
    }
}
