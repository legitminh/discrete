import Foundation
@testable import discrete

/// Read-only policy checks: no browser automation, user graph or tab changes.
@main struct BrowserTabPolicyTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func window(_ id: String, order: Int, active: Int, urls: [(Int, String)]) -> BrowserTabPolicy.Window {
        BrowserTabPolicy.Window(id: id, index: order, activeTab: active, bounds: [0, 0, 800, 600],
                                tabs: urls.map { .init(index: $0.0, url: $0.1, title: "test") })
    }

    static func selected(_ id: String, _ index: Int) -> BrowserTabPolicy.Selection {
        .init(windowID: id, tabIndex: index)
    }

    static func main() {
        let prefix = "https://example.com/projects/"
        let first = window("2", order: 2, active: 1, urls: [
            (3, prefix + "second"), (1, prefix + "first"), (2, "https://unrelated.example/")
        ])
        let second = window("10", order: 1, active: 4, urls: [(4, prefix + "third")])
        let windows = [second, first]
        expect(BrowserTabPolicy.choose(windows: windows, prefix: prefix, browserIsFrontmost: false) == selected("2", 1),
               "Background browser must start at the first match, ordered by numeric session ID then tab index")
        expect(BrowserTabPolicy.choose(windows: windows, prefix: prefix, browserIsFrontmost: true) == selected("2", 1),
               "The last matching tab must wrap to the first")
        let firstFocused = window("2", order: 1, active: 1, urls: first.tabs.map { ($0.index, $0.url) })
        let secondBackground = window("10", order: 2, active: 4, urls: second.tabs.map { ($0.index, $0.url) })
        expect(BrowserTabPolicy.choose(windows: [firstFocused, secondBackground], prefix: prefix, browserIsFrontmost: true) == selected("2", 3),
               "Same-window cycling must skip unrelated tabs and follow the tab strip")
        let firstAtLast = window("2", order: 1, active: 3, urls: first.tabs.map { ($0.index, $0.url) })
        expect(BrowserTabPolicy.choose(windows: [secondBackground, firstAtLast], prefix: prefix, browserIsFrontmost: true) == selected("10", 4),
               "Cycling must advance to the next window after its last matching tab")
        let firstUnrelated = window("2", order: 1, active: 2, urls: first.tabs.map { ($0.index, $0.url) })
        expect(BrowserTabPolicy.choose(windows: [secondBackground, firstUnrelated], prefix: prefix, browserIsFrontmost: true) == selected("2", 1),
               "A focused unrelated tab must start at the first match")
        expect(BrowserTabPolicy.choose(windows: [second], prefix: prefix, browserIsFrontmost: true) == selected("10", 4),
               "A single match must stay selected")
        expect(BrowserTabPolicy.choose(windows: windows, prefix: "https://absent.example/", browserIsFrontmost: true) == nil,
               "No matches must request the webpage URL fallback")
        expect(BrowserTabPolicy.choose(windows: [], prefix: prefix, browserIsFrontmost: false) == nil,
               "No windows must request the webpage URL fallback")
        expect(BrowserTabPolicy.choose(windows: windows, prefix: " \n ", browserIsFrontmost: false) == nil,
               "An empty prefix must never match every tab")

        expect(BrowserTabPolicy.normalized(" HTTPS://EXAMPLE.COM/Projects/?Q=A#Top \n") == "https://example.com/Projects/?Q=A#Top",
               "Scheme and host case must normalize without changing path, query or fragment case")
        expect(BrowserTabPolicy.normalized("example.com/Projects/") == "https://example.com/Projects/",
               "A remote prefix without a scheme must default to HTTPS")
        expect(BrowserTabPolicy.normalized("localhost:8080/Projects/") == "http://localhost:8080/Projects/",
               "A localhost prefix must default to HTTP and preserve its port")
        expect(BrowserTabPolicy.normalized("192.168.1.1:8080/Projects/") == "http://192.168.1.1:8080/Projects/",
               "An IP prefix must default to HTTP")
        let exact = window("1", order: 1, active: 1, urls: [(1, "HTTPS://EXAMPLE.COM/Projects/")])
        expect(BrowserTabPolicy.choose(windows: [exact], prefix: "example.com/Projects/", browserIsFrontmost: false) == selected("1", 1),
               "An exactly equal URL after normalization must match")
        expect(BrowserTabPolicy.choose(windows: [exact], prefix: "example.com/projects/", browserIsFrontmost: false) == nil,
               "Path matching must remain case-sensitive")
        let containsOnly = window("1", order: 1, active: 1, urls: [(1, "https://other.example/?url=https://example.com/Projects/")])
        expect(BrowserTabPolicy.choose(windows: [containsOnly], prefix: "example.com/Projects/", browserIsFrontmost: false) == nil,
               "A prefix appearing only inside a URL must not match")
        let similarHost = window("1", order: 1, active: 1, urls: [(1, "https://example.com.evil.test/Projects/")])
        expect(BrowserTabPolicy.choose(windows: [similarHost], prefix: "https://example.com/", browserIsFrontmost: false) == nil,
               "A trailing slash must enforce the intended host boundary")
        print("Browser tab policy: \(checks) checks passed")
    }
}
