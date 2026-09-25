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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .studyBar { footer(due) }
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
        // commute mode reads questions as well as due cards, so Listen
        // stays in reach with nothing due
        .studyBar { emptyBar }
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
        let interval: Double = reviews.records[due.card.id]?.intervalMin ?? 0
        let labels: [AnkiRating: String] = AnkiScheduler.previewLabels(currentIntervalMin: interval)
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
    }
}
