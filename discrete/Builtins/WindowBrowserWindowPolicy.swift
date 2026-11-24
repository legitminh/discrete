import CoreGraphics

/// ScreenCaptureKit exposes utility panels, compositor surfaces and helper-app
/// windows alongside user-facing windows. The browser only admits windows the
/// user can actually select: Accessibility-confirmed documents/dialogs, plus
/// native fullscreen documents identified by Dock's Space metadata.
enum WindowBrowserWindowPolicy {
    struct Candidate {
        let layer: Int
        let frame: CGRect
        let isRegularApplication: Bool
        let spaces: [UInt64]?
        let isAccessibilityDocument: Bool
        let isFullscreenDocument: Bool
    }

    static func isEligible(_ candidate: Candidate) -> Bool {
        guard candidate.layer == 0,
              candidate.frame.width >= 100,
              candidate.frame.height >= 80,
              candidate.isRegularApplication,
              candidate.isAccessibilityDocument || candidate.isFullscreenDocument else { return false }
        // A known-empty membership is a transient surface (Chrome creates
        // several). nil means the optional private Space query is unavailable;
        // AX confirmation remains enough in that fallback.
        return candidate.spaces?.isEmpty != true
    }
}
