import AppKit

/// Default-browser discovery, serialized native automation and window activation.
/// Matching/cycling and the browser-specific scripting adapter stay separate.
enum BrowserTabOpener {
    private static let queue = DispatchQueue(label: "minh.discrete.browser-automation")
    private static var requests: [() -> Void] = []
    private static var busy = false

    static func newTab(_ argument: String?) {
        guard let url = WebsiteOpener.url(from: argument ?? "") else {
            report("Enter a valid webpage URL in this function's settings."); return
        }
        let pointerRequest = SummonedWindowPointer.begin()
        guard let browser = defaultBrowser(for: url), supported(browser) else {
            WebsiteOpener.open(argument)
            return
        }
        enqueue {
            executeAndFollow(browser: browser, operation: "new", payload: url.absoluteString, pointerRequest: pointerRequest)
        }
    }

    static func openIfNotPresent(_ argument: String?) {
        guard let values = BuiltinToolkit.function(id: "open-webpage-if-not-present")?.decodeArguments(argument),
              let url = WebsiteOpener.url(from: values[0]), let prefix = BrowserTabPolicy.normalized(values[1]) else {
            report("Enter a valid webpage URL and URL prefix in this function's settings."); return
        }
        guard let browser = defaultBrowser(for: url), supported(browser) else {
            report("Open webpage if not present supports Google Chrome and Safari. Set either as your default browser to use it.")
            return
        }
        let pointerRequest = SummonedWindowPointer.begin()
        enqueue {
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == browser
            execute(browser: browser, operation: "scan", payload: "") { data in
                guard let data else { finish(); return }
                guard let windows = try? JSONDecoder().decode([BrowserTabPolicy.Window].self, from: data) else {
                    report("Couldn't read the browser's tab list. No new tab was opened."); finish(); return
                }
                guard let selected = BrowserTabPolicy.choose(windows: windows, prefix: prefix, browserIsFrontmost: isFrontmost),
                      let window = windows.first(where: { $0.id == selected.windowID }),
                      let tab = window.tabs.first(where: { $0.index == selected.tabIndex }) else {
                    executeAndFollow(browser: browser, operation: "new", payload: url.absoluteString, pointerRequest: pointerRequest)
                    return
                }
                struct Selection: Encodable { let windowID: String; let tabIndex: Int; let url: String }
                guard let encoded = try? JSONEncoder().encode(Selection(windowID: selected.windowID, tabIndex: selected.tabIndex, url: tab.url)),
                      let payload = String(data: encoded, encoding: .utf8) else { finish(); return }
                let select = {
                    executeAndFollow(browser: browser, operation: "select", payload: payload, pointerRequest: pointerRequest)
                }
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser).first {
                    BrowserWindowFocus.focus(window, app: app, frontWindow: { done in
                        execute(browser: browser, operation: "front", payload: "") { data in
                            done(data.flatMap { try? JSONDecoder().decode(String.self, from: $0) })
                        }
                    }, completion: select)
                } else { select() }
            }
        }
    }

    private static func defaultBrowser(for url: URL) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private static func supported(_ identifier: String) -> Bool {
        identifier == "com.google.Chrome" || identifier == "com.apple.Safari"
    }

    /// Include focus/Space completions in serialization, so rapid repeated
    /// invocations each see the tab selected by the previous invocation.
    private static func enqueue(_ request: @escaping () -> Void) {
        requests.append(request)
        if !busy { advance() }
    }

    private static func advance() {
        guard !requests.isEmpty else { busy = false; return }
        busy = true
        requests.removeFirst()()
    }

    private static func finish() { advance() }

    private static func executeAndFollow(browser: String, operation: String, payload: String,
                                         pointerRequest: SummonedWindowPointer.Request) {
        execute(browser: browser, operation: operation, payload: payload) { data in
            guard data != nil,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser).first else { finish(); return }
            pointerRequest.follow(app) { finish() }
        }
    }

    private static func execute(browser: String, operation: String, payload: String,
                                completion: @escaping (Data?) -> Void) {
        guard let script = Bundle.main.url(forResource: "BrowserAutomation", withExtension: "js") else {
            report("The browser automation resource is missing. Reinstall Discrete.")
            completion(nil); return
        }
        queue.async {
            let result = run(script: script, arguments: [browser, operation, payload])
            DispatchQueue.main.async {
                switch result {
                case .success(let data): completion(data)
                case .failure(let error):
                    report(error.localizedDescription)
                    completion(nil)
                }
            }
        }
    }

    private struct AutomationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    nonisolated private static func run(script: URL, arguments: [String]) -> Result<Data, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", script.path] + arguments
        let output = Pipe()
        process.standardOutput = output
        // Errors are small; keep them separate from potentially large tab lists.
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
            // Drain stdout before waiting: many tabs can exceed a pipe buffer.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            let error = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                let message = error.contains("-1743") || error.localizedCaseInsensitiveContains("not authorized")
                    ? "Allow Discrete to control your browser in System Settings → Privacy & Security → Automation, then try again. No new tab was opened."
                    : "Browser automation failed. Try again after closing any browser dialogs. No fallback tab was opened."
                return .failure(AutomationError(message: message))
            }
            return .success(data)
        } catch { return .failure(AutomationError(message: "Couldn't start browser automation: \(error.localizedDescription)")) }
    }

    private static func report(_ message: String) {
        print("🌐 \(message)")
        let alert = NSAlert()
        alert.messageText = "Discrete browser function"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
