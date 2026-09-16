import SwiftUI

/// The review screen — matches the web app's `#ankiView`:
/// `renderAnkiCard()` for the front face, the reveal button, then
/// `el.ankiRateGrid` for the four rating buttons once revealed.
struct AnkiReviewView: View {
    let set: StudySet
    /// Only used by the CI screenshot launch (see PreviewLaunch) to open on
    /// the back of the first card.
    var startRevealed: Bool = false
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [AnkiQueueItem] = []
    @State private var current: AnkiQueueItem? = nil
    @State private var revealed: Bool = false
    @State private var reviewedCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let current {
                ScrollView {
                    cardBody(current.card)
                        .padding()
                }
                Spacer(minLength: 0)
                footer(current)
            } else {
                Spacer()
                Text("No cards to review.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle(set.subject.isEmpty ? "Anki" : set.subject)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startSession)
    }

    private var header: some View {
        HStack {
            Text("\(queue.count) card\(queue.count == 1 ? "" : "s") in this session")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(reviewedCount) reviewed")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    @ViewBuilder
    private func cardBody(_ card: AnkiCard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(badge(for: card.type))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if card.type == .occlusion, let idx = card.imageIndex, idx >= 0, idx < set.images.count,
               let data = Data(base64Encoded: stripDataPrefix(set.images[idx])),
               let uiImage = UIImage(data: data) {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: uiImage).resizable().scaledToFit()
                        if !revealed, let occ = card.occlusion {
                            Rectangle()
                                .fill(Color.black.opacity(0.85))
                                .frame(width: occ.w * geo.size.width, height: occ.h * geo.size.height)
                                .offset(x: occ.x * geo.size.width, y: occ.y * geo.size.height)
                        }
                    }
                }
                .aspectRatio(uiImage.size, contentMode: .fit)
                .frame(maxHeight: 280)
            }

            Text(front(for: card))
                .font(.title3.weight(.semibold))

            if revealed {
                back(for: card)
                if !card.why.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why / how").font(.caption.weight(.bold))
                        Text(card.why).font(.subheadline)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    @ViewBuilder
    private func back(for card: AnkiCard) -> some View {
        switch card.type {
        case .qa:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.bullets, id: \.self) { b in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(highlighted(b))
                    }
                }
            }
        case .cloze:
            // Same regex as the front face, but the term is shown (bold) —
            // matches clozeToHtml(text, true) in the web app.
            Text(highlighted(card.clozeText.replacingOccurrences(
                of: #"\{\{c\d+::([^}:]+)(::[^}]*)?\}\}"#,
                with: "**$1**",
                options: .regularExpression
            )))
        case .occlusion:
            EmptyView() // the box simply disappears from the image above
        }
    }

    private func front(for card: AnkiCard) -> String {
        switch card.type {
        case .cloze:
            // Blank out {{cN::term}} groups the way clozeToHtml(text, false) does.
            return card.clozeText.replacingOccurrences(
                of: #"\{\{c\d+::([^}:]+)(::[^}]*)?\}\}"#,
                with: "▢▢▢",
                options: .regularExpression
            )
        default:
            return card.displayFront
        }
    }

    /// `**term**` highlight markers -> plain bold-flagged text (SwiftUI
    /// Text supports simple Markdown natively).
    private func highlighted(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    private func badge(for type: AnkiCardType) -> String {
        switch type {
        case .qa: return "Question & answer"
        case .cloze: return "Cloze deletion"
        case .occlusion: return "Image occlusion"
        }
    }

    @ViewBuilder
    private func footer(_ item: AnkiQueueItem) -> some View {
        VStack(spacing: 10) {
            if !revealed {
                Button {
                    revealed = true
                } label: {
                    Text("Reveal").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            } else {
                let labels = AnkiScheduler.previewLabels(currentIntervalMin: item.intervalMin)
                HStack(spacing: 8) {
                    rateButton(.again, labels[.again] ?? "", color: .red)
                    rateButton(.hard, labels[.hard] ?? "", color: .orange)
                    rateButton(.good, labels[.good] ?? "", color: .green)
                    rateButton(.easy, labels[.easy] ?? "", color: .blue)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func rateButton(_ rating: AnkiRating, _ subtitle: String, color: Color) -> some View {
        Button {
            rate(rating)
        } label: {
            VStack(spacing: 2) {
                Text(rating.rawValue.capitalized).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption2).opacity(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private func startSession() {
        queue = AnkiScheduler.seedQueue(cards: set.cards)
        reviewedCount = 0
        showNext()
        if startRevealed { revealed = true }
    }

    private func showNext() {
        queue.sort { $0.due < $1.due }
        current = queue.first
        revealed = false
    }

    private func rate(_ rating: AnkiRating) {
        guard let item = current else { return }
        AnkiScheduler.apply(rating: rating, to: item, in: &queue)
        reviewedCount += 1
        showNext()
    }

    private func stripDataPrefix(_ s: String) -> String {
        guard let commaIdx = s.firstIndex(of: ",") , s.hasPrefix("data:") else { return s }
        return String(s[s.index(after: commaIdx)...])
    }
}
