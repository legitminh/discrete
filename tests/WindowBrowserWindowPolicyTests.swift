import CoreGraphics

@main
struct WindowBrowserWindowPolicyTests {
    static func candidate(layer: Int = 0, width: CGFloat = 900, height: CGFloat = 600,
                          regular: Bool = true, spaces: [UInt64]? = [4], ax: Bool = true,
                          fullscreen: Bool = false) -> WindowBrowserWindowPolicy.Candidate {
        .init(layer: layer, frame: CGRect(x: 0, y: 0, width: width, height: height),
              isRegularApplication: regular, spaces: spaces,
              isAccessibilityDocument: ax, isFullscreenDocument: fullscreen)
    }

    static func main() {
        assert(WindowBrowserWindowPolicy.isEligible(candidate()),
               "An AX standard window on a desktop is selectable")
        assert(WindowBrowserWindowPolicy.isEligible(candidate(spaces: nil)),
               "AX windows survive unavailable private Space metadata")
        assert(WindowBrowserWindowPolicy.isEligible(candidate(ax: false, fullscreen: true)),
               "Dock-confirmed fullscreen documents survive omitted AX windows")
        assert(!WindowBrowserWindowPolicy.isEligible(candidate(spaces: [], ax: false)),
               "Chrome transient surfaces without Space membership are excluded")
        assert(!WindowBrowserWindowPolicy.isEligible(candidate(spaces: [], ax: true)),
               "Even AX-like transient surfaces with known-empty membership are excluded")
        assert(!WindowBrowserWindowPolicy.isEligible(candidate(regular: false)),
               "Helper-app windows such as ChatGPT ComputerUse are excluded")
        assert(!WindowBrowserWindowPolicy.isEligible(candidate(ax: false)),
               "Unverified layer-zero panels are excluded")
        assert(!WindowBrowserWindowPolicy.isEligible(candidate(layer: 3)),
               "Non-window layers are excluded")
        assert(!WindowBrowserWindowPolicy.isEligible(candidate(width: 80)),
               "Tiny utility surfaces are excluded")
        // Minimized state is intentionally absent from the policy: a real AX
        // document remains selectable and is restored by ApplicationOpener.
        assert(WindowBrowserWindowPolicy.isEligible(candidate()),
               "Minimized real windows remain eligible")
        print("Window browser eligibility: 10 scenarios passed")
    }
}
