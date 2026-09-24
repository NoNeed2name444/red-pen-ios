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

    private static let sittingMinutes: Double = 20

    @State private var queue: [ReviewPlan.Due] = []
    @State private var revealed = false
    @State private var reviewedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            if let due = queue.first {
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
                Spacer(minLength: 0)
                footer(due)
            } else {
                ScrollView {
                    FinishHero(symbol: reviewedCount > 0 ? "checkmark.seal.fill" : "clock",
                               title: reviewedCount > 0 ? "That's everything" : "Nothing due today",
                               message: emptyLine)
                        .padding(.horizontal, 16)
                        .padding(.top, 32)
                        .readableColumn()
                }
                Spacer(minLength: 0)
                StudyActionBar {
                    Button("Done") { dismiss() }
                        .buttonStyle(.bigPrimary)
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
        .modeScreen(.anki)
        .navigationTitle("Due today")
        .navigationBarTitleDisplayMode(.inline)
        .commuteModeButton()
        .onAppear(perform: load)
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

    /// Reveal, then the four ratings, always in the same place.
    private func footer(_ due: ReviewPlan.Due) -> some View {
        let interval = reviews.records[due.card.id]?.intervalMin ?? 0
        return StudyActionBar {
            if !revealed {
                Button { revealed = true } label: {
                    Text("Reveal")
                }
                .buttonStyle(.bigPrimary)
                // Space turns the card over, as it does in Anki
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityHint("Shows the answer. Say it to yourself first.")
            } else {
                AnkiRatingBar(labels: AnkiScheduler.previewLabels(currentIntervalMin: interval),
                              onRate: { rate($0, due) })
            }
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
        UISelectionFeedbackGenerator().selectionChanged()
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
