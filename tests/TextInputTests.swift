import AppKit
@testable import discrete

/// Uses a temporary in-memory graph. The optional GUI checks send key-downs
/// directly to the popup and never change the system clipboard.
@main struct TextInputTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() {
        let settings = UserSettings()
        let root = DiscreteState(name: "test")
        let child = DiscreteState(name: "Project 123", parent: root)
        root.actions[KeyCode.c] = .transition(child)
        var saves = 0
        let store = DiscreteGraphStore(settings: settings, root: root, saveGraph: { _ in saves += 1 })
        let one = KeyCode.digits[0]
        func rows() -> [OverlayRow] { OverlayRowBuilder.build(for: root, mode: store.mode).rows }

        store.handleTap(KeyList.reservedSlots(for: root).search!)
        let searchID = store.mode.textDraft!.id
        store.updateText("Project 123", draftID: searchID)
        expect(rows().contains { $0.label == "Project 123" && $0.symbol.isEmpty }, "Typing previews results without digit shortcuts")
        store.handleTap(one)
        expect(store.mode.textDraft?.text == "Project 123", "A suggestion cannot run while the query is editable")
        store.handleTextCommand(.confirm, draftID: searchID)
        expect(rows().first?.label == "return to typing", "Escape is the first action after confirming")
        expect(rows().contains { $0.label == "Project 123" && $0.symbol == KeyList.symbol(for: one) }, "Confirm enables suggestion keys")
        store.updateText("discard this", draftID: searchID)
        store.handleTap(KeyCode.escape)
        expect(store.mode.textDraft?.id == searchID && store.mode.textDraft?.text == "Project 123", "Escape restores the same query")
        store.handleTextCommand(.confirm, draftID: searchID)
        store.handleTap(one)
        expect(store.currentState === child, "A confirmed digit opens the displayed suggestion")

        store.enterRoot()
        store.handleTap(KeyList.reservedSlots(for: root).configure!)
        store.handleTap(KeyList.ConfigureSlots.nameState)
        let nameID = store.mode.textDraft!.id
        store.updateText("A1", draftID: nameID)
        store.handleTextCommand(.confirm, draftID: nameID)
        expect(saves == 0 && root.name == "test", "Confirmation must not save the name")
        store.handleTap(KeyCode.escape)
        store.updateText("A2", draftID: nameID)
        store.handleTextCommand(.confirm, draftID: nameID)
        store.handleTap(KeyCode.enter)
        expect(saves == 1 && root.name == "A2", "Save commits the corrected draft once")

        store.handleTap(KeyList.ConfigureSlots.addFunction)
        store.handleTap(KeyList.AddFunctionSlots.builtin)
        store.handleTap(KeyCode.v)
        let functionID = store.mode.textDraft!.id
        store.updateText("test builtin", draftID: functionID)
        store.handleTextCommand(.confirm, draftID: functionID)
        store.handleTap(KeyCode.enter)
        guard case .selectingBuiltin(let request) = store.mode else { fatalError("Expected builtin picker") }
        store.handleTap(KeyList.builtinFolderSlots(for: request.folder).system!)
        let builtinID = store.mode.textDraft!.id
        store.updateText("search", draftID: builtinID)
        store.handleTap(one)
        expect(store.mode.textDraft?.id == builtinID, "Builtin suggestions also wait for confirmation")
        store.handleTextCommand(.confirm, draftID: builtinID)
        store.handleTap(one)
        expect(root.actions[KeyCode.v]?.name == "test builtin" && saves == 2, "Choosing a confirmed builtin finishes adding it")

        print("Text input phases: passed")
        if CommandLine.arguments.contains("--gui") { checkNativeField(store, settings: settings) }
    }

    static func checkNativeField(_ store: DiscreteGraphStore, settings: UserSettings) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let popup = PopupWindowController()
        popup.onTextChanged = { store.updateText($0, draftID: $1) }
        popup.onTextCommand = { store.handleTextCommand($0, draftID: $1) }
        store.onStateChanged = {
            popup.show(OverlayRowBuilder.build(for: store.currentState, mode: store.mode), settings: settings)
        }
        defer { store.onStateChanged = nil; popup.hide() }

        func key(_ code: CGKeyCode, _ characters: String, flags: CGEventFlags = []) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.flags = flags
            let units = Array(characters.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            popup.handleKeyDown(NSEvent(cgEvent: event)!)
        }

        store.handleTap(KeyList.reservedSlots(for: store.root).search!)
        key(0, "A", flags: .maskShift)
        key(KeyCode.digits[0], "1")
        key(KeyCode.leftArrow, "\u{F702}", flags: .maskShift)
        key(11, "B", flags: .maskShift)
        expect(store.mode.textDraft?.text == "AB", "Native typing, selection, and replacement must reach the query")
        key(KeyCode.leftArrow, "\u{F702}", flags: .maskShift)
        key(KeyCode.enter, "\r")
        expect(store.mode.textDraft?.isTyping == false, "Native Return must confirm")
        store.handleTap(KeyCode.escape)
        key(KeyCode.digits[1], "2")
        expect(store.mode.textDraft?.text == "A2", "The selection must survive confirming and returning to typing")
        key(0, "a", flags: .maskCommand)
        key(KeyCode.digits[2], "3")
        expect(store.mode.textDraft?.text == "3", "Command-A must select the native draft for replacement")
        key(KeyCode.escape, "\u{1B}")
        expect(store.mode.textDraft == nil, "Native Escape while typing must exit search")
        print("Native field key handling: passed")
    }
}
