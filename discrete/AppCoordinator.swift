/// Wires the independent layers together: physical input feeds the signal
/// generator (inside `CapsLockClickListener`), whose `.tap` signal drives
/// the popup. Nothing above this knows how the pieces connect.
final class AppCoordinator {
    private let clickListener = CapsLockClickListener()
    private let popup = PopupWindowController()

    init() {
        clickListener.onClick = { [popup] in
            popup.show(text: "Hello")
        }
    }

    func start() {
        AccessibilityPermission.requestIfNeeded()
        clickListener.start()
    }
}
