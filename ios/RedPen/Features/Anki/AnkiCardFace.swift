import SwiftUI

/// What one card looks like, front and back.
///
/// Split out of the review screen because two screens now show a card - one
/// deck at a time, and everything due across the library - and because the
/// review screen had grown past what the SwiftUI type-checker will take in one
/// expression.
struct AnkiCardFace: View {
    let card: AnkiCard
    let images: [String]
    let revealed: Bool
    /// The lectures this set came from, so a citation can be opened rather than
    /// only read. Defaulted, because most screens showing a card have no source
    /// to offer and should not have to say so.
    var sources: [SourceDoc] = []
    var openSource: ((SourceDoc, Int) -> Void)? = nil
    /// The rest of the card's set, so an older image occlusion card - saved
    /// before cards carried their neighbours' masks - can still cover every
    /// other label on its picture.
    var deck: [AnkiCard] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(badge)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.wardPrimaryInk)

            if card.pictureOnFront { picture }

            if card.type == .cloze {
                // as Anki shows it: the sentence stays where it is, and the
                // answer appears in the gap it was hidden in
                Text(Self.clozeSentence(card.clozeText, revealed: revealed))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.wardInk)
                    .accessibilityLabel(Self.clozeSpoken(card.clozeText, revealed: revealed))
            } else {
                Text(front)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.wardInk)
            }

            if revealed {
                // the answer opens under the question, as Anki shows a card's
                // back below its front: nothing turns over, the question stays
                // where it was read (a cloze fills its gap in place instead)
                VStack(alignment: .leading, spacing: 14) {
                    if card.type != .cloze {
                        WardEtch()
                    }
                    back
                    if !card.pictureOnFront { picture }
                    if !card.why.trimmingCharacters(in: .whitespaces).isEmpty {
                        why
                    }
                }
                .transition(reduceMotion ? .opacity
                            : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }

            citation
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: revealed)
        .clipped()
    }

    /// Where this card came from.
    ///
    /// A tap opens the lecture at that page when we still have it - the point
    /// of recording a citation in the first place, since a card that looks
    /// wrong is only worth checking if checking is one tap rather than a hunt
    /// through a slide deck. When the source is gone it stays what it always
    /// was: a line of text saying where to look.
    @ViewBuilder
    private var citation: some View {
        if let label = card.source, !label.isEmpty {
            if let found = Citation.resolve(label, in: sources), let openSource {
                Button {
                    openSource(found.source, found.page)
                } label: {
                    Label(label, systemImage: "doc.text.magnifyingglass")
                        .font(.footnote)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.wardPrimaryInk)
                .accessibilityHint("Opens the lecture at \(found.source.kind.pageNoun.lowercased()) \(found.page)")
            } else {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(Color.wardInkSecondary)
            }
        }
    }

    /// The card's picture: an occlusion card's with its covers, any other
    /// card's as it came (audit #14 - imported basic and cloze cards kept
    /// theirs but never showed them).
    @ViewBuilder
    private var picture: some View {
        if let idx = card.imageIndex,
           images.indices.contains(idx),
           let uiImage = Self.pictures.picture(for: images[idx], make: { UIImage(data: $0) }) {
            if card.type == .occlusion {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: uiImage).resizable().scaledToFit()
                        covers(size: geo.size)
                    }
                }
                .aspectRatio(uiImage.size, contentMode: .fit)
                .frame(maxHeight: 280)
            } else {
                Image(uiImage: uiImage).resizable().scaledToFit()
                    .frame(maxHeight: 280)
                    .accessibilityLabel("Picture on the card")
            }
        }
    }

    /// Every tested label on the picture, covered.
    ///
    /// The one this card asks about is orange with a "?"; the rest are a flat
    /// grey and stay put when the card is revealed, so only the answer comes
    /// off. Covers are fully opaque, grown past the glyphs and snapped outward
    /// to whole points, so no letter shows through or round an edge. Once
    /// revealed, the answer's place is outlined in the same orange.
    private func covers(size: CGSize) -> some View {
        let frame = CGRect(origin: .zero, size: size)
        let others = OcclusionCovers.others(for: card, in: deck)
        let target = card.occlusion
        let isRevealed = revealed
        // the covers keep their own opaque colours, matched to the exported
        // masks (OcclusionCovers), so they hide labels on any photo
        let grey = Color(red: OcclusionCovers.otherRGB.red,
                         green: OcclusionCovers.otherRGB.green,
                         blue: OcclusionCovers.otherRGB.blue)
        let orange = Color(red: OcclusionCovers.targetRGB.red,
                           green: OcclusionCovers.targetRGB.green,
                           blue: OcclusionCovers.targetRGB.blue)
        return Canvas { context, _ in
            for box in others {
                let rect = OcclusionCovers.rect(for: box, in: frame, padding: OcclusionCovers.drawPadding,
                                                   minimum: OcclusionCovers.drawMinimum)
                guard rect.width > 0, rect.height > 0 else { continue }
                context.fill(Path(rect), with: .color(grey))
            }
            guard let target else { return }
            let rect = OcclusionCovers.rect(for: target, in: frame, padding: OcclusionCovers.drawPadding,
                                                   minimum: OcclusionCovers.drawMinimum)
            guard rect.width > 0, rect.height > 0 else { return }
            if isRevealed {
                context.stroke(Path(rect), with: .color(orange), lineWidth: 2)
            } else {
                context.fill(Path(rect), with: .color(orange))
                let mark = Text("?")
                    .font(.system(size: max(9, min(rect.height * 0.7, 22)), weight: .bold))
                    .foregroundColor(.white)
                context.draw(mark, at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var back: some View {
        switch card.type {
        case .qa:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{2022}")
                        Text(Self.highlighted(bullet))
                    }
                }
            }
        case .cloze:
            // filled in where it stood, in the sentence above: nothing to repeat
            EmptyView()
        case .occlusion:
            // the mask simply disappears from the picture above; the answer is
            // the label it was covering, which is now readable
            if let answer = card.bullets.first {
                Text(Self.highlighted(answer)).font(.body.weight(.medium))
            }
        }
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Why / how").wardSmallCaps().accessibilityAddTraits(.isHeader)
            Text(card.why).font(.body).lineSpacing(2).foregroundStyle(Color.wardInk)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // a note pressed into the card
        .wardInset(in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous))
        .padding(.top, 4)
    }

    /// A question card's front (a cloze is drawn by clozeSentence).
    private var front: String { card.displayFront }

    private var badge: String {
        switch card.type {
        case .qa: return "Question"
        case .cloze: return "Fill in the gap"
        case .occlusion: return "What is hidden?"
        }
    }

    /// A cloze sentence with its gaps as Anki draws them: "[...]" (or the
    /// hint) in Theatre Blue until revealed, then the answer, bold and blue,
    /// in the same place.
    static func clozeSentence(_ text: String, revealed: Bool) -> AttributedString {
        var out = AttributedString()
        for piece in AnkiCard.clozePieces(text) {
            guard piece.isGap else {
                out += AttributedString(piece.text)
                continue
            }
            var gap = AttributedString(revealed ? piece.text : AnkiCard.clozeGap(piece))
            gap.foregroundColor = Color.wardPrimaryInk
            gap.inlinePresentationIntent = .stronglyEmphasized
            out += gap
        }
        return out
    }

    /// The sentence as VoiceOver reads it: "blank" (or the hint) for a gap.
    static func clozeSpoken(_ text: String, revealed: Bool) -> String {
        AnkiCard.clozePieces(text).map { piece in
            guard piece.isGap, !revealed else { return piece.text }
            return piece.hint.map { "blank, hint: \($0)" } ?? "blank"
        }.joined()
    }

    /// `**term**` markers become real bold; SwiftUI's Text reads Markdown.
    static func highlighted(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    /// Pictures decoded once, not on every redraw (audit #67).
    private static let pictures = PictureCache<UIImage>()

    /// An image may be stored bare or as a full data: URI, depending on where
    /// it came from.
    static func stripDataPrefix(_ s: String) -> String {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return s }
        return String(s[s.index(after: comma)...])
    }
}

/// What sits in a card screen's bottom bar: Reveal while the card is face
/// down, then the four ratings.
///
/// Shared by the one-deck screen and Due today. `companion` is an optional
/// small button at the leading end of the Reveal row (Due today's Listen);
/// Reveal itself is the screen's one main button and sits at the trailing
/// end, under the right thumb. Give it to `.studyBar { }`, so the card
/// scrolls under the glass.
struct AnkiFooter<Companion: View>: View {
    let revealed: Bool
    /// When each rating would bring the card back ("1m", "4d").
    let labels: [AnkiRating: String]
    let onReveal: () -> Void
    let onRate: (AnkiRating) -> Void
    private let companion: Companion
    private let hasCompanion: Bool

    @Environment(\.windowSpan) private var span

    init(revealed: Bool, labels: [AnkiRating: String], onReveal: @escaping () -> Void,
         onRate: @escaping (AnkiRating) -> Void, @ViewBuilder companion: () -> Companion) {
        self.revealed = revealed
        self.labels = labels
        self.onReveal = onReveal
        self.onRate = onRate
        self.companion = companion()
        self.hasCompanion = true
    }

    var body: some View {
        if revealed {
            AnkiRatingBar(labels: labels, onRate: onRate)
        } else {
            HStack(spacing: 12) {
                if hasCompanion {
                    companion
                    // on a wide iPad the companion goes to the left hand
                    if span == .broad { Spacer(minLength: 16) }
                }
                revealButton
            }
        }
    }

    private var revealButton: some View {
        Button(action: onReveal) {
            Text("Reveal")
        }
        .buttonStyle(.bigPrimary)
        // Space turns the card over, as it does in Anki
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityHint("Shows the answer. Say it to yourself first.")
    }
}

extension AnkiFooter where Companion == EmptyView {
    /// Reveal on its own, filling the bar.
    init(revealed: Bool, labels: [AnkiRating: String], onReveal: @escaping () -> Void,
         onRate: @escaping (AnkiRating) -> Void) {
        self.revealed = revealed
        self.labels = labels
        self.onReveal = onReveal
        self.onRate = onRate
        self.companion = EmptyView()
        self.hasCompanion = false
    }
}

/// The four ratings after a card is turned over, as big buttons with plain
/// words: Again, Hard, Good, Easy.
///
/// Shared by the one-deck screen and Due today, so the two cannot drift
/// apart. Each speaks in its tone - Again Resus Red, Hard Caution Amber,
/// Good Discharge Green, Easy Theatre Blue - with when it comes back in SF
/// Mono. Good is the filled one, because it is the answer most cards get
/// and the one a thumb should find without looking; the other three are the
/// quiet version of the same button.
///
/// On a phone they sit two by two, big enough to hit without looking; in any
/// wider window, one row of four, Again to Easy from left to right like the
/// 1 to 4 keys that press them.
///
/// For the first few cards anybody rates, each button also says what it
/// means in a few words ("I forgot it"), and a line above asks the question
/// the buttons answer. After that the hints step aside - they are for
/// learning the buttons, not for reading every time - though VoiceOver keeps
/// saying them always.
struct AnkiRatingBar: View {
    /// When each rating would bring the card back ("1m", "4d").
    let labels: [AnkiRating: String]
    let onRate: (AnkiRating) -> Void

    /// How many cards have been rated while the hints were showing.
    @AppStorage("anki.ratingHintsShown") private var hintsShown = 0
    private static let hintCards = 5
    @Environment(\.windowSpan) private var span

    var body: some View {
        let hints: Bool = hintsShown < Self.hintCards
        let oneRow: Bool = span > .slim
        VStack(spacing: 12) {
            if hints {
                Text("How well did you remember it?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.wardInkSecondary)
            }
            if oneRow {
                HStack(spacing: 12) {
                    button(.again, hints: hints)
                    button(.hard, hints: hints)
                    button(.good, hints: hints)
                    button(.easy, hints: hints)
                }
            } else {
                HStack(spacing: 12) {
                    button(.again, hints: hints)
                    button(.hard, hints: hints)
                }
                HStack(spacing: 12) {
                    button(.good, hints: hints)
                    button(.easy, hints: hints)
                }
            }
        }
    }

    @ViewBuilder
    private func button(_ rating: AnkiRating, hints: Bool) -> some View {
        let when: String = labels[rating] ?? ""
        let key: Int = (AnkiRating.allCases.firstIndex(of: rating) ?? 9) + 1
        let action: () -> Void = {
            if hintsShown < Self.hintCards { hintsShown += 1 }
            onRate(rating)
        }
        let label = VStack(spacing: 2) {
            Text(Self.title(rating))
            if hints {
                Text(Self.meaning(rating)).font(.footnote)
            }
            if !when.isEmpty {
                HStack(spacing: 3) {
                    Text("back").font(.caption)
                    Text(when)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        Button(action: action) { label }
            .buttonStyle(AnkiRatingButtonStyle(tone: Self.tone(rating), filled: rating == .good))
            // 1 to 4, Again to Easy - Anki's own keys
            .numberKey(key)
            .accessibilityHint(Self.meaning(rating))
    }

    static func tone(_ rating: AnkiRating) -> WardTone {
        switch rating {
        case .again: return .danger
        case .hard: return .warning
        case .good: return .green
        case .easy: return .blue
        }
    }

    static func title(_ rating: AnkiRating) -> String {
        switch rating {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    /// What each button means, in the student's words rather than Anki's.
    static func meaning(_ rating: AnkiRating) -> String {
        switch rating {
        case .again: return "I forgot it"
        case .hard: return "I just about got it"
        case .good: return "I got it"
        case .easy: return "Too easy"
        }
    }
}

/// A rating button: a soft tile raised off the base, its words in the
/// rating's tone, never a fill. The one to press most (`filled`) says its
/// word in bold. Held, it is pressed into the base.
private struct AnkiRatingButtonStyle: ButtonStyle {
    let tone: WardTone
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        AnkiRatingFace(label: configuration.label, pressed: configuration.isPressed,
                       tone: tone, bold: filled)
    }
}

private struct AnkiRatingFace: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let tone: WardTone
    let bold: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.button, style: .continuous)
        let lift: WardLift = .mid
        let font: Font = bold ? .headline.weight(.bold) : .headline
        label
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(tone.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background { WardReliefFace(shape: shape, lift: pressed ? lift.lower : lift, inset: pressed) }
            .contentShape(shape)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: pressed)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
    }
}
