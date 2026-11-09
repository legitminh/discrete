import SwiftUI

/// Shared by the SwiftUI rows and the native field placed in the first row.
enum PopupLayout {
    static let padding: CGFloat = 16
    static let sectionSpacing: CGFloat = 10
    static let titleHeight: CGFloat = 16
    static let contextHeight: CGFloat = 14
    static let rowHeight: CGFloat = 22
    static let rowSpacing: CGFloat = 8
    static let symbolWidth: CGFloat = 24
    static let symbolSpacing: CGFloat = 12

    static func rowsTop(hasContext: Bool) -> CGFloat {
        padding + titleHeight + sectionSpacing + (hasContext ? contextHeight + sectionSpacing : 0)
    }
}

/// Renders whatever content it's given, Raycast-style: the state's name
/// as a header (plus which configure screen, if any), then its rows below. Knows nothing about the graph,
/// modes, or what triggered it.
struct PopupContentView: View {
    let content: OverlayContent
    @ObservedObject var settings: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: PopupLayout.sectionSpacing) {
            // The state's name exactly as typed; an empty name is a blank line.
            OverflowScrollingText(text: content.title.isEmpty ? " " : content.title,
                                  font: .systemFont(ofSize: 13, weight: .semibold),
                                  charactersPerSecond: settings.overflowScrollRate)
                .foregroundStyle(.white.opacity(0.6))
                .frame(height: PopupLayout.titleHeight)

            if let context = content.context {
                OverflowScrollingText(text: context, font: .systemFont(ofSize: 12),
                                      charactersPerSecond: settings.overflowScrollRate)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(height: PopupLayout.contextHeight)
            }

            VStack(alignment: .leading, spacing: PopupLayout.rowSpacing) {
                ForEach(content.rows) { row in
                    HStack(spacing: PopupLayout.symbolSpacing) {
                        Text(row.symbol)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .frame(minWidth: PopupLayout.symbolWidth, alignment: .center)
                        if !row.isTextField {
                            OverflowScrollingText(text: row.label, font: .systemFont(ofSize: 14),
                                                  charactersPerSecond: settings.overflowScrollRate)
                        }
                        if let detail = row.detail {
                            OverflowScrollingText(text: detail, font: .systemFont(ofSize: 12),
                                                  charactersPerSecond: settings.overflowScrollRate,
                                                  truncationMode: .middle)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: PopupLayout.rowHeight)
                    .opacity(row.isUnavailable ? 0.4 : 1)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(PopupLayout.padding)
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
    ]), settings: UserSettings())
    .padding(40)
    .background(Color.gray)
}
