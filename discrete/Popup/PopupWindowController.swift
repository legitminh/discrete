import AppKit
import SwiftUI

/// Shows `PopupContentView` in a small, borderless, floating panel at the top
/// of the screen — like Raycast's HUD. Has no idea what triggers it or what
/// the content means; it just knows how to show it and hide it. The
/// coordinator decides when discrete mode is active and calls
/// `show`/`hide` accordingly.
final class PopupWindowController: NSObject, NSTextFieldDelegate {
    private final class OverlayPanel: NSPanel {
        // The panel can own its field editor without activating Discrete.
        override var canBecomeKey: Bool { !ignoresMouseEvents }
    }

    private var panel: OverlayPanel?
    private var hostingView: NSHostingView<PopupContentView>?
    private var field: NSTextField?
    private var draftID: UUID?
    private var selection = NSRange(location: 0, length: 0)

    var onTextChanged: ((String, UUID) -> Void)?
    var onTextCommand: ((TextInputCommand, UUID) -> Void)?

    /// Bumped on every show/hide, so a fade-out that finishes after the
    /// overlay was shown again doesn't order the new one out.
    private var generation = 0

    func show(_ content: OverlayContent, settings: UserSettings) {
        generation += 1

        // A fresh panel each time the overlay appears: the window server's
        // all-Spaces / full-screen-auxiliary membership of a long-lived
        // window can be dropped (sleep/wake, display changes, Dock restarts,
        // the app activating), pinning it to one desktop so it no longer
        // shows over full-screen apps.
        let isShowing = panel?.isVisible == true
        if !isShowing {
            panel = makePanel()
            let hosting = NSHostingView(rootView: PopupContentView(content: content, settings: settings))
            hosting.autoresizingMask = [.width, .height]
            panel?.contentView?.addSubview(hosting)
            hostingView = hosting
        }
        guard let panel, let container = panel.contentView, let hostingView else { return }

        hostingView.rootView = PopupContentView(content: content, settings: settings)
        panel.setContentSize(idealSize(for: content))
        hostingView.frame = container.bounds
        place(panel)
        updateField(for: content, in: panel, container: container)

        if isShowing {
            // Possibly mid fade-out from a hide that was interrupted.
            panel.animator().alphaValue = 1
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        if let field, field.currentEditor() == nil { focusField() }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        generation += 1
        let wasKey = panel.isKeyWindow
        removeField()
        draftID = nil
        panel.ignoresMouseEvents = true
        if wasKey {
            panel.orderOut(nil)
            self.panel = nil
            hostingView = nil
            return
        }
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
                self.hostingView = nil
            }
        )
    }

    private func idealSize(for content: OverlayContent) -> NSSize {
        let count = CGFloat(max(content.rows.count, 1))
        let height = PopupLayout.rowsTop(hasContext: content.context != nil) + PopupLayout.padding
            + count * PopupLayout.rowHeight + (count - 1) * PopupLayout.rowSpacing
        let width: CGFloat = content.isWide ? 480 : 320
        return NSSize(width: width, height: height)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
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

    // MARK: - Native text input

    private func updateField(for content: OverlayContent, in panel: OverlayPanel, container: NSView) {
        let draft = content.draft
        if draft?.id != draftID || draft?.isTyping != true { removeField() }
        if draft?.id != draftID {
            draftID = draft?.id
            selection = NSRange(location: draft?.text.utf16.count ?? 0, length: 0)
        }

        guard let draft, draft.isTyping else {
            let wasKey = panel.isKeyWindow
            panel.ignoresMouseEvents = true
            if wasKey {
                // Release the nonactivating panel's key focus back to the
                // foreground app before showing the keyboard actions.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
            return
        }
        panel.ignoresMouseEvents = false

        if field == nil {
            let input = NSTextField(string: draft.text)
            input.font = .systemFont(ofSize: 14)
            input.appearance = NSAppearance(named: .darkAqua)
            input.cell?.usesSingleLineMode = true
            input.cell?.isScrollable = true
            input.setAccessibilityLabel(content.context ?? "text")
            input.delegate = self
            container.addSubview(input, positioned: .above, relativeTo: hostingView)
            field = input
        }
        let left = PopupLayout.padding + PopupLayout.symbolWidth + PopupLayout.symbolSpacing
        let top = PopupLayout.rowsTop(hasContext: content.context != nil)
        field?.frame = NSRect(x: left, y: container.bounds.height - top - PopupLayout.rowHeight,
                              width: container.bounds.width - left - PopupLayout.padding,
                              height: PopupLayout.rowHeight)
    }

    private func removeField() {
        guard let field else { return }
        if let editor = field.currentEditor() {
            selection = editor.selectedRange
            panel?.makeFirstResponder(nil)
        }
        field.removeFromSuperview()
        self.field = nil
    }

    private func focusField() {
        guard let panel, let field else { return }
        if !panel.isKeyWindow { panel.makeKey() }
        if field.currentEditor() == nil {
            panel.makeFirstResponder(field)
            if let editor = field.currentEditor() as? NSTextView {
                editor.allowsUndo = true
                editor.setSelectedRange(selection)
            }
        }
    }

    func handleKeyDown(_ event: NSEvent) {
        focusField()
        guard let editor = field?.currentEditor() as? NSTextView else { return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let character = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command || modifiers == .control {
            // Events are sent directly to the field, so handle clipboard
            // equivalents here instead of sending them through the app menu.
            switch character {
            case "c": editor.copy(nil); return
            case "v": editor.pasteAsPlainText(nil); return
            case "x" where modifiers == .command: editor.cut(nil); return
            case "a" where modifiers == .command: editor.selectAll(nil); return
            case "z" where modifiers == .command: editor.undoManager?.undo(); return
            default: break
            }
        } else if modifiers == [.command, .shift], character == "z" {
            editor.undoManager?.redo()
            return
        }
        editor.keyDown(with: event)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let draftID, let editor = field?.currentEditor() else { return }
        onTextChanged?(editor.string, draftID)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let draftID else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            onTextChanged?(textView.string, draftID)
            onTextCommand?(.confirm, draftID)
        case #selector(NSResponder.cancelOperation(_:)):
            onTextCommand?(.cancel, draftID)
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            break
        default:
            return false
        }
        return true
    }

    /// Top-aligned to, and horizontally centered on, whichever screen the
    /// mouse pointer is on (re-checked on every update), so the overlay
    /// follows the user across displays. Anchoring the top edge means a
    /// change in row count only grows or shrinks the bottom.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height
        )
        panel.setFrameOrigin(origin)
    }
}
