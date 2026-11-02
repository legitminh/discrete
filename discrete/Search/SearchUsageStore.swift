import AppKit

/// Spotlight supplies system-wide document/app open dates. Keep immediate
/// local opens and app activations too, while Spotlight catches up.
final class SearchUsageStore {
    static let shared = SearchUsageStore()
    private static let defaultsKey = "searchLastOpenedPaths"
    private let defaults: UserDefaults
    private var opened: [String: Date]
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        opened = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Date] ?? [:]
    }

    func observeApplications() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier, let url = app.bundleURL else { return }
                self?.recordOpen(url)
            }
        }
    }

    func recordOpen(_ url: URL, at date: Date = Date()) {
        opened[url.standardizedFileURL.path] = date
        // Bound the persisted history; expired dates don't affect ranking.
        opened = Dictionary(uniqueKeysWithValues: opened.sorted { $0.value > $1.value }.prefix(1000).map { ($0.key, $0.value) })
        defaults.set(opened, forKey: Self.defaultsKey)
    }

    func recentURLs(since cutoff: Date) -> [URL] {
        let now = Date()
        return opened.filter { $0.value >= cutoff && $0.value <= now }.sorted { $0.value > $1.value }.prefix(128)
            .map { URL(fileURLWithPath: $0.key) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func lastOpened(_ url: URL) -> Date? {
        lastOpened(url, indexedDate: NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date)
    }

    func lastOpened(_ url: URL, indexedDate: Date?) -> Date? {
        [opened[url.standardizedFileURL.path], indexedDate].compactMap { $0 }.max()
    }
}
