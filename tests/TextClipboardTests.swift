import AppKit
@testable import discrete

/// In-memory graph and clipboard: never touches the user's saved data or pasteboard.
@main struct TextClipboardTests {
    final class Clipboard { var text: String?; var writes = 0; var saves = 0 }
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    static func fixture() -> (DiscreteGraphStore, Clipboard) {
        let clipboard = Clipboard()
        let store = DiscreteGraphStore(settings: UserSettings(), root: DiscreteState(name: "test"),
                                       saveGraph: { _ in clipboard.saves += 1 },
                                       readClipboard: { clipboard.text }, writeClipboard: { clipboard.text = $0; clipboard.writes += 1 })
        return (store, clipboard)
    }

    static func type(_ store: DiscreteGraphStore, _ code: CGKeyCode = 0, _ text: String = "", flags: CGEventFlags = []) {
        store.handleTyped(TypedKey(keyCode: code, flags: flags, characters: text))
    }

    static func editor(_ store: DiscreteGraphStore, text: String = "abc") {
        store.handleTap(KeyList.reservedSlots(for: store.root).configure!)
        store.handleTap(KeyList.ConfigureSlots.nameState)
        type(store, 0, text)
    }

    static func buffer(_ store: DiscreteGraphStore) -> TextBuffer {
        switch store.mode {
        case .editingText(let request): return request.buffer
        case .searching(let session): return session.buffer
        case .searchingBuiltins(let session): return session.buffer
        default: fatalError("Expected a text input")
        }
    }

    static func main() {
        do {
            let (store, clipboard) = fixture()
            editor(store)
            type(store, KeyCode.leftArrow)
            type(store, KeyCode.c, "c", flags: .maskCommand)
            expect(clipboard.text == "abc" && clipboard.writes == 1, "Command-C copies the whole field without the caret")
            expect(buffer(store).text == "abc" && buffer(store).cursor == 2, "Copy preserves text and caret")
            expect(clipboard.saves == 0 && store.root.name == "test", "Copy never saves the draft")
            clipboard.text = "é🙂\n\t12"
            type(store, KeyCode.v, "v", flags: .maskCommand)
            expect(buffer(store).text == "abé🙂12c" && buffer(store).cursor == 6, "Paste inserts Unicode at the caret and filters line breaks/control characters")
            expect(clipboard.writes == 1 && clipboard.saves == 0, "Paste neither overwrites the clipboard nor saves")
            type(store, KeyCode.enter)
            expect(store.root.name == "abé🙂12c" && clipboard.saves == 1, "Enter saves the pasted draft exactly once")
        }
        do {
            let (store, clipboard) = fixture()
            editor(store)
            clipboard.text = nil
            type(store, KeyCode.v, "v", flags: .maskCommand)
            expect(buffer(store).text == "abc", "An absent text clipboard is a no-op")
            clipboard.text = ""
            type(store, KeyCode.v, "v", flags: .maskCommand)
            expect(buffer(store).text == "abc", "An empty clipboard never inserts the shortcut letter")
            type(store, KeyCode.c, "c", flags: [.maskCommand, .maskControl])
            expect(clipboard.writes == 0, "Other modified shortcuts must not unexpectedly copy")
        }
        do {
            let (store, clipboard) = fixture()
            editor(store)
            type(store, KeyCode.leftArrow)
            let rows = OverlayRowBuilder.build(for: store.root, mode: store.mode).rows
            expect(rows.contains { $0.symbol == "⌘" && $0.label == "command functions" }, "Text inputs visibly advertise the Command menu")
            expect(rows.first?.label == "ab▏c" && rows.last?.label == "exit discrete", "The text stays first and CapsLock stays last")
            type(store, KeyCode.leftCommand)
            guard case .commandFunctions = store.mode else { fatalError("Command opens its functions") }
            let commands = OverlayRowBuilder.build(for: store.root, mode: store.mode).rows
            expect(commands.contains { $0.label == "copy" } && commands.contains { $0.label == "paste" }, "Both clipboard actions are discoverable")
            expect(commands.contains { $0.label == "return to text" }, "Escape has an explicit return action")
            type(store, KeyCode.c, "c", flags: [.maskCommand, .maskControl])
            expect(clipboard.writes == 0, "Extra modifiers must not trigger clipboard actions inside the menu either")
            type(store, KeyCode.escape)
            expect(buffer(store).text == "abc" && buffer(store).cursor == 2 && clipboard.saves == 0, "Escape returns to the intact draft without cancelling it")
            type(store, KeyCode.rightCommand)
            type(store, KeyCode.c, "c", flags: .maskCommand)
            expect(clipboard.text == "abc" && buffer(store).cursor == 2, "Right Command plus C copies once and returns to typing")
            clipboard.text = "XYZ"
            type(store, KeyCode.leftCommand)
            type(store, KeyCode.v)
            expect(buffer(store).text == "abXYZc" && buffer(store).cursor == 5, "Command then plain V pastes and restores the editor")
            type(store, KeyCode.leftCommand)
            store.cancelEditInProgress()
            expect(clipboard.saves == 0 && store.root.name == "test", "CapsLock in the command menu cancels the draft")
            guard case .navigating = store.mode else { fatalError("Cancellation must exit the menu") }
        }
        do {
            let (store, clipboard) = fixture()
            store.handleTap(KeyList.reservedSlots(for: store.root).search!)
            clipboard.text = "12unique-query"
            type(store, KeyCode.v, "v", flags: .maskCommand)
            expect(buffer(store).text == "12unique-query", "Pasted search digits are text, never suggestion shortcuts")
            type(store, KeyCode.leftCommand)
            let content = OverlayRowBuilder.build(for: store.root, mode: store.mode)
            expect(content.isWide, "The command menu retains the search layout")
            type(store, KeyCode.c)
            expect(clipboard.text == "12unique-query", "Search queries can be copied through the command menu")
            type(store, KeyCode.escape)
            guard case .navigating = store.mode else { fatalError("Search Escape still exits search") }
        }
        do {
            let (store, clipboard) = fixture()
            store.handleTap(KeyList.reservedSlots(for: store.root).configure!)
            store.handleTap(KeyList.ConfigureSlots.addFunction)
            store.handleTap(KeyList.AddFunctionSlots.builtin)
            store.handleTap(KeyCode.c)
            type(store, 0, "test function")
            type(store, KeyCode.enter)
            guard case .selectingBuiltin(let request) = store.mode else { fatalError("Expected builtin picker") }
            store.handleTap(KeyList.builtinFolderSlots(for: request.folder).system!)
            clipboard.text = "browser"
            type(store, KeyCode.leftCommand)
            type(store, KeyCode.v)
            guard case .searchingBuiltins(let session) = store.mode else { fatalError("Expected builtin search") }
            expect(session.buffer.text == "browser" && !session.results.isEmpty, "Builtin-search paste refreshes matching results")
            type(store, KeyCode.c, "c", flags: .maskCommand)
            expect(clipboard.text == "browser" && clipboard.saves == 0, "Builtin-search copy doesn't save an unfinished function")
            type(store, KeyCode.leftCommand)
            store.cancelEditInProgress()
            expect(store.root.actions.isEmpty && clipboard.saves == 0, "Cancelling the builtin command menu preserves the saved graph")
        }
        print("Text clipboard and command menu: \(checks) checks passed")
    }
}
