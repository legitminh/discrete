import AppKit
import SwiftUI

/// Shows `PopupContentView` in a small, borderless, floating panel centered
/// on screen — like Raycast's HUD. Has no idea what triggers it or what
/// the content means; it just knows how to show it and hide it. The
/// coordinator decides when discrete mode is active and calls
/// `show`/`hide` accordingly.
final class PopupWindowController {
    private var panel: NSPanel?

    func show(_ content: OverlayContent) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let wasVisible = panel.isVisible
        panel.contentView = NSHostingView(rootView: PopupContentView(content: content))
        panel.setContentSize(idealSize(for: content))
        center(panel)

        guard !wasVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                panel.orderOut(nil)
            }
        )
    }

    private func idealSize(for content: OverlayContent) -> NSSize {
        // Title line + its spacing, the context line if any, plus one row-height per action.
        let contextHeight: CGFloat = content.context == nil ? 0 : 24
        return NSSize(width: 320, height: CGFloat(max(content.rows.count, 1)) * 30 + 56 + contextHeight)
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
        panel.level = .floating
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
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
