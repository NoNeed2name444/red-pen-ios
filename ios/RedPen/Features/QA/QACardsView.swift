import SwiftUI

/// Cases mode — matches `#qaView` / `renderQaCard()`: a progress bar, the
/// topic and a Clinical case / Recall badge, the question, Reveal, then the
/// answer bullets and Previous / Next.
struct QACardsView: View {
    let studySet: StudySet
    @State private var index: Int
    @State private var revealed: Bool
    @Environment(\.dismiss) private var dismiss

    init(set studySet: StudySet, startIndex: Int = 0, startRevealed: Bool = false) {
        self.studySet = studySet
        _index = State(initialValue: startIndex)
        _revealed = State(initialValue: startRevealed)
    }

    private var cards: [QACard] { studySet.qaCards }
    private var card: QACard? { cards.indices.contains(index) ? cards[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(cards.count) card\(cards.count == 1 ? "" : "s")").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("\(index + 1) / \(cards.count)")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .liquidGlassChip()
            }
            .padding(.horizontal).padding(.top, 8)
            ProgressView(value: Double(index + 1), total: Double(max(1, cards.count)))
                .tint(.accentColor)
                .padding(.horizontal).padding(.vertical, 6)
            ScrollView {
                if let card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Text(card.badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(card.type == .case ? Color.orange.opacity(0.18) : Color.accentColor.opacity(0.14), in: Capsule())
                            if !card.topic.isEmpty { Text(card.topic).font(.caption).foregroundStyle(.secondary) }
                        }
                        Text(hl(card.stem)).font(.title3.weight(.semibold)).lineSpacing(2)
                        if revealed {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(card.answer.enumerated()), id: \.offset) { _, a in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•").foregroundStyle(.secondary)
                                        Text(hl(a))
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                    .padding(.bottom, 12)
                } else {
                    Text("No cards in this set.").foregroundStyle(.secondary).padding()
                }
            }
            footer
        }
        .navigationTitle(studySet.subject.isEmpty ? "Cases" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footer: some View {
        HStack {
            Button("Previous") { index = max(0, index - 1); revealed = false }
                .buttonStyle(.liquidGlass)
                .disabled(index == 0)
            Spacer()
            if revealed {
                Button(index >= cards.count - 1 ? "Done" : "Next") {
                    if index >= cards.count - 1 { dismiss() } else { index += 1; revealed = false }
                }
                .buttonStyle(.liquidGlassProminent())
            } else {
                Button("Reveal answer") { revealed = true }
                    .buttonStyle(.liquidGlassProminent())
                    .disabled(card == nil)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlassPanel()
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    /// `**term**` highlights, via SwiftUI's Markdown support.
    private func hl(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
