import SwiftUI

/// Cases mode — matches `#qaView` / `renderQaCard()`: a progress bar, the
/// topic and a Clinical case / Recall badge, the question, Reveal, then the
/// answer bullets and Previous / Next.
struct QACardsView: View {
    let studySet: StudySet
    @State private var index: Int
    @State private var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @State private var simulating: QACard?

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
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .liquidGlassChip()
            }
            .padding(.horizontal).padding(.top, 8)
            ThinProgress(fraction: Double(index + 1) / Double(max(1, cards.count)))
                .padding(.horizontal).padding(.vertical, 8)
            ScrollView {
                if let card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Text(card.badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundStyle(card.type == .case ? StudySetKind.qa.shifted(brightness: -0.18, saturation: 0.05) : StudySetKind.qa.tint)
                                .background((card.type == .case ? StudySetKind.qa.shifted(brightness: -0.18, saturation: 0.05) : StudySetKind.qa.tint).opacity(0.14), in: Capsule())
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
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .contentCard()
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .readableColumn()
                } else {
                    Text("No cards in this set.").foregroundStyle(.secondary).padding()
                }
            }
            footer
        }
        .onAppear {
            // Only when opened at the start: a caller that asked for a
            // particular card meant it.
            if index == 0, !revealed { index = store.reading(for: studySet.id, count: cards.count) }
        }
        .onChange(of: index) { _, now in store.saveReading(at: now, for: studySet.id) }
        .modeScreen(.qa)
        .turnIntoButton(studySet)
        .navigationTitle(studySet.subject.isEmpty ? "Cases" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { simulating = card } label: {
                    Label("Simulate patient", systemImage: "stethoscope")
                }
                .disabled(card == nil)
            }
        }
        .accuracyCheck(set: studySet,
                       instruction: "Write a clinical case or recall question with its answer points, from the source.") {
            card.map { ([$0.stem] + $0.answer).joined(separator: "\n") }
        }
        .sheet(item: $simulating) { CaseChatView(card: $0, subject: studySet.subject) }
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
        HStack {
            Button("Previous") { index = max(0, index - 1); revealed = false }
                .buttonStyle(.glass)
                .disabled(index == 0)
            Spacer()
            if revealed {
                Button(index >= cards.count - 1 ? "Done" : "Next") {
                    if index >= cards.count - 1 {
                        store.clearReading(for: studySet.id)
                        dismiss()
                    } else { index += 1; revealed = false }
                }
                .buttonStyle(.glassProminent)
            } else {
                Button("Reveal answer") { withAnimation(.snappy) { revealed = true } }
                    .buttonStyle(.glassProminent)
                    .disabled(card == nil)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    /// `**term**` highlights, via SwiftUI's Markdown support.
    /// `**term**` highlights, and nothing else - see Highlight. A Cases card
    /// is not Markdown, and reading it as if it were quietly eats the
    /// underscores and brackets medical writing is full of.
    private func hl(_ s: String) -> AttributedString { Highlight.attributed(s) }
}
