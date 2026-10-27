import Foundation

@main struct OverflowScrollTimingTests {
    static func main() {
        let timing = OverflowScrollTiming(textWidth: 600, visibleWidth: 200, characterCount: 60, charactersPerSecond: 6)
        assert(timing.isScrolling)
        assert(timing.offset(at: 0) == 0)
        assert(timing.offset(at: 1) == 0, "Text must pause at its beginning")
        assert(timing.offset(at: 1.2) == 0)
        assert(abs(timing.offset(at: 2.2) - 60) < 0.001, "Six characters/second at ten points per character")
        assert(timing.offset(at: timing.cycleDuration + 1) == 0, "Every loop must pause again")
        let beforeWrap = timing.offset(at: timing.cycleDuration - 0.001)
        assert(abs((timing.cycleWidth - beforeWrap) - 0.06) < 0.001,
               "The second identical copy must reach the first copy's origin smoothly at wrap")
        assert(timing.offset(at: timing.cycleDuration) == 0)
        let fast = OverflowScrollTiming(textWidth: 600, visibleWidth: 200, characterCount: 60, charactersPerSecond: 12)
        assert(abs(fast.offset(at: 2.2) - 120) < 0.001, "The configured character rate must scale speed")
        for rate in [0.0, -1, 1e308, .infinity, .nan] {
            let disabled = OverflowScrollTiming(textWidth: 600, visibleWidth: 200, characterCount: 60, charactersPerSecond: rate)
            assert(!disabled.isScrolling && disabled.offset(at: 5) == 0)
        }
        let fitting = OverflowScrollTiming(textWidth: 100, visibleWidth: 200, characterCount: 10, charactersPerSecond: 6)
        assert(!fitting.isScrolling && fitting.offset(at: 5) == 0, "Names that fit must stay still")
        let empty = OverflowScrollTiming(textWidth: 0, visibleWidth: 200, characterCount: 0, charactersPerSecond: 6)
        assert(!empty.isScrolling && empty.offset(at: 5) == 0)
        assert(timing.offset(at: -.infinity) == 0 && timing.offset(at: .nan) == 0)
        print("Overflow scrolling: timing, speed, seamless wrap, and disabled cases passed")
    }
}
