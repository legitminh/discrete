import AppKit

/// state.file_select: the system file picker, for choosing the file,
/// script, or app a new function runs.
final class FilePicker {
    private var panel: NSOpenPanel?
    /// The app that was frontmost before the picker took focus — handed
    /// focus back afterwards, since discrete itself is a background app.
    private var previousApp: NSRunningApplication?

    var isOpen: Bool { panel != nil }

    func pick(prompt: String, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "discrete"
        panel.message = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        // Above the overlay (a .floating panel), which stays visible meanwhile.
        panel.level = .modalPanel
        self.panel = panel

        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()

        // .begin so it doesn't block the run loop the CapsLock listener lives on.
        panel.begin { [weak self] response in
            let url = response == .OK ? panel.url : nil
            self?.panel = nil
            self?.previousApp?.activate()
            self?.previousApp = nil
            completion(url)
        }
    }

    /// Closes the picker as if the user cancelled it.
    func cancel() {
        panel?.cancel(nil)
    }
}
