import AppKit
import ApplicationServices
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
    let image: CGImage?
    let captureSize: CGSize

    var imageSize: CGSize {
        image.map { CGSize(width: $0.width, height: $0.height) } ?? captureSize
    }
}

private struct CapturedWindow {
    let windowID: CGWindowID
    let processID: pid_t
    let appName: String
    let title: String
    let image: CGImage?
    let captureSize: CGSize
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
                                      appName: capture.appName, title: capture.title, image: capture.image,
                                      captureSize: capture.captureSize)
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
        let runningApplications = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map {
            ($0.processIdentifier, $0)
        })
        let displays = ApplicationSpaces.displays() ?? []
        let fullscreenWindowIDs = Set(displays.flatMap(\.fullscreenWindowIDs))
        var spaceRanks: [UInt64: Int] = [:]
        for space in displays.flatMap(\.spaces) where spaceRanks[space] == nil {
            spaceRanks[space] = spaceRanks.count
        }
        var accessibilityDocuments: [pid_t: Set<CGWindowID>] = [:]
        for pid in Set(content.windows.compactMap { $0.owningApplication?.processID }) where pid != ownPID {
            accessibilityDocuments[pid] = accessibilityDocumentIDs(processID: pid)
        }
        var windowsByID: [CGWindowID: SCWindow] = [:]
        let candidates = content.windows.enumerated().compactMap { sourceOrder, window -> WindowBrowserOrdering.Candidate? in
            guard let app = window.owningApplication,
                  app.processID != ownPID,
                  let running = runningApplications[app.processID] else { return nil }
            let spaces = ApplicationSpaces.spaces(for: window.windowID)
            guard WindowBrowserWindowPolicy.isEligible(.init(
                layer: window.windowLayer,
                frame: window.frame,
                isRegularApplication: running.activationPolicy == .regular,
                spaces: spaces,
                isAccessibilityDocument: accessibilityDocuments[app.processID]?.contains(window.windowID) == true,
                isFullscreenDocument: fullscreenWindowIDs.contains(window.windowID)
            )) else { return nil }
            windowsByID[window.windowID] = window
            return WindowBrowserOrdering.Candidate(
                windowID: window.windowID,
                processID: app.processID,
                spaceRanks: (spaces ?? []).compactMap { spaceRanks[$0] },
                sourceOrder: sourceOrder
            )
        }
        let applicationRecency: [pid_t: Date] = Dictionary(uniqueKeysWithValues: runningApplications.compactMap { pid, app in
            guard let url = app.bundleURL,
                  let date = SearchUsageStore.shared.lastOpened(url, indexedDate: nil) else { return nil }
            return (pid, date)
        })
        let windows = WindowBrowserOrdering.sorted(candidates, applicationRecency: applicationRecency)
            .prefix(limit)
            .compactMap { windowsByID[$0.windowID] }

        var captures: [CapturedWindow] = []
        for window in windows {
            if Task.isCancelled { break }
            let configuration = SCStreamConfiguration()
            let scale = min(1, 1400 / max(window.frame.width, window.frame.height))
            configuration.width = max(1, Int((window.frame.width * scale).rounded()))
            configuration.height = max(1, Int((window.frame.height * scale).rounded()))
            configuration.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image: CGImage?
            do {
                image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            } catch {
                image = nil
                print("🪟 Couldn't capture window \(window.windowID): \(error.localizedDescription)")
            }
            // A failed or transparent capture must not make the selection
            // disappear. Keep a labeled tile and its key as a fallback.
            guard let app = window.owningApplication else { continue }
            captures.append(CapturedWindow(windowID: window.windowID, processID: app.processID,
                                           appName: app.applicationName, title: window.title ?? "", image: image,
                                           captureSize: window.frame.size))
        }
        return captures
    }

    /// AXWindows is the authority for windows a person can activate. Include
    /// main/focused fallbacks because some apps omit inactive/minimized windows
    /// from their ordinary list while still exposing one of those references.
    private static func accessibilityDocumentIDs(processID: pid_t) -> Set<CGWindowID> {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.3)
        var windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for name in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let value = attribute(application, name), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let element = value as! AXUIElement
                if !windows.contains(where: { CFEqual($0, element) }) { windows.append(element) }
            }
        }
        return Set(windows.compactMap { window in
            AXUIElementSetMessagingTimeout(window, 0.3)
            let subrole = attribute(window, kAXSubroleAttribute) as? String
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
            return ApplicationSpaces.windowID(of: window)
        })
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
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
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = item.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 32, weight: .light))
                        Text(item.appName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.42))
                }

                VStack {
                    Spacer()
                    let label = item.title.isEmpty ? item.appName : "\(item.appName) — \(item.title)"
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.76))
                }
            }
            // Anchor selection affordances to the fixed tile, never to the
            // screenshot. Chrome can return transparent or oddly bounded
            // frames; its key must remain visible and clickable-looking.
            .overlay(alignment: .topLeading) {
                Text(KeyList.symbol(for: item.keyCode))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.55)))
                    .padding(9)
            }
        }
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}
