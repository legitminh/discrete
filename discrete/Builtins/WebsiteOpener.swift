import AppKit

/// The "open website" builtin. Opens the address the user gave when they
/// added the function in the default browser, which comes to the front.
enum WebsiteOpener {
    static func open(_ address: String?) {
        guard let url = url(from: address ?? "") else {
            print("🌐 Not a website address: \(address ?? "")")
            return
        }
        print("🌐 Opening \(url.absoluteString)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration)
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
