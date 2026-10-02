import SwiftUI

/// Renders whatever content it's given, Raycast-style: the state's name
/// as a header (plus which configure screen, if any), then its rows below. Knows nothing about the graph,
/// modes, or what triggered it.
struct PopupContentView: View {
    let content: OverlayContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The state's name exactly as typed; an empty name is a blank line.
            Text(content.title.isEmpty ? " " : content.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            if let context = content.context {
                Text(context)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }

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
                    .opacity(row.isUnavailable ? 0.4 : 1)
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
    PopupContentView(content: OverlayContent(title: "root", context: nil, rows: [
        OverlayRow(symbol: "⌘", label: "configure"),
        OverlayRow(symbol: "c", label: "code"),
        OverlayRow(symbol: "m", label: "mail"),
        OverlayRow(symbol: "⇪", label: "exit discrete")
    ]))
    .padding(40)
    .background(Color.gray)
}
