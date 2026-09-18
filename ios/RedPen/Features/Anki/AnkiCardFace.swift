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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(badge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .textCase(.uppercase)

            picture

            Text(front)
                .font(.title3.weight(.semibold))

            if revealed {
                back
                if !card.why.trimmingCharacters(in: .whitespaces).isEmpty {
                    why
                }
            }

            citation
        }
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
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityHint("Opens the lecture at \(found.source.kind.pageNoun.lowercased()) \(found.page)")
            } else {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var picture: some View {
        if card.type == .occlusion, let idx = card.imageIndex,
           images.indices.contains(idx),
           let data = Data(base64Encoded: Self.stripDataPrefix(images[idx])),
           let uiImage = UIImage(data: data) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Image(uiImage: uiImage).resizable().scaledToFit()
                    if !revealed, let occ = card.occlusion {
                        Rectangle()
                            .fill(Color.black.opacity(0.85))
                            .frame(width: occ.w * geo.size.width,
                                   height: occ.h * geo.size.height)
                            .offset(x: occ.x * geo.size.width, y: occ.y * geo.size.height)
                    }
                }
            }
            .aspectRatio(uiImage.size, contentMode: .fit)
            .frame(maxHeight: 280)
        }
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
            // the same regex as the front face, with the term shown in bold
            Text(Self.highlighted(card.clozeText.replacingOccurrences(
                of: #"\{\{c\d+::([^}:]+)(::[^}]*)?\}\}"#,
                with: "**$1**", options: .regularExpression)))
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
            Text("Why / how").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(card.why).font(.subheadline).lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 4)
    }

    private var front: String {
        guard card.type == .cloze else { return card.displayFront }
        return card.clozeText.replacingOccurrences(
            of: #"\{\{c\d+::([^}:]+)(::[^}]*)?\}\}"#,
            with: "\u{25A2}\u{25A2}\u{25A2}", options: .regularExpression)
    }

    private var badge: String {
        switch card.type {
        case .qa: return "Question & answer"
        case .cloze: return "Cloze deletion"
        case .occlusion: return "Image occlusion"
        }
    }

    /// `**term**` markers become real bold; SwiftUI's Text reads Markdown.
    static func highlighted(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    /// An image may be stored bare or as a full data: URI, depending on where
    /// it came from.
    static func stripDataPrefix(_ s: String) -> String {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return s }
        return String(s[s.index(after: comma)...])
    }
}
