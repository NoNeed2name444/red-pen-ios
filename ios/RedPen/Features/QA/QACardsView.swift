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
            StudyProgressHeader(headerStatus, detail: headerDetail,
                                fraction: Double(index + 1) / Double(max(1, cards.count)))
            ScrollView {
                if let card {
                    cardView(card)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .readableColumn()
                } else {
                    FinishHero(symbol: "tray", title: "No cards yet", message: "This set has no cards.")
                        .padding(.top, 32)
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
        // Practise with a pretend patient, Check accuracy and Turn into, all
        // in the one More menu
        .studyMoreMenu(for: studySet, check: accuracyAsk) {
            Button { simulating = card } label: {
                Label("Practise with a pretend patient", systemImage: "stethoscope")
            }
            .disabled(card == nil)
        }
        .navigationTitle(studySet.subject.isEmpty ? "Cases" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $simulating) { CaseChatView(card: $0, subject: studySet.subject) }
    }

    private var headerStatus: String {
        cards.isEmpty ? "No cards" : "Card \(index + 1) of \(cards.count)"
    }

    private var headerDetail: String {
        revealed ? "Did you get it right?" : "Answer it in your head, then tap Reveal"
    }

    /// What Check accuracy looks at: the card on screen.
    private var accuracyAsk: AccuracyAsk {
        AccuracyAsk(instruction: "Write a clinical case or recall question with its answer points, from the source.") {
            card.map { ([$0.stem] + $0.answer).joined(separator: "\n") + AccuracyChecker.differentialBlock($0.differential) }
        }
    }

    private func cardView(_ card: QACard) -> some View {
        let badgeColor: Color = card.type == .case
            ? StudySetKind.qa.shifted(brightness: -0.18, saturation: 0.05)
            : StudySetKind.qa.tint
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(card.badge)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .foregroundStyle(badgeColor)
                    .background(badgeColor.opacity(0.14), in: Capsule())
                if !card.topic.isEmpty {
                    Text(card.topic).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(hl(card.stem)).font(.title3.weight(.semibold)).lineSpacing(2)
            if revealed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Answer").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(Array(card.answer.enumerated()), id: \.offset) { _, a in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}").foregroundStyle(.secondary)
                            Text(hl(a)).font(.body)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if revealed, let tiers = card.differential, !tiers.isEmpty {
                HowToReachCard(differential: tiers, lecture: lectureLabel(card))
                    .transition(.opacity)
            }
        }
        .contentCard()
    }

    /// The lecture page the card matches, for "How to reach it".
    private func lectureLabel(_ card: QACard) -> String? {
        let text: String = ([card.stem] + card.answer).joined(separator: " ")
        return HowToReachCard.lectureLabel(for: text, in: studySet)
    }

    /// Back on the left, small; Reveal, then Next, filling the rest.
    private var footer: some View {
        let last = index >= cards.count - 1
        return StudyActionBar {
            HStack(spacing: 12) {
                Button { index = max(0, index - 1); revealed = false } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bigCompanion)
                .disabled(index == 0)
                .accessibilityLabel("Previous card")

                if revealed {
                    Button {
                        if last {
                            store.clearReading(for: studySet.id)
                            dismiss()
                        } else { index += 1; revealed = false }
                    } label: {
                        Label(last ? "Done" : "Next", systemImage: last ? "checkmark" : "arrow.right")
                    }
                    .buttonStyle(.bigPrimary)
                    .keyboardShortcut(.return, modifiers: [])
                } else {
                    Button { withAnimation(.snappy) { revealed = true } } label: {
                        Label("Reveal answer", systemImage: "eye")
                    }
                    .buttonStyle(.bigPrimary)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(card == nil)
                }
            }
        }
    }

    /// `**term**` highlights, via SwiftUI's Markdown support.
    /// `**term**` highlights, and nothing else - see Highlight. A Cases card
    /// is not Markdown, and reading it as if it were quietly eats the
    /// underscores and brackets medical writing is full of.
    private func hl(_ s: String) -> AttributedString { Highlight.attributed(s) }
}
