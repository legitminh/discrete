import AppKit
import SwiftUI

/// Shows `PopupContentView` in a small, borderless, floating panel centered
/// on screen — like Raycast's HUD. Has no idea what triggers it or what
/// the content means; it just knows how to show it and hide it. The
/// coordinator decides when discrete mode is active and calls
/// `show`/`hide` accordingly.
final class PopupWindowController {
    private var panel: NSPanel?
    /// Bumped on every show/hide, so a fade-out that finishes after the
    /// overlay was shown again doesn't order the new one out.
    private var generation = 0

    func show(_ content: OverlayContent) {
        generation += 1

        // A fresh panel each time the overlay appears: the window server's
        // all-Spaces / full-screen-auxiliary membership of a long-lived
        // window can be dropped (sleep/wake, display changes, Dock restarts,
        // the app activating), pinning it to one desktop so it no longer
        // shows over full-screen apps.
        let isShowing = panel.map { $0.isVisible && $0.alphaValue > 0 } ?? false
        if !isShowing {
            panel?.orderOut(nil)
            panel = makePanel()
        }
        guard let panel else { return }

        panel.contentView = NSHostingView(rootView: PopupContentView(content: content))
        panel.setContentSize(idealSize(for: content))
        center(panel)

        guard !isShowing else {
            // Possibly mid fade-out from a hide that was interrupted.
            panel.animator().alphaValue = 1
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        generation += 1
        let hideGeneration = generation
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                guard let self, self.generation == hideGeneration else { return }
                panel.orderOut(nil)
                self.panel = nil
            }
        )
    }

    private func idealSize(for content: OverlayContent) -> NSSize {
        // Title line + its spacing, the context line if any, plus one row-height per action.
        let contextHeight: CGFloat = content.context == nil ? 0 : 24
        let width: CGFloat = content.isWide ? 480 : 320
        return NSSize(width: width, height: CGFloat(max(content.rows.count, 1)) * 30 + 56 + contextHeight)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Above .floating, which full-screen video players and games may use too.
        panel.level = .statusBar
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return panel
    }

    /// Centers on whichever screen the mouse pointer is on (re-checked on
    /// every update), so the overlay follows the user across displays.
    private func center(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
