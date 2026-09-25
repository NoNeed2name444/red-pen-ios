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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSpan) private var span

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
    /// When Undo stops being offered; nil while it is not.
    @State private var undoUntil: Date?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let current {
                cardScroll(current)
            } else {
                finishScroll
            }
        }
        .modeScreen(.anki)
        // Quiz me, Check accuracy and Turn into, all in the one More menu
        .studyMoreMenu(for: studySet, check: accuracyAsk) {
            Button(action: buildQuiz) {
                Label("Quiz me", systemImage: "list.bullet.rectangle")
            }
            .disabled(studySet.cards.count < 5)
            if current != nil {
                Button(action: buryCurrent) {
                    Label("Bury until tomorrow", systemImage: "moon.zzz")
                }
                Button(action: suspendCurrent) {
                    Label("Suspend this card", systemImage: "pause.circle")
                }
            }
        }
        .navigationTitle(studySet.subject.isEmpty ? "Cards" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startSitting)
        .navigationDestination(item: $quizSet) { set in MCQQuizView(set: set, keepsProgress: false) }
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

    /// What Check accuracy looks at: the card on screen.
    private var accuracyAsk: AccuracyAsk {
        AccuracyAsk(instruction: "Write a flashcard (question and answer) from the source.",
                    item: { current.flatMap { AccuracyItem.card($0.card) } }) {
            current.map { item -> String in
                let c = item.card
                let parts: [String] = [c.front, c.clozeText] + c.bullets + [c.why]
                return parts.filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
    }

    // MARK: the empty states, which say different things

    @ViewBuilder
    private var nothingDue: some View {
        if studySet.cards.isEmpty {
            FinishHero(symbol: "tray", title: "No cards yet",
                       message: "This deck has no cards.")
        } else if reviewedCount > 0 {
            FinishHero(symbol: "checkmark.seal.fill", title: "Done for now", message: doneLine)
        } else {
            FinishHero(symbol: "clock", title: "Nothing to review",
                       message: "No cards in this deck are due yet. " + nextLine)
        }
    }

    /// The card, scrolling under the bar that turns it over and rates it.
    private func cardScroll(_ item: AnkiQueueItem) -> some View {
        ScrollView {
            AnkiCardFace(card: item.card, images: studySet.images,
                         revealed: revealed,
                         sources: studySet.sources,
                         openSource: { source, page in
                             reading = SourceOpening(source: source, page: page)
                         },
                         deck: studySet.cards)
                .contentCard()
                .cardFlip(revealed: revealed, enabled: !startRevealed)
                .reviewCardActions(onBury: buryCurrent, onSuspend: suspendCurrent)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, revealed ? 8 : 24)
                .readableColumn()
            // turned over: the card's accuracy, and why
            if revealed {
                HStack {
                    AccuracyBadge(set: studySet, itemID: item.card.id.uuidString)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .readableColumn()
            }
        }
        .reviewUndoChip(until: $undoUntil, action: undo)
        .studyBar { footer(item) }
    }

    /// The finish: what happened, the way to a quiz on the same cards, and
    /// the bar with the one thing to do next.
    private var finishScroll: some View {
        ScrollView {
            VStack(spacing: 16) {
                nothingDue
                // Quiz me needs five cards to find wrong answers among
                if studySet.cards.count >= 5 { quizMeButton }
            }
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .reviewUndoChip(until: $undoUntil, action: undo)
        .studyBar { finishButtons }
        // a streak of a week, finished here, is a good moment to ask once
        .reviewPromptAfterStreak(reviewedCount > 0)
    }

    /// The deck as a quiz, under the finish - the same as More's Quiz me.
    private var quizMeButton: some View {
        Button(action: buildQuiz) {
            Label("Quiz me on this deck", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(.bigSecondary)
        .accessibilityHint("A quiz whose wrong answers come from the other cards in this deck")
    }

    /// Study ahead when nothing is due and nothing was done, with Done beside
    /// it; otherwise Done alone.
    @ViewBuilder
    private var finishButtons: some View {
        if !studySet.cards.isEmpty && reviewedCount == 0 {
            HStack(spacing: 12) {
                Button("Done") { dismiss() }
                    .buttonStyle(.bigCompanion)
                if span == .broad { Spacer(minLength: 16) }
                Button("Study it anyway") { studyAhead() }
                    .buttonStyle(.bigPrimary)
                    .keyboardShortcut(.return, modifiers: [])
            }
        } else {
            Button("Done") { dismiss() }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    /// "You went through 12 cards. Next card back in 10 minutes."
    private var doneLine: String {
        let plural: String = reviewedCount == 1 ? "" : "s"
        let first: String = "You went through \(reviewedCount) card\(plural). "
        return first + nextLine
    }

    private var nextLine: String {
        guard let next = reviews.nextDue(for: studySet.cards), next > Date() else {
            return "Everything here has been seen."
        }
        let minutes = next.timeIntervalSinceNow / 60
        return "Next card back in " + AnkiScheduler.formatInterval(minutes) + "."
    }

    private var header: some View {
        let left = queue.count
        let done = reviewedCount
        let status: String = left == 0 ? "All done" : "\(left) card\(left == 1 ? "" : "s") left"
        let detail: String = "\(done) done" + (studyingAhead ? " \u{00B7} studying ahead" : "")
        let fraction: Double = Double(done) / Double(max(1, done + left))
        return StudyProgressHeader(status, detail: detail, fraction: fraction)
    }

    /// Reveal, then the four ratings, always in the same place.
    private func footer(_ item: AnkiQueueItem) -> some View {
        // from the card's stored standing, so studying ahead promises what
        // an early rating will actually store
        let kept: ReviewRecord = ReviewPlan.record(for: item.card, in: reviews.records)
        let labels: [AnkiRating: String] = ReviewPlan.previewLabels(for: kept, now: Date(),
                                                                    exam: ExamCap.storedDate(),
                                                                    scheduler: ReviewSettings.scheduler())
        return AnkiFooter(revealed: revealed, labels: labels,
                          onReveal: {
                              revealed = true
                              SpaceFeedback.play(.reveal)
                          },
                          onRate: { rate($0) })
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
        // Again is a miss; Hard, Good and Easy were remembered
        SpaceFeedback.play(rating == .again ? .wrong : .correct)
        let kept = reviews.rate(rating, card: item.card)
        StudyLog.shared.record()
        reviewedCount += 1
        queue.removeAll { $0.id == item.id }
        if kept.intervalMin <= Self.sittingMinutes {
            queue.append(AnkiQueueItem(card: item.card, due: kept.due,
                                       intervalMin: kept.intervalMin))
        }
        undoUntil = Date().addingTimeInterval(5)
        showNext()
    }

    /// Takes the last rating back: the card returns to the front, question
    /// side up, and its schedule is as it was.
    private func undo() {
        undoUntil = nil
        guard let last = reviews.undoLast(),
              let card = studySet.cards.first(where: { $0.id == last.cardID }) else { return }
        queue.removeAll { $0.id == card.id }
        let before: ReviewRecord = ReviewPlan.record(for: card, in: reviews.records)
        let back = AnkiQueueItem(card: card, due: .distantPast, intervalMin: before.intervalMin)
        queue.insert(back, at: 0)
        reviewedCount = max(0, reviewedCount - 1)
        current = back
        revealed = false
    }

    private func buryCurrent() {
        guard let item = current else { return }
        reviews.bury(item.card)
        leaveSitting(item)
    }

    private func suspendCurrent() {
        guard let item = current else { return }
        reviews.suspend(item.card)
        leaveSitting(item)
    }

    /// A card buried or suspended leaves this sitting at once.
    private func leaveSitting(_ item: AnkiQueueItem) {
        undoUntil = nil
        queue.removeAll { $0.id == item.id }
        showNext()
    }

    /// A quiz whose wrong answers are the right answers to other cards in this
    /// deck. Nothing is generated and nothing is sent anywhere: the options are
    /// text these cards already contain, which is what stops a quiz being
    /// easier than the deck it came from.
    private func buildQuiz() {
        let built = QuizFromCards.build(from: studySet.cards)
        guard built.questions.count >= 3 else {
            let reasons: [String] = Array(Set(built.skipped.map(\.why)).sorted().prefix(2))
            let count: Int = built.questions.count
            let plural: String = count == 1 ? "" : "s"
            let why: String = reasons.joined(separator: " ")
            quizNote = "This deck made \(count) usable question\(plural). \(why)"
            return
        }
        var set = studySet
        set.questions = built.questions
        set.kind = .mcq
        quizSet = set
    }
}
