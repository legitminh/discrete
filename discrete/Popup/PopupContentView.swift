import SwiftUI

/// Renders whatever content it's given, Raycast-style: the state's name
/// as a header, then its rows below. Knows nothing about the graph,
/// modes, or what triggered it.
struct PopupContentView: View {
    let content: OverlayContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(content.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(content.rows) { row in
                    HStack(spacing: 12) {
                        Text(row.symbol)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .frame(width: 24, alignment: .center)
                        Text(row.label)
                            .font(.system(size: 14))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        )
    }
}

#Preview {
    PopupContentView(content: OverlayContent(title: "home", rows: [
        OverlayRow(symbol: "C", label: "state with 0 actions"),
        OverlayRow(symbol: "⌫", label: "settings"),
        OverlayRow(symbol: "⇪", label: "exit discrete")
    ]))
    .padding(40)
    .background(Color.gray)
}
