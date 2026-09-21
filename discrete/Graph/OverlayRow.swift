import CoreGraphics
import Foundation

struct OverlayRow: Identifiable {
    let id = UUID()
    let symbol: String
    let label: String
}

struct OverlayContent {
    let title: String
    let rows: [OverlayRow]
}

/// Turns a graph state + mode into exactly what the spec describes: the
/// state's name as the top line, then one row per available action below
/// it, "[input's symbol] {what it does}," sorted by key list order.
enum OverlayRowBuilder {
    static func build(for state: DiscreteState, mode: DiscreteMode) -> OverlayContent {
        switch mode {
        case .namingState(_, let buffer):
            return OverlayContent(title: "set state name", rows: [
                OverlayRow(symbol: "✎", label: "naming: \(buffer)"),
                OverlayRow(symbol: KeyList.capsLockSymbol, label: "save name")
            ])

        case .settingActions:
            var rows: [OverlayRow] = []
            for (keyCode, child) in orderedChildren(of: state) {
                rows.append(OverlayRow(symbol: KeyList.symbol(for: keyCode), label: "edit: \(displayName(of: child))"))
            }
            rows.append(OverlayRow(symbol: "?", label: "create new state"))
            rows.append(OverlayRow(symbol: KeyList.capsLockSymbol, label: "cancel"))
            return OverlayContent(title: displayName(of: state), rows: rows)

        case .editingAction(_, let target):
            var rows: [OverlayRow] = []
            let slots = KeyList.actionEditSlots(for: target)
            if let rename = slots.rename {
                rows.append(OverlayRow(symbol: rename.symbol, label: "rename"))
            }
            if let setAction = slots.setAction {
                rows.append(OverlayRow(symbol: setAction.symbol, label: "set action"))
            }
            if let delete = slots.delete {
                rows.append(OverlayRow(symbol: delete.symbol, label: "delete"))
            }
            rows.append(OverlayRow(symbol: KeyList.capsLockSymbol, label: "cancel"))
            return OverlayContent(title: "edit: \(displayName(of: target))", rows: rows)

        case .navigating:
            var rows: [OverlayRow] = []
            for (keyCode, child) in orderedChildren(of: state) {
                rows.append(OverlayRow(symbol: KeyList.symbol(for: keyCode), label: displayName(of: child)))
            }

            let reserved = KeyList.reservedSlots(for: state)
            if let back = reserved.back {
                rows.append(OverlayRow(symbol: back.symbol, label: "return to previous state"))
            }
            if let actions = reserved.actions {
                rows.append(OverlayRow(symbol: actions.symbol, label: "set node actions"))
            }
            if let name = reserved.name {
                rows.append(OverlayRow(symbol: name.symbol, label: "set state name"))
            }

            rows.append(OverlayRow(symbol: KeyList.capsLockSymbol, label: "exit discrete"))
            return OverlayContent(title: displayName(of: state), rows: rows)
        }
    }

    private static func orderedChildren(of state: DiscreteState) -> [(key: CGKeyCode, value: DiscreteState)] {
        state.children.sorted { KeyList.displayOrder(of: $0.key) < KeyList.displayOrder(of: $1.key) }
    }

    private static func displayName(of state: DiscreteState) -> String {
        state.name ?? "state with \(state.children.count) actions"
    }
}
