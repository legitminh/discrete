import AppKit

/// The leaf state's "open file system for user to select a script to run" action.
enum ScriptPicker {
    static func pick(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose a script or app to run"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        // .begin so it doesn't block while discrete's own event tap is live.
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
}
