import AppKit

/// Executes whatever a leaf state points at. `ScriptPicker` only lets the
/// user choose a file (the spec's "open file system... select a script to
/// run"), so this decides how to run it: launch it directly if it's
/// executable, otherwise hand it to Launch Services — which is what
/// actually makes CapsLock+<key>-style app shortcuts work, since picking
/// e.g. VSCode.app and "running" it is just opening it normally.
enum LeafActionRunner {
    static func run(_ url: URL) {
        print("🚀 Running leaf action: \(url.path)")

        let isExecutable = FileManager.default.isExecutableFile(atPath: url.path)
        let isAppBundle = url.pathExtension == "app"

        if isExecutable, !isAppBundle {
            let process = Process()
            process.executableURL = url
            do {
                try process.run()
            } catch {
                print("❌ Failed to run script, falling back to Launch Services: \(error)")
                NSWorkspace.shared.open(url)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
