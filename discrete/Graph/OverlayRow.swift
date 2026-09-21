import CoreGraphics
import Foundation

struct OverlayRow: Identifiable {
    let id = UUID()
    let symbol: String
    let label: String
}

/// Turns a graph state + mode into exactly what the spec describes: one
/// row per available action, "[input's symbol] {what it does}."
enum OverlayRowBuilder {
    static func rows(for state: DiscreteState, mode: DiscreteMode) -> [OverlayRow] {
        switch mode {
        case .namingState(_, let buffer):
            return [
                OverlayRow(symbol: "✎", label: "naming: \(buffer)"),
                OverlayRow(symbol: KeyList.capsLockSymbol, label: "save name")
            ]

        case .settingActions:
            var rows: [OverlayRow] = []
            for (keyCode, child) in orderedChildren(of: state) {
                let name = child.name ?? "state with \(child.children.count) actions"
                rows.append(OverlayRow(symbol: KeyList.symbol(for: keyCode), label: "edit: \(name)"))
            }
            rows.append(OverlayRow(symbol: "?", label: "create new state"))
            rows.append(OverlayRow(symbol: KeyList.capsLockSymbol, label: "cancel"))
            return rows

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
            return rows

        case .navigating:
            var rows: [OverlayRow] = []
            for (keyCode, child) in orderedChildren(of: state) {
                let label = child.name ?? "state with \(child.children.count) actions"
                rows.append(OverlayRow(symbol: KeyList.symbol(for: keyCode), label: label))
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
            return rows
        }
    }

    private static func orderedChildren(of state: DiscreteState) -> [(key: CGKeyCode, value: DiscreteState)] {
        state.children.sorted { KeyList.displayOrder(of: $0.key) < KeyList.displayOrder(of: $1.key) }
    }
}
