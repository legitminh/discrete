import CoreGraphics
import Foundation

struct OverlayRow: Identifiable {
    let id = UUID()
    let symbol: String
    let label: String
    /// Secondary text after the label (where a search suggestion lives).
    var detail: String?
    /// A binding whose key isn't on any connected keyboard right now.
    var isUnavailable = false
}

struct OverlayContent {
    /// The state's name exactly as typed — may be empty.
    let title: String
    /// Which configure sub-state or editor is showing, if not state.? itself.
    let context: String?
    let rows: [OverlayRow]
    /// Room for search suggestions' locations.
    var isWide = false
}

/// Turns a graph state + mode into what the spec describes: the state's
/// name as the top line, then one row per available action, "[input's
/// symbol] {what it does}," sorted by key list order, with the CapsLock
/// row always last.
enum OverlayRowBuilder {
    private struct KeyedRow {
        let keyCode: CGKeyCode
        let label: String
        /// A function whose builtin this version no longer ships.
        var isTargetMissing = false
    }

    private static let unavailableNote = "(key not connected)"
    private static let missingBuiltinNote = "(builtin not available)"

    static func build(for state: DiscreteState, mode: DiscreteMode) -> OverlayContent {
        let (context, rows) = contextAndRows(for: state, mode: mode)
        let exitRow = OverlayRow(symbol: KeyList.capsLockSymbol, label: "exit discrete")
        var title = state.name
        var isSearching = false
        switch mode {
        case .searching:
            isSearching = true
        case .selectingBuiltin(let request):
            // state.builtin_select's top line is the folder being browsed.
            title = request.folder.name
        case .searchingBuiltins:
            title = BuiltinToolkit.root.name
            isSearching = true
        default:
            break
        }
        return OverlayContent(title: title, context: context, rows: rows + [exitRow], isWide: isSearching)
    }

    private static func contextAndRows(for state: DiscreteState, mode: DiscreteMode) -> (String?, [OverlayRow]) {
        switch mode {
        case .navigating:
            var keyed = state.actions.map { key, action in
                var isTargetMissing = false
                if case .function(let function) = action { isTargetMissing = function.isTargetMissing }
                return KeyedRow(keyCode: key, label: action.name, isTargetMissing: isTargetMissing)
            }
            let reserved = KeyList.reservedSlots(for: state)
            if let configure = reserved.configure {
                keyed.append(KeyedRow(keyCode: configure, label: "configure"))
            }
            if let back = reserved.back {
                keyed.append(KeyedRow(keyCode: back, label: "return to previous state"))
            }
            if let search = reserved.search {
                keyed.append(KeyedRow(keyCode: search, label: "search"))
            }
            return (nil, sorted(keyed))

        case .configuring:
            typealias Slots = KeyList.ConfigureSlots
            var keyed = [
                KeyedRow(keyCode: Slots.nameState, label: "name this state"),
                KeyedRow(keyCode: Slots.newState, label: "new state"),
                KeyedRow(keyCode: Slots.addFunction, label: "add a function"),
                KeyedRow(keyCode: KeyCode.escape, label: "end config")
            ]
            if state.parent != nil {
                keyed.append(KeyedRow(keyCode: Slots.deleteState, label: "delete this state"))
            }
            if state.hasFunctions {
                keyed += [
                    KeyedRow(keyCode: Slots.deleteFunction, label: "delete a function"),
                    KeyedRow(keyCode: Slots.renameFunction, label: "rename a function"),
                    KeyedRow(keyCode: Slots.setFunctionTrigger, label: "set function trigger"),
                    KeyedRow(keyCode: Slots.updateFunction, label: "update function")
                ]
            }
            return ("configure", sorted(keyed))

        case .confirmingDelete:
            let key = KeyList.symbol(for: KeyList.ConfigureSlots.deleteState)
            let count = state.descendantCount
            let what = "\(quoted(state.name)) and \(count) sub-state\(count == 1 ? "" : "s")"
            return ("delete this state", [
                OverlayRow(symbol: key, label: "tap again to delete \(what)"),
                OverlayRow(symbol: "…", label: "any other key: keep it")
            ])

        case .addingState:
            return ("new state", [
                OverlayRow(symbol: "?", label: "action trigger"),
                escapeRow("exit")
            ])

        case .choosingFunctionKind(let setup):
            typealias Slots = KeyList.AddFunctionSlots
            return (setup.title, sorted([
                KeyedRow(keyCode: Slots.resource, label: "choose resource to activate (script/app/open file)"),
                KeyedRow(keyCode: Slots.builtin, label: "choose builtin function"),
                KeyedRow(keyCode: KeyCode.escape, label: "exit")
            ]))

        case .addingFunction:
            return ("add a function", [
                OverlayRow(symbol: "?", label: "function trigger"),
                escapeRow("exit")
            ])

        case .pickingFunction(let purpose):
            // Selected by their own trigger, or by a stand-in key when the
            // trigger isn't connected (see KeyList.functionSelectionKeys).
            let functions = KeyList.functionSelectionKeys(for: state).compactMap { selectKey, trigger -> KeyedRow? in
                guard case .function(let function)? = state.actions[trigger] else { return nil }
                let note = selectKey == trigger ? "" : " — on \(KeyList.symbol(for: trigger)) \(unavailableNote)"
                return KeyedRow(keyCode: selectKey, label: function.name + note)
            }
            return (title(for: purpose), sorted(functions) + [escapeRow("exit")])

        case .pickingNewTrigger(_, let function):
            return ("set function trigger", [
                OverlayRow(symbol: "?", label: "new trigger for \(quoted(function.name))"),
                escapeRow("exit")
            ])

        case .editingText(let request):
            return (request.prompt, [
                OverlayRow(symbol: "✎", label: request.buffer.displayText),
                OverlayRow(symbol: KeyList.symbol(for: KeyCode.enter), label: "save"),
                escapeRow("cancel")
            ])

        case .selectingFile(let request):
            return (request.prompt, [
                OverlayRow(symbol: "📄", label: "choose in the file picker"),
                escapeRow("cancel")
            ])

        case .searching(let session):
            // Each suggestion is opened by its rank's digit key.
            let suggestions = session.results.enumerated().map { rank, result in
                let symbol = rank < KeyCode.digits.count ? KeyList.symbol(for: KeyCode.digits[rank]) : ""
                return OverlayRow(symbol: symbol, label: result.name, detail: result.detail)
            }
            return ("search", [OverlayRow(symbol: "🔍", label: session.buffer.displayText)] + suggestions + [escapeRow("exit")])

        case .selectingBuiltin(let request):
            let slots = KeyList.builtinFolderSlots(for: request.folder)
            var keyed = slots.entries.map { KeyedRow(keyCode: $0.key, label: $0.value.name) }
            if let system = slots.system {
                let label = request.folder.parent == nil ? "search builtin functions" : "return to previous folder"
                keyed.append(KeyedRow(keyCode: system, label: label))
            }
            return (request.prompt, sorted(keyed) + [escapeRow("cancel")])

        case .searchingBuiltins(let session):
            let suggestions = session.results.enumerated().map { rank, result in
                let symbol = rank < KeyCode.digits.count ? KeyList.symbol(for: KeyCode.digits[rank]) : ""
                return OverlayRow(symbol: symbol, label: result.name, detail: result.detail)
            }
            return ("search builtin functions", [OverlayRow(symbol: "🔍", label: session.buffer.displayText)] + suggestions + [escapeRow("exit")])
        }
    }

    /// Key-list order. A binding on a key that isn't connected is kept
    /// and shown, dimmed and marked, until its keyboard is back.
    private static func sorted(_ rows: [KeyedRow]) -> [OverlayRow] {
        rows.sorted { KeyList.displayOrder(of: $0.keyCode) < KeyList.displayOrder(of: $1.keyCode) }
            .map { row in
                let notes = [
                    KeyList.isAvailable(row.keyCode) ? nil : unavailableNote,
                    row.isTargetMissing ? missingBuiltinNote : nil
                ].compactMap { $0 }
                guard notes.isEmpty else {
                    let label = ([row.label] + notes).joined(separator: " ")
                    return OverlayRow(symbol: KeyList.symbol(for: row.keyCode), label: label, isUnavailable: true)
                }
                return OverlayRow(symbol: KeyList.symbol(for: row.keyCode), label: row.label)
            }
    }

    private static func escapeRow(_ label: String) -> OverlayRow {
        OverlayRow(symbol: KeyList.symbol(for: KeyCode.escape), label: label)
    }

    private static func quoted(_ name: String) -> String {
        "\"\(name)\""
    }

    private static func title(for purpose: FunctionPickerPurpose) -> String {
        switch purpose {
        case .delete: return "delete a function"
        case .rename: return "rename a function"
        case .setTrigger: return "set function trigger"
        case .update: return "update function"
        }
    }
}
