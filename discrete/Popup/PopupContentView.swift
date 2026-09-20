import SwiftUI

/// The visual content of the popup. Knows nothing about why it's being
/// shown — it just renders whatever text it's given, Raycast-style.
struct PopupContentView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 32)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.1))
            )
    }
}

#Preview {
    PopupContentView(text: "Hello")
        .padding(40)
        .background(Color.gray)
}
