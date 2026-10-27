import AppKit

/// Runs a function's file — the spec's "open file, execute script, open
/// apps". `FilePicker` only lets the user choose a file, so this decides
/// how to run it: launch it directly if it's an executable script,
/// apps use the separate intelligent app opener; other files are handed
/// to Launch Services to open in their default app.
enum LeafActionRunner {
    static func run(_ url: URL) {
        print("🚀 Running leaf action: \(url.path)")

        let isExecutable = FileManager.default.isExecutableFile(atPath: url.path)
        let isAppBundle = url.pathExtension.lowercased() == "app"

        if isAppBundle {
            ApplicationOpener.open(url)
        } else if isExecutable {
            runScript(at: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Runs the script through the user's own login+interactive shell
    /// rather than exec'ing the file directly. A directly exec'd script
    /// inherits this app's own minimal GUI-process environment — no
    /// entries from ~/.zprofile or ~/.zshrc — so anything the script
    /// relies on the shell to have put on PATH (Homebrew, nvm, VS Code's
    /// `code` CLI shim, etc.) fails with "command not found" even though
    /// the identical script runs fine from Terminal. `-l -i` makes the
    /// shell source both the login and interactive startup files before
    /// running the script, so it sees the same PATH the user's terminal does.
    private static func runScript(at url: URL) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", shellQuoted(url.path)]
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("❌ Failed to run script, falling back to Launch Services: \(error)")
            NSWorkspace.shared.open(url)
        }
    }

    /// Single-quotes a path for safe embedding in a `-c` shell command
    /// string, so paths with spaces or other special characters can't
    /// split into multiple words when the shell parses it.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
