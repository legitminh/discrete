import Foundation
import CoreGraphics
@testable import discrete

/// Link against the Debug module. The injected root and save callback keep
/// every graph in memory: these checks never load or alter the user's graph.
@main struct FunctionUpdateTests {
    final class Saves { var count = 0 }
    struct Fixture {
        let store: DiscreteGraphStore
        let root: DiscreteState
        let function: DiscreteFunction
        let trigger: CGKeyCode
        let saves: Saves
    }

    static let originalURL = URL(fileURLWithPath: "/tmp/original.app")
    static let replacementURL = URL(fileURLWithPath: "/tmp/replacement.sh")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func fixture(trigger: CGKeyCode = 11, target: FunctionTarget = .file(originalURL)) -> Fixture {
        let root = DiscreteState(name: "test root")
        let function = DiscreteFunction(name: "original", target: target)
        root.actions[trigger] = .function(function)
        root.actions[8] = .transition(DiscreteState(name: "child", parent: root))
        let saves = Saves()
        let store = DiscreteGraphStore(settings: UserSettings(), root: root, saveGraph: { _ in saves.count += 1 })
        store.onRunFile = { _ in fatalError("Updating a function must not run it") }
        return Fixture(store: store, root: root, function: function, trigger: trigger, saves: saves)
    }

    static func configure(_ store: DiscreteGraphStore) {
        store.handleTap(KeyList.reservedSlots(for: store.currentState).configure!)
        guard case .configuring = store.mode else { fatalError("Expected configure menu") }
    }

    static func beginUpdate(_ f: Fixture) {
        configure(f.store)
        let menu = OverlayRowBuilder.build(for: f.root, mode: f.store.mode)
        expect(menu.rows.contains { $0.label == "update function" }, "The configure menu must offer update function")
        f.store.handleTap(KeyList.ConfigureSlots.updateFunction)
        // A state transition must never select a function.
        f.store.handleTap(8)
        guard case .pickingFunction(.update) = f.store.mode else { fatalError("State transitions must not be selectable") }
        let selection = KeyList.functionSelectionKeys(for: f.root).first { $0.value == f.trigger }!.key
        f.store.handleTap(selection)
        guard case .choosingFunctionKind(.update(let selected)) = f.store.mode else { fatalError("Expected update kind selection") }
        expect(selected === f.function, "The existing function identity must be retained")
    }

    static func typed(_ store: DiscreteGraphStore, code: CGKeyCode = 0, text: String = "") {
        store.handleTyped(TypedKey(keyCode: code, flags: [], characters: text))
    }

    static func name(_ f: Fixture, replacement: String? = nil) {
        guard case .editingText(let request) = f.store.mode else { fatalError("Expected name editor") }
        expect(request.buffer.text == "original", "Updating must prefill the existing name")
        if let replacement {
            for _ in request.buffer.text { typed(f.store, code: KeyCode.delete) }
            typed(f.store, text: replacement)
        }
        typed(f.store, code: KeyCode.enter)
    }

    static func chooseBuiltin(_ store: DiscreteGraphStore, id: String) {
        guard case .selectingBuiltin(let request) = store.mode else { fatalError("Expected builtin picker") }
        let key = KeyList.builtinFolderSlots(for: request.folder).entries.first { _, entry in
            if case .function(let function) = entry { return function.id == id }
            return false
        }!.key
        store.handleTap(key)
    }

    static func unchanged(_ f: Fixture) {
        expect(f.function.name == "original", "Cancellation must preserve the existing name")
        guard case .file(let url) = f.function.target else { fatalError("Cancellation must preserve the existing target") }
        expect(url == originalURL && f.saves.count == 0, "Cancelled updates must not persist")
        guard case .function(let bound) = f.root.actions[f.trigger] else { fatalError("The original trigger must remain") }
        expect(bound === f.function && f.root.actions.count == 2, "Updating must not rebind or duplicate functions")
    }

    static func main() {
        do {
            let f = fixture()
            beginUpdate(f)
            f.store.handleTap(KeyList.AddFunctionSlots.resource)
            name(f, replacement: "updated")
            unchanged(f)
            f.store.completeFileSelect(replacementURL)
            guard case .file(let url) = f.function.target else { fatalError("Expected resource target") }
            expect(url == replacementURL && f.function.name == "updated" && f.saves.count == 1, "Resource update must save atomically")
            expect(f.root.actions.count == 2, "An update must not add a trigger")
        }
        do {
            let f = fixture()
            beginUpdate(f)
            f.store.handleTap(KeyList.AddFunctionSlots.builtin)
            name(f)
            chooseBuiltin(f.store, id: "toggle-full-screen")
            guard case .builtin(let id, let argument) = f.function.target else { fatalError("Expected builtin replacement") }
            expect(id == "toggle-full-screen" && argument == nil && f.saves.count == 1, "File-to-builtin update must work")
        }
        do {
            let f = fixture()
            beginUpdate(f)
            f.store.handleTap(KeyList.AddFunctionSlots.builtin)
            name(f, replacement: "website")
            chooseBuiltin(f.store, id: "open-website")
            unchanged(f)
            typed(f.store, text: "https://example.com")
            typed(f.store, code: KeyCode.enter)
            guard case .builtin(let id, let argument) = f.function.target else { fatalError("Expected argument-taking builtin") }
            expect(id == "open-website" && argument == "https://example.com" && f.function.name == "website" && f.saves.count == 1,
                   "Builtin name, target and argument must commit together")
        }
        do {
            let f = fixture(target: .builtin(id: "removed-builtin", argument: "old"))
            beginUpdate(f)
            f.store.handleTap(KeyList.AddFunctionSlots.resource)
            name(f)
            f.store.completeFileSelect(replacementURL)
            guard case .file(let url) = f.function.target else { fatalError("Missing builtins must be replaceable with resources") }
            expect(url == replacementURL && f.saves.count == 1, "Builtin-to-resource update must work")
        }
        for stage in 0..<7 {
            let f = fixture()
            beginUpdate(f)
            if stage == 0 {
                f.store.handleTap(KeyCode.escape) // Kind selection.
            } else {
                f.store.handleTap(stage >= 4 ? KeyList.AddFunctionSlots.builtin : KeyList.AddFunctionSlots.resource)
                if stage == 1 {
                    typed(f.store, text: " draft")
                    typed(f.store, code: KeyCode.escape)
                } else {
                    name(f, replacement: "draft")
                    if stage == 2 { f.store.completeFileSelect(nil) }
                    if stage == 3 {
                        f.store.cancelEditInProgress()
                        f.store.completeFileSelect(replacementURL) // Late picker completion after exit.
                    }
                    if stage == 4 { f.store.handleTap(KeyCode.escape) }
                    if stage >= 5 {
                        chooseBuiltin(f.store, id: "open-website")
                        typed(f.store, text: "draft argument")
                        if stage == 5 { typed(f.store, code: KeyCode.escape) }
                        else { f.store.cancelEditInProgress() }
                    }
                }
            }
            unchanged(f)
            guard case .navigating = f.store.mode else { fatalError("Cancellation must return to the state") }
        }
        do {
            let f = fixture(trigger: 9999)
            beginUpdate(f)
            f.store.handleTap(KeyList.AddFunctionSlots.resource)
            name(f)
            f.store.completeFileSelect(replacementURL)
            guard case .function(let function) = f.root.actions[9999] else { fatalError("Disconnected trigger must stay unchanged") }
            expect(function === f.function && f.saves.count == 1, "Stand-in selection must update the original binding")
        }
        do {
            let root = DiscreteState(name: "empty")
            let store = DiscreteGraphStore(settings: UserSettings(), root: root, saveGraph: { _ in fatalError("No change expected") })
            configure(store)
            expect(!OverlayRowBuilder.build(for: root, mode: store.mode).rows.contains { $0.label == "update function" }, "Hide update when there are no functions")
            store.handleTap(KeyList.ConfigureSlots.updateFunction)
            guard case .configuring = store.mode else { fatalError("The reserved update key must be inert without functions") }
        }
        do {
            let f = fixture()
            configure(f.store)
            f.store.handleTap(KeyList.ConfigureSlots.addFunction)
            f.store.handleTap(KeyList.AddFunctionSlots.builtin)
            let trigger = KeyList.assignableKeys.first { f.root.actions[$0] == nil }!
            f.store.handleTap(trigger)
            typed(f.store, text: "new function")
            typed(f.store, code: KeyCode.enter)
            chooseBuiltin(f.store, id: "search")
            expect(f.root.actions.count == 3 && f.saves.count == 1 && f.function.name == "original", "Shared setup must preserve normal adding")
        }
        print("Function updating: resource/builtin replacement, cancellation, stand-in triggers, menu visibility, and add-flow regression passed")
    }
}
