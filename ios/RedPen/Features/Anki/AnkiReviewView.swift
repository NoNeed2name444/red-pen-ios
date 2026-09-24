import SwiftUI

/// The review screen for one deck.
///
/// Two things are going on at once and they used to be the same thing. A
/// SITTING is what happens while this screen is open: "Again" should hand the
/// card back a minute later, before you leave. The SCHEDULE is what survives
/// the screen, and it now does - a card rated Easy is gone for four days, not
/// until the next time the deck is opened.
///
/// So a rating does both: it is written to the ReviewStore, and if the new
/// interval is short enough to fall inside this sitting the card stays in the
/// queue. Anything scheduled further out leaves.
struct AnkiReviewView: View {
    let studySet: StudySet
    /// Only used by the CI screenshot launch to open on the back of a card.
    var startRevealed: Bool = false

    init(set studySet: StudySet, startRevealed: Bool = false) {
        self.studySet = studySet
        self.startRevealed = startRevealed
    }

    @EnvironmentObject var store: Store
    @EnvironmentObject var reviews: ReviewStore

    /// Cards whose next appearance is this close still come back before you
    /// put the phone down; further out and the sitting is over for them.
    private static let sittingMinutes: Double = 20

    @State private var queue: [AnkiQueueItem] = []
    @State private var current: AnkiQueueItem?
    @State private var revealed = false
    @State private var reviewedCount = 0
    @State private var studyingAhead = false
    @State private var quizSet: StudySet?
    /// The lecture page a citation asked for, if one is open.
    @State private var reading: SourceOpening?
    @State private var quizNote: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let current {
                ScrollView {
                    AnkiCardFace(card: current.card, images: studySet.images,
                                 revealed: revealed,
                                 sources: studySet.sources,
                                 openSource: { source, page in
                                     reading = SourceOpening(source: source, page: page)
                                 })
                        .contentCard()
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                        .readableColumn()
                }
                Spacer(minLength: 0)
                footer(current)
            } else {
                Spacer()
                nothingDue
                Spacer()
            }
        }
        .modeScreen(.anki)
        .navigationTitle(studySet.subject.isEmpty ? "Cards" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startSitting)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: buildQuiz) {
                    Label("Quiz me", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.glass)
                .disabled(studySet.cards.count < 5)
            }
        }
        .navigationDestination(item: $quizSet) { set in MCQQuizView(set: set) }
        .accuracyCheck(set: studySet,
                       instruction: "Write a flashcard (question and answer) from the source.") {
            current.map { item -> String in
                let c = item.card
                return ([c.front, c.clozeText] + c.bullets + [c.why])
                    .filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
        // A sheet rather than a push: checking the slide is a glance in the
        // middle of a review, and the card underneath should still be there
        // when it closes.
        .sheet(item: $reading) { opening in
            SourcePreviewView(source: opening.source, set: studySet, openAt: opening.page)
        }
        .alert("Not enough to quiz on", isPresented: Binding(
            get: { quizNote != nil }, set: { if !$0 { quizNote = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(quizNote ?? "")
        }
    }

    // MARK: the two empty states, which say different things

    @ViewBuilder
    private var nothingDue: some View {
        VStack(spacing: 12) {
            if studySet.cards.isEmpty {
                Text("This deck has no cards.").foregroundStyle(.secondary)
            } else if reviewedCount > 0 {
                Text("Done for now.").font(.headline)
                Text(nextLine).font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Nothing due in this deck.").font(.headline)
                Text(nextLine).font(.footnote).foregroundStyle(.secondary)
                Button("Study it anyway") { studyAhead() }
                    .buttonStyle(.glass)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private var nextLine: String {
        guard let next = reviews.nextDue(for: studySet.cards), next > Date() else {
            return "Everything here has been seen."
        }
        let minutes = next.timeIntervalSinceNow / 60
        return "Next card back in " + AnkiScheduler.formatInterval(minutes) + "."
    }

    private var header: some View {
        HStack {
            Text("\(queue.count) card\(queue.count == 1 ? "" : "s") left"
                 + (studyingAhead ? " (studying ahead)" : ""))
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Text("\(reviewedCount) reviewed")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .liquidGlassChip()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    @ViewBuilder
    private func footer(_ item: AnkiQueueItem) -> some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if !revealed {
                    Button { revealed = true } label: {
                        Text("Reveal").frame(maxWidth: .infinity).padding(.vertical, 2)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    let labels = AnkiScheduler.previewLabels(currentIntervalMin: item.intervalMin)
                    HStack(spacing: 8) {
                        rateButton(.again, labels[.again] ?? "", color: StudySetKind.anki.step(0))
                        rateButton(.hard, labels[.hard] ?? "", color: StudySetKind.anki.step(1))
                        rateButton(.good, labels[.good] ?? "", color: StudySetKind.anki.step(2))
                        rateButton(.easy, labels[.easy] ?? "", color: StudySetKind.anki.step(3))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func rateButton(_ rating: AnkiRating, _ subtitle: String, color: Color) -> some View {
        Button { rate(rating) } label: {
            VStack(spacing: 2) {
                Text(rating.rawValue.capitalized).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption2).opacity(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.glass).tint(color)
    }

    // MARK: the sitting

    private func startSitting() {
        guard queue.isEmpty, current == nil else { return } // a return from the quiz is not a new sitting
        queue = reviews.queue(for: studySet.cards)
        reviewedCount = 0
        showNext()
        if startRevealed { revealed = true }
    }

    private func studyAhead() {
        studyingAhead = true
        queue = reviews.everything(studySet.cards)
        showNext()
    }

    private func showNext() {
        queue.sort { $0.due < $1.due }
        current = queue.first
        revealed = false
    }

    private func rate(_ rating: AnkiRating) {
        guard let item = current else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        let kept = reviews.rate(rating, card: item.card)
        reviewedCount += 1
        queue.removeAll { $0.id == item.id }
        if kept.intervalMin <= Self.sittingMinutes {
            queue.append(AnkiQueueItem(card: item.card, due: kept.due,
                                       intervalMin: kept.intervalMin))
        }
        showNext()
    }

    /// A quiz whose wrong answers are the right answers to other cards in this
    /// deck. Nothing is generated and nothing is sent anywhere: the options are
    /// text these cards already contain, which is what stops a quiz being
    /// easier than the deck it came from.
    private func buildQuiz() {
        let built = QuizFromCards.build(from: studySet.cards)
        guard built.questions.count >= 3 else {
            let reasons = Set(built.skipped.map(\.why)).sorted().prefix(2)
            quizNote = "This deck made \(built.questions.count) usable question"
                + (built.questions.count == 1 ? "" : "s") + ". "
                + (reasons.isEmpty ? "" : reasons.joined(separator: " "))
            return
        }
        var set = studySet
        set.questions = built.questions
        set.kind = .mcq
        quizSet = set
    }
}
