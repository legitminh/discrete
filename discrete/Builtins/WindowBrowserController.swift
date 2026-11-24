import AppKit
import ScreenCaptureKit
import SwiftUI

struct WindowBrowserSelection {
    let windowID: CGWindowID
    let processID: pid_t
}

private struct WindowBrowserItem: Identifiable {
    let id: CGWindowID
    let processID: pid_t
    let keyCode: CGKeyCode
    let appName: String
    let title: String
    let image: CGImage

    var imageSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

private struct CapturedWindow {
    let windowID: CGWindowID
    let processID: pid_t
    let appName: String
    let title: String
    let image: CGImage
}

/// Owns the built-in's transient screen-sized overlay. The user's saved graph
/// remains in its current state underneath it; Escape simply reveals that
/// state again, while a window key focuses the selected window and exits.
final class WindowBrowserController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<WindowBrowserView>?
    private var items: [WindowBrowserItem] = []
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    var onCancel: (() -> Void)?
    var onSelect: ((WindowBrowserSelection) -> Void)?

    func show() {
        generation += 1
        let currentGeneration = generation
        items = []
        let screen = screenUnderPointer()
        let panel = makePanel(frame: screen.frame)
        let hosting = NSHostingView(rootView: WindowBrowserView(items: [], status: "Loading windows…"))
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)
        self.panel = panel
        hostingView = hosting
        panel.orderFrontRegardless()

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                let captures = try await WindowBrowserCapture.capture(limit: KeyList.assignableKeys.count)
                guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                self.items = zip(KeyList.assignableKeys, captures).map { key, capture in
                    WindowBrowserItem(id: capture.windowID, processID: capture.processID, keyCode: key,
                                      appName: capture.appName, title: capture.title, image: capture.image)
                }
                let status = self.items.isEmpty ? "No application windows are available." : nil
                self.render(status: status)
            } catch {
                guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                self.render(status: error.localizedDescription)
            }
        }
    }

    func handleTap(_ keyCode: CGKeyCode) {
        if keyCode == KeyCode.escape {
            onCancel?()
            return
        }
        guard let item = items.first(where: { $0.keyCode == keyCode }) else { return }
        onSelect?(WindowBrowserSelection(windowID: item.id, processID: item.processID))
    }

    func hide() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        items = []
    }

    private func render(status: String?) {
        hostingView?.rootView = WindowBrowserView(items: items, status: status)
    }

    private func screenUnderPointer() -> NSScreen {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return panel
    }
}

private enum WindowBrowserCapture {
    struct CaptureError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func capture(limit: Int) async throws -> [CapturedWindow] {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError(message: "Allow Screen & System Audio Recording for Discrete, then reopen the window browser.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = content.windows.filter { window in
            guard let app = window.owningApplication else { return false }
            return app.processID != ownPID && window.windowLayer == 0
                && window.frame.width >= 100 && window.frame.height >= 80
        }.prefix(limit)

        var captures: [CapturedWindow] = []
        for window in windows {
            if Task.isCancelled { break }
            let configuration = SCStreamConfiguration()
            let scale = min(1, 1400 / max(window.frame.width, window.frame.height))
            configuration.width = max(1, Int((window.frame.width * scale).rounded()))
            configuration.height = max(1, Int((window.frame.height * scale).rounded()))
            configuration.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard let app = window.owningApplication else { continue }
                captures.append(CapturedWindow(windowID: window.windowID, processID: app.processID,
                                               appName: app.applicationName, title: window.title ?? "", image: image))
            } catch {
                print("🪟 Couldn't capture window \(window.windowID): \(error.localizedDescription)")
            }
        }
        return captures
    }
}

private struct WindowBrowserView: View {
    let items: [WindowBrowserItem]
    let status: String?

    private let toolbarHeight: CGFloat = 58
    private let margin: CGFloat = 22
    private let spacing: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("windows browser")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                HStack(spacing: 9) {
                    Text(KeyList.symbol(for: KeyCode.escape))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("cancel")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white)
            }
            .padding(.horizontal, margin)
            .frame(height: toolbarHeight)
            .background(.white.opacity(0.055))

            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)

            GeometryReader { geometry in
                if let status {
                    Text(status)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    grid(in: geometry.size)
                }
            }
        }
        .background(Color.black.opacity(0.92))
    }

    @ViewBuilder
    private func grid(in size: CGSize) -> some View {
        let viewport = CGSize(width: max(0, size.width - margin * 2),
                              height: max(0, size.height - margin * 2))
        let layout = WindowBrowserLayout.optimalGrid(imageSizes: items.map(\.imageSize), viewport: viewport)
        let columns = max(layout.columns, 1)
        let rows = max(layout.rows, 1)
        let cellWidth = max(1, (viewport.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let cellHeight = max(1, (viewport.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
        let gridColumns = Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: columns)

        LazyVGrid(columns: gridColumns, alignment: .center, spacing: spacing) {
            ForEach(items) { item in
                WindowBrowserTile(item: item)
                    .frame(width: cellWidth, height: cellHeight)
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .center)
        .padding(margin)
    }
}

private struct WindowBrowserTile: View {
    let item: WindowBrowserItem

    var body: some View {
        Image(decorative: item.image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay(alignment: .topLeading) {
                Text(KeyList.symbol(for: item.keyCode))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                let label = item.title.isEmpty ? item.appName : "\(item.appName) — \(item.title)"
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.7))
            }
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}
