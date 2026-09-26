import SwiftUI

/// Cases mode — matches `#qaView` / `renderQaCard()`: a progress bar, the
/// topic and a Clinical case / Recall badge, the question, Reveal, then the
/// answer bullets and Previous / Next.
struct QACardsView: View {
    let studySet: StudySet
    @State private var index: Int
    @State private var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSpan) private var span
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
            StudyProgressHeader(headerStatus, detail: headerDetail, fraction: headerFraction)
            cardScroll
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

    private var headerFraction: Double {
        Double(index + 1) / Double(max(1, cards.count))
    }

    /// The card, scrolling under the bar.
    private var cardScroll: some View {
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
        .studyBar { footer }
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
                Spacer(minLength: 4)
                // revealed: the case's accuracy, and why
                if revealed { AccuracyBadge(set: studySet, itemID: card.id.uuidString) }
            }
            Text(hl(card.stem)).font(.title3.weight(.semibold)).lineSpacing(2)
            if revealed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Answer").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
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
                .transition(.slideFade(.bottom))
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

    /// Back on the left, small; Reveal, then Next, at the trailing end - and
    /// once the answer is showing, the patient from this case beside them.
    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: goBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bigCompanion)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(index == 0)
            .accessibilityLabel("Previous card")

            if revealed && card != nil { patientButton }

            if span == .broad { Spacer(minLength: 16) }

            if revealed {
                nextButton
            } else {
                Button(action: reveal) {
                    Label("Reveal answer", systemImage: "eye")
                }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(card == nil)
            }
        }
    }

    /// Next, or Done on the last card. Return presses it; so does the right
    /// arrow, until the last card.
    private var nextButton: some View {
        let last: Bool = index >= cards.count - 1
        let title: String = last ? "Done" : "Next"
        let symbol: String = last ? "checkmark" : "arrow.right"
        return Button(action: goNext) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.return, modifiers: [])
        .background {
            if !last { QAExtraKey(key: .rightArrow, action: goNext) }
        }
    }

    /// Talk it through with the patient in this case - the same as More's
    /// "Practise with a pretend patient". Words when there is room for them,
    /// the stethoscope alone on a phone.
    private var patientButton: some View {
        Button { simulating = card } label: {
            ViewThatFits(in: .horizontal) {
                Label("Talk to the patient", systemImage: "stethoscope")
                Image(systemName: "stethoscope")
            }
        }
        .buttonStyle(.bigCompanion)
        .accessibilityLabel("Talk to the patient")
        .accessibilityHint("Opens this case as a patient you can question")
    }

    /// Shows the answer, and reads it out: the button VoiceOver was on has
    /// just become Next.
    private func reveal() {
        withAnimation(Motion.gentle(.snappy)) { revealed = true }
        guard let card else { return }
        let points: String = card.answer.joined(separator: ". ").replacingOccurrences(of: "**", with: "")
        Announce.say(points.isEmpty ? "Answer shown." : "Answer: " + points)
    }

    private func goBack() {
        index = max(0, index - 1)
        revealed = false
    }

    private func goNext() {
        if index >= cards.count - 1 {
            store.clearReading(for: studySet.id)
            dismiss()
        } else {
            index += 1
            revealed = false
        }
    }

    /// `**term**` highlights, via SwiftUI's Markdown support.
    /// `**term**` highlights, and nothing else - see Highlight. A Cases card
    /// is not Markdown, and reading it as if it were quietly eats the
    /// underscores and brackets medical writing is full of.
    private func hl(_ s: String) -> AttributedString { Highlight.attributed(s) }
}

/// A second key for a button that already has one: an invisible button that
/// does the same thing, since a button takes only one keyboard shortcut.
private struct QAExtraKey: View {
    let key: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear.frame(width: 1, height: 1)
        }
        .keyboardShortcut(key, modifiers: [])
        .buttonStyle(.plain)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
