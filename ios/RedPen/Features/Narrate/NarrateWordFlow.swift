import SwiftUI

/// The transcript laid out word by word.
///
/// It used to be one Text per line, which is fine to read and useless to
/// correct: you cannot tap a word inside a Text. Every word is its own tap
/// target now - a short press jumps the player to that line, a long press
/// offers to fix the word - and the line still reads as a line because the
/// words are flowed rather than stacked.
///
/// When a recording is attached, `spokenWord` is the word the recogniser says
/// is being spoken right now, and it is marked more strongly than the line
/// around it. That is the whole point of keeping word timings: a student
/// reading along knows exactly where the lecturer is, instead of scanning a
/// highlighted paragraph for their place.
struct NarrateWordFlow: View {
    let texts: [String]
    let langs: [String]
    let currentIndex: Int
    /// The word within the current line, when a recording is driving playback.
    var spokenWord: Int?
    let onJump: (Int) -> Void
    let onFix: (FixTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(texts.indices, id: \.self) { i in
                line(i)
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .background(i == currentIndex ? Color.accentColor.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .animation(.easeInOut(duration: 0.25), value: currentIndex)
                    .id(i)
                    .environment(\.layoutDirection,
                                 (i < langs.count && langs[i] == "ar") ? .rightToLeft : .leftToRight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func line(_ i: Int) -> some View {
        let words = texts[i].split(separator: " ").map(String.init)
        FlowLayout(spacing: 4, lineSpacing: 6) {
            ForEach(words.indices, id: \.self) { w in
                let speaking = (i == currentIndex && spokenWord == w)
                Text(words[w])
                    .font(.body)
                    .foregroundStyle(i == currentIndex ? Color.accentColor : .primary)
                    .fontWeight(speaking ? .bold : (i == currentIndex ? .semibold : .regular))
                    .padding(.horizontal, speaking ? 3 : 0)
                    .background(speaking ? Color.accentColor.opacity(0.22) : .clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    // a moving highlight should glide, but not so slowly that
                    // it lags behind the voice it is tracking
                    .animation(.easeOut(duration: 0.12), value: speaking)
                    .contentShape(Rectangle())
                    .onTapGesture { onJump(i) }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        onFix(FixTarget(segment: i, word: w, heard: words[w]))
                    }
            }
        }
    }
}

/// Words wrapped the way a paragraph wraps them.
///
/// SwiftUI has no inline flow of separately tappable views, and an HStack per
/// line would need the text measured by hand. The Layout protocol does the
/// measuring properly, including when the text size changes.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                widest = max(widest, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, width == .infinity ? widest : width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
