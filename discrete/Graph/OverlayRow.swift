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
            return OverlayContent(title: "rename", rows: [
                OverlayRow(symbol: "✎", label: "naming: \(buffer)"),
                OverlayRow(symbol: KeyList.capsLockSymbol, label: "save name")
            ])

        case .namingNewLeaf(_, let buffer):
            return OverlayContent(title: "name this action", rows: [
                OverlayRow(symbol: "✎", label: "naming: \(buffer)"),
                OverlayRow(symbol: KeyList.capsLockSymbol, label: "save name")
            ])

        case .configuring:
            var rows: [OverlayRow] = []
            let slots = KeyList.configureSlots(for: state)
            if let s = slots.addState {
                rows.append(OverlayRow(symbol: s.symbol, label: "add state"))
            }
            if let s = slots.addAction {
                rows.append(OverlayRow(symbol: s.symbol, label: "add an action"))
            }
            if let s = slots.renameAction {
                rows.append(OverlayRow(symbol: s.symbol, label: "rename an action"))
            }
            if let s = slots.setTrigger {
                rows.append(OverlayRow(symbol: s.symbol, label: "set an action trigger"))
            }
            if let s = slots.deleteAction {
                rows.append(OverlayRow(symbol: s.symbol, label: "delete action"))
            }
            if let s = slots.deleteState {
                rows.append(OverlayRow(symbol: s.symbol, label: "delete this state"))
            }
            if let s = slots.renameState {
                rows.append(OverlayRow(symbol: s.symbol, label: "rename this state"))
            }
            rows.append(OverlayRow(symbol: KeyList.capsLockSymbol, label: "cancel"))
            return OverlayContent(title: displayName(of: state), rows: rows)

        case .addingState, .addingAction:
            return OverlayContent(title: displayName(of: state), rows: [
                OverlayRow(symbol: "?", label: "create new action"),
                OverlayRow(symbol: KeyList.capsLockSymbol, label: "cancel")
            ])

        case .pickingAction(let purpose):
            // "list of actions" (spec, twice) — not children in general,
            // so plain sub-states made via "add state" don't show up here.
            var rows: [OverlayRow] = []
            for (keyCode, child) in orderedChildren(of: state) where child.scriptURL != nil {
                rows.append(OverlayRow(symbol: KeyList.symbol(for: keyCode), label: displayName(of: child)))
            }
            rows.append(OverlayRow(symbol: KeyList.capsLockSymbol, label: "cancel"))
            return OverlayContent(title: title(for: purpose), rows: rows)

        case .pickingNewTrigger(_, let target):
            return OverlayContent(title: "set an action trigger", rows: [
                OverlayRow(symbol: "?", label: "press new trigger key for \(displayName(of: target))"),
                OverlayRow(symbol: KeyList.capsLockSymbol, label: "cancel")
            ])

        case .navigating:
            var rows: [OverlayRow] = []
            for (keyCode, child) in orderedChildren(of: state) {
                rows.append(OverlayRow(symbol: KeyList.symbol(for: keyCode), label: displayName(of: child)))
            }

            let reserved = KeyList.reservedSlots(for: state)
            if let back = reserved.back {
                rows.append(OverlayRow(symbol: back.symbol, label: "return to previous state"))
            }
            if let configure = reserved.configure {
                rows.append(OverlayRow(symbol: configure.symbol, label: "configure"))
            }

            rows.append(OverlayRow(symbol: KeyList.capsLockSymbol, label: "exit discrete"))
            return OverlayContent(title: displayName(of: state), rows: rows)
        }
    }

    private static func title(for purpose: ActionPickerPurpose) -> String {
        switch purpose {
        case .rename: return "rename an action"
        case .setTrigger: return "set an action trigger"
        case .delete: return "delete action"
        }
    }

    private static func orderedChildren(of state: DiscreteState) -> [(key: CGKeyCode, value: DiscreteState)] {
        state.children.sorted { KeyList.displayOrder(of: $0.key) < KeyList.displayOrder(of: $1.key) }
    }

    private static func displayName(of state: DiscreteState) -> String {
        state.name ?? "state with \(state.children.count) actions"
    }
}
