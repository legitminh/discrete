/// Wires the independent layers together: physical input feeds the signal
/// generator (inside `CapsLockClickListener`), whose `.tap` signal toggles
/// the popup. Nothing above this knows how the pieces connect.
final class AppCoordinator {
    private let settings = UserSettings()
    private let clickListener: CapsLockClickListener
    private let popup = PopupWindowController()

    init() {
        clickListener = CapsLockClickListener(settings: settings)
        clickListener.onClick = { [popup] in
            popup.toggle(text: "Hello")
        }
    }

    func start() {
        AccessibilityPermission.requestIfNeeded()
        clickListener.start()
    }
}
