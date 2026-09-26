import SwiftUI

/// Everything due right now, from every deck at once.
///
/// Twenty lectures means twenty decks, and nobody remembers which of them has
/// cards waiting. Opening each in turn to find out is the reason a schedule
/// goes unused. This asks the question the student is actually asking - what do
/// I owe today - and answers it with one queue.
///
/// Ratings go through the same ReviewStore as the per-deck screen, so a card
/// answered here is answered everywhere.
struct DueTodayView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var reviews: ReviewStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSpan) private var span

    private static let sittingMinutes: Double = 20

    @State private var queue: [ReviewPlan.Due] = []
    @State private var revealed = false
    @State private var reviewedCount = 0
    /// Commute mode, open over the queue.
    @State private var commuting = false
    /// When Undo stops being offered; nil while it is not.
    @State private var undoUntil: Date?
    /// Where the undone card came from, so it can go back in front.
    @State private var lastRated: ReviewPlan.Due?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let due = queue.first {
                dueScroll(due)
            } else {
                emptyScroll
            }
        }
        .modeScreen(.anki)
        .navigationTitle("Due today")
        .navigationBarTitleDisplayMode(.inline)
        .commuteModeSheet(isPresented: $commuting)
        .onAppear(perform: load)
    }

    /// The card due first, scrolling under the bar that reveals and rates it.
    private func dueScroll(_ due: ReviewPlan.Due) -> some View {
        withMoreMenu(cardScroll(due), for: due)
    }

    /// More, as on a deck's own review: Bury and Suspend in words, then
    /// Check accuracy and Report a problem for the card on screen. Turn
    /// into is left to the deck itself - this screen is every deck at once.
    @ViewBuilder
    private func withMoreMenu<V: View>(_ view: V, for due: ReviewPlan.Due) -> some View {
        if let set = store.library.first(where: { $0.id == due.setID }) {
            view.studyMoreMenu(for: set, turnInto: false, check: accuracyAsk(due)) {
                Button { bury(due) } label: {
                    Label("Bury until tomorrow", systemImage: "moon.zzz")
                }
                Button { suspend(due) } label: {
                    Label("Suspend this card", systemImage: "pause.circle")
                }
            }
        } else {
            view
        }
    }

    private func accuracyAsk(_ due: ReviewPlan.Due) -> AccuracyAsk {
        let card: AnkiCard = due.card
        return AccuracyAsk(instruction: "Write a flashcard (question and answer) from the source.",
                           item: { AccuracyItem.card(card) }) {
            let parts: [String] = [card.front, card.clozeText] + card.bullets + [card.why]
            return parts.filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    private func cardScroll(_ due: ReviewPlan.Due) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(due.setName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                AnkiCardFace(card: due.card, images: images(for: due),
                             revealed: revealed, deck: deck(for: due))
            }
            .contentCard()
            .cardFlip(revealed: revealed)
            .reviewCardActions(onBury: { bury(due) }, onSuspend: { suspend(due) })
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, revealed ? 8 : 24)
            .readableColumn()
            // turned over: the back kept as a note in Ideas
            if revealed, let set = store.library.first(where: { $0.id == due.setID }) {
                HStack {
                    Spacer()
                    SaveToIdeasButton(clip: SaveToIdeas.clip(card: due.card, in: set,
                                                             library: store.library))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .readableColumn()
            }
        }
        .reviewUndoChip(until: $undoUntil, action: undo)
        .studyBar { footer(due) }
        .saveToIdeasHost()
    }

    private var emptyScroll: some View {
        let symbol: String = reviewedCount > 0 ? "checkmark.seal.fill" : "clock"
        let title: String = reviewedCount > 0 ? "That's everything" : "Nothing due today"
        return ScrollView {
            FinishHero(symbol: symbol, title: title, message: emptyLine)
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .readableColumn()
        }
        .reviewUndoChip(until: $undoUntil, action: undo)
        // commute mode reads questions as well as due cards, so Listen
        // stays in reach with nothing due
        .studyBar { emptyBar }
        .reviewPromptAfterStreak(reviewedCount > 0)
    }

    private var emptyBar: some View {
        HStack(spacing: 12) {
            listenButton
            if span == .broad { Spacer(minLength: 16) }
            Button("Done") { dismiss() }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    /// Commute mode, beside Reveal (or Done): the same cards read aloud,
    /// answered by voice, for when eyes and hands are busy.
    private var listenButton: some View {
        Button { commuting = true } label: {
            Label("Listen", systemImage: "car.fill")
        }
        .buttonStyle(.bigCompanion)
        .accessibilityLabel("Listen in commute mode")
        .accessibilityHint("Reads your due cards and questions aloud and listens for the answers")
    }

    private var emptyLine: String {
        if reviewedCount == 0 {
            return "Come back when a card is ready, or open a deck and study ahead."
        }
        let plural: String = reviewedCount == 1 ? "" : "s"
        return "\(reviewedCount) card\(plural) reviewed across your decks."
    }

    private var header: some View {
        let left = queue.count
        let done = reviewedCount
        let status: String = left == 0 ? "All done" : "\(left) card\(left == 1 ? "" : "s") due"
        let fraction: Double = Double(done) / Double(max(1, done + left))
        return StudyProgressHeader(status, detail: "\(done) done", fraction: fraction)
    }

    /// Listen and Reveal, then the four ratings, always in the same place.
    private func footer(_ due: ReviewPlan.Due) -> some View {
        let kept: ReviewRecord = ReviewPlan.record(for: due.card, in: reviews.records)
        let labels: [AnkiRating: String] = ReviewPlan.previewLabels(for: kept, now: Date(),
                                                                    exam: ExamCap.storedDate(),
                                                                    scheduler: ReviewSettings.scheduler())
        return AnkiFooter(revealed: revealed, labels: labels,
                          onReveal: {
                              revealed = true
                              SpaceFeedback.play(.reveal)
                          },
                          onRate: { rate($0, due) }) {
            listenButton
        }
    }

    private func images(for due: ReviewPlan.Due) -> [String] {
        store.library.first { $0.id == due.setID }?.images ?? []
    }

    /// The card's own set, so an image occlusion card can cover the other
    /// labels on its picture.
    private func deck(for due: ReviewPlan.Due) -> [AnkiCard] {
        store.library.first { $0.id == due.setID }?.cards ?? []
    }

    private func load() {
        guard queue.isEmpty, reviewedCount == 0 else { return }
        queue = reviews.dueAcross(store.library)
        revealed = false
    }

    private func rate(_ rating: AnkiRating, _ due: ReviewPlan.Due) {
        // Again is a miss; Hard, Good and Easy were remembered
        SpaceFeedback.play(rating == .again ? .wrong : .correct)
        let kept = reviews.rate(rating, card: due.card)
        StudyLog.shared.record()
        reviewedCount += 1
        queue.removeAll { $0.id == due.id }
        if kept.intervalMin <= Self.sittingMinutes {
            // back before the phone goes down, and behind whatever else is waiting
            queue.append(ReviewPlan.Due(setID: due.setID, setName: due.setName,
                                        card: due.card, due: kept.due))
        }
        queue.sort { $0.due < $1.due }
        revealed = false
        lastRated = due
        undoUntil = Date().addingTimeInterval(5)
    }

    /// Takes the last rating back: the card returns to the front of the
    /// queue, question side up, with its schedule as it was.
    private func undo() {
        undoUntil = nil
        guard let due = lastRated, reviews.lastRating?.cardID == due.card.id else { return }
        reviews.undoLast()
        lastRated = nil
        queue.removeAll { $0.id == due.id }
        queue.insert(due, at: 0)
        reviewedCount = max(0, reviewedCount - 1)
        revealed = false
    }

    private func bury(_ due: ReviewPlan.Due) {
        reviews.bury(due.card)
        leave(due)
    }

    private func suspend(_ due: ReviewPlan.Due) {
        reviews.suspend(due.card)
        leave(due)
    }

    /// A card buried or suspended leaves the queue at once.
    private func leave(_ due: ReviewPlan.Due) {
        undoUntil = nil
        lastRated = nil
        queue.removeAll { $0.id == due.id }
        revealed = false
    }
}
