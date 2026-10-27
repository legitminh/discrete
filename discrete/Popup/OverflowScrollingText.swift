import AppKit
import SwiftUI

/// Keeps Text's intrinsic layout/compression behavior, then draws a clipped
/// marquee only when that allocated width is smaller than the full name.
struct OverflowScrollingText: View {
    let text: String
    let font: NSFont
    let charactersPerSecond: Double
    var truncationMode: Text.TruncationMode = .tail

    @State private var startedAt = Date()

    private var textWidth: CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    var body: some View {
        // A hidden Text, rather than a greedy GeometryReader, preserves the
        // natural split between short labels and their secondary detail.
        Text(text)
            .font(Font(font))
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    let timing = OverflowScrollTiming(
                        textWidth: textWidth, visibleWidth: geometry.size.width,
                        characterCount: text.count, charactersPerSecond: charactersPerSecond
                    )
                    Group {
                        if timing.isScrolling {
                            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                                HStack(spacing: timing.gap) {
                                    copy
                                    copy
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .offset(x: -timing.offset(at: context.date.timeIntervalSince(startedAt)))
                            }
                        } else {
                            Text(text)
                                .font(Font(font))
                                .lineLimit(1)
                                .truncationMode(truncationMode)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .onChange(of: geometry.size.width) { startedAt = Date() }
                }
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .onChange(of: text) { startedAt = Date() }
            .onChange(of: charactersPerSecond) { startedAt = Date() }
            .onChange(of: font) { startedAt = Date() }
    }

    private var copy: some View {
        Text(text)
            .font(Font(font))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
