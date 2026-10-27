import AppKit

/// Shared URL normalization and Launch Services fallback for browser functions.
enum WebsiteOpener {
    static func open(_ address: String?) {
        guard let url = url(from: address ?? "") else {
            print("🌐 Not a website address: \(address ?? "")")
            return
        }
        print("🌐 Opening \(url.absoluteString)")
        let pointerRequest = SummonedWindowPointer.begin()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                guard error == nil, let app else { return }
                pointerRequest.follow(app)
            }
        }
    }

    /// An address without a scheme gets one: http:// for an ip address or
    /// localhost (local devices rarely serve https), https:// otherwise.
    static func url(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") ? trimmed : "\(isLocal(trimmed) ? "http" : "https")://\(trimmed)"
        guard let url = URL(string: full), url.host?.isEmpty == false else { return nil }
        return url
    }

    private static func isLocal(_ address: String) -> Bool {
        let host = address.split(whereSeparator: { "/:".contains($0) }).first.map(String.init) ?? ""
        if host == "localhost" || address.hasPrefix("[") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}
