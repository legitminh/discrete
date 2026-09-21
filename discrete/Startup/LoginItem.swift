import ServiceManagement

/// Registers the app to launch automatically at login, so discrete mode
/// is available as soon as you log in rather than needing a manual launch.
enum LoginItem {
    static func registerIfNeeded() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else {
            print("✅ Already registered as a login item")
            return
        }
        do {
            try service.register()
            print("✅ Registered as a login item")
        } catch {
            print("❌ Failed to register as a login item: \(error)")
        }
    }
}
