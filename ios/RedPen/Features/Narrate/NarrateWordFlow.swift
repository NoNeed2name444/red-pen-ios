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
    @Environment(\.modeTint) private var modeTint
    let texts: [String]
    let langs: [String]
    let currentIndex: Int
    /// The word within the current line being spoken right now.
    var spokenWord: Int?
    /// Where each line sits in the scroll view, for the auto-scroll's band.
    var band: NarrateScrollBand?
    let onJump: (Int) -> Void
    let onFix: (FixTarget) -> Void

    var body: some View {
        // Lazy, and one Equatable view per line: a word moving on rebuilds
        // the one line it is in, not a lecture's worth of flowed words.
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(texts.indices, id: \.self) { i in
                let current: Bool = i == currentIndex
                NarrateLine(index: i, text: texts[i],
                            rtl: i < langs.count && langs[i] == "ar",
                            current: current,
                            spoken: current ? spokenWord : nil,
                            tint: modeTint,
                            band: band, onJump: onJump, onFix: onFix)
                    .equatable()
                    .id(i)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line of the transcript.
///
/// The spoken word is marked by colour and a background drawn OUTSIDE its
/// frame, never by a bolder weight or extra padding: either of those makes
/// the word wider, the line re-wraps, and every word after it shuffles
/// sideways three times a second. That shuffle was most of the "choppy".
struct NarrateLine: View, Equatable {
    let index: Int
    let text: String
    let rtl: Bool
    let current: Bool
    let spoken: Int?
    let tint: Color
    let band: NarrateScrollBand?
    let onJump: (Int) -> Void
    let onFix: (FixTarget) -> Void

    /// What the line shows. The closures and the band never change what is
    /// drawn, so they are left out and SwiftUI skips every line but the one
    /// whose highlight moved.
    nonisolated static func == (a: NarrateLine, b: NarrateLine) -> Bool {
        a.index == b.index && a.text == b.text && a.rtl == b.rtl
            && a.current == b.current && a.spoken == b.spoken && a.tint == b.tint
    }

    var body: some View {
        let words: [String] = text.split(separator: " ").map(String.init)
        let ink: Color = current ? tint : Color.primary
        let lit: Color = current ? tint.opacity(0.14) : Color.clear
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        FlowLayout(spacing: 4, lineSpacing: 6) {
            ForEach(words.indices, id: \.self) { w in
                word(words[w], at: w, ink: ink)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(lit, in: shape)
        // a pointer lights the whole line, which is what a click jumps to;
        // one modifier per line, not one per word
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.highlight)
        .animation(.easeInOut(duration: 0.2), value: current)
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(NarrateScrollBand.space))
        } action: { frame in
            band?.frames[index] = frame
        }
        .onDisappear { band?.frames[index] = nil }
    }

    private func word(_ text: String, at w: Int, ink: Color) -> some View {
        let speaking: Bool = spoken == w
        let mark: Color = speaking ? tint.opacity(0.24) : Color.clear
        return Text(text)
            .font(.body)
            .foregroundStyle(ink)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(mark)
                    .padding(.horizontal, -3)
                    .padding(.vertical, -1)
            }
            // quick enough to keep up with the voice, slow enough to glide
            .animation(.easeOut(duration: 0.1), value: speaking)
            .contentShape(Rectangle())
            .onTapGesture { onJump(index) }
            .onLongPressGesture(minimumDuration: 0.35) {
                onFix(FixTarget(segment: index, word: w, heard: text))
            }
    }
}

/// Where the lines are, kept out of SwiftUI's state on purpose: writing a
/// frame here on every scrolled frame must not rebuild anything. The screen
/// reads it only when the line changes, to decide whether to scroll.
@MainActor
final class NarrateScrollBand {
    nonisolated static let space = "narrate.scroll"

    var frames: [Int: CGRect] = [:]
    var viewport: CGFloat = 0
    /// While the student is scrolling, and for a moment after, the transcript
    /// is theirs: the auto-scroll does not pull it back.
    var handsOffUntil = Date.distantPast

    /// The current line is left where it is while it sits comfortably in the
    /// upper-middle of the screen; only when it leaves that band is the
    /// transcript moved - instead of re-centring on every line.
    func needsScroll(to line: Int) -> Bool {
        guard Date() >= handsOffUntil, viewport > 0 else { return false }
        guard let frame = frames[line] else { return true }
        let top: CGFloat = viewport * 0.12
        let bottom: CGFloat = viewport * 0.72
        return frame.minY < top || frame.maxY > bottom
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
