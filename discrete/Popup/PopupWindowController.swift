import AppKit
import SwiftUI

/// Shows `PopupContentView` in a small, borderless, floating panel centered
/// on screen — like Raycast's HUD. Has no idea what triggers it or what
/// the rows mean; it just knows how to show a list of rows and hide them.
/// The coordinator decides when discrete mode is active and calls
/// `showRows`/`hide` accordingly.
final class PopupWindowController {
    private var panel: NSPanel?

    func showRows(_ rows: [OverlayRow]) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let wasVisible = panel.isVisible
        panel.contentView = NSHostingView(rootView: PopupContentView(rows: rows))
        panel.setContentSize(idealSize(for: rows))
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

    private func idealSize(for rows: [OverlayRow]) -> NSSize {
        NSSize(width: 320, height: CGFloat(max(rows.count, 1)) * 30 + 32)
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

    private func center(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
