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
        case .namingState(let buffer):
            return [
                OverlayRow(symbol: "✎", label: "naming: \(buffer)"),
                OverlayRow(symbol: KeyList.capsLockSymbol, label: "save name")
            ]

        case .settingArguments:
            return [
                OverlayRow(symbol: "?", label: "press a key to bind a new action"),
                OverlayRow(symbol: KeyList.capsLockSymbol, label: "cancel")
            ]

        case .navigating:
            var rows: [OverlayRow] = []

            for (keyCode, child) in state.children.sorted(by: { $0.key < $1.key }) {
                let label = child.name ?? "state with \(child.children.count) actions"
                rows.append(OverlayRow(symbol: KeyList.symbol(for: keyCode), label: label))
            }

            let reserved = KeyList.reservedSlots(for: state)
            if let name = reserved.name {
                rows.append(OverlayRow(symbol: name.symbol, label: "set state name"))
            }
            if let arguments = reserved.arguments {
                rows.append(OverlayRow(symbol: arguments.symbol, label: "set node arguments"))
            }
            if let back = reserved.back {
                rows.append(OverlayRow(symbol: back.symbol, label: "return to previous state"))
            }
            if let pickScript = reserved.pickScript {
                rows.append(OverlayRow(symbol: pickScript.symbol, label: "pick a script to run"))
            }

            rows.append(OverlayRow(symbol: KeyList.capsLockSymbol, label: "exit discrete"))
            return rows
        }
    }
}
