import AppKit
import SwiftUI

/// Shows `PopupContentView` in a small, borderless, floating panel centered
/// on screen — like Raycast's HUD. Has no idea what triggers it or what a
/// "click" is; it just knows how to show and hide text, and toggles between
/// the two on request.
final class PopupWindowController {
    private var panel: NSPanel?
    private var isVisible = false

    func toggle(text: String) {
        if isVisible {
            hide()
        } else {
            show(text: text)
        }
    }

    private func show(text: String) {
        print("💬 Showing popup: \"\(text)\"")
        isVisible = true

        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = NSHostingView(rootView: PopupContentView(text: text))
        center(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel else { return }
        print("💬 Hiding popup")
        isVisible = false

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

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 88),
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
