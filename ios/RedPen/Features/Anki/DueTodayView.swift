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

    private static let sittingMinutes: Double = 20

    @State private var queue: [ReviewPlan.Due] = []
    @State private var revealed = false
    @State private var reviewedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            if let due = queue.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(due.setName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        AnkiCardFace(card: due.card, images: images(for: due),
                                     revealed: revealed)
                    }
                    .contentCard()
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                Spacer(minLength: 0)
                footer(due)
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Text(reviewedCount > 0 ? "That's everything." : "Nothing due today.")
                        .font(.headline)
                    Text(reviewedCount > 0
                         ? "\(reviewedCount) card\(reviewedCount == 1 ? "" : "s") reviewed across your decks."
                         : "Come back when a card is ready, or open a deck and study ahead.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            }
        }
        .modeScreen(.anki)
        .navigationTitle("Due today")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack {
            Text("\(queue.count) due")
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
    private func footer(_ due: ReviewPlan.Due) -> some View {
        let interval = reviews.records[due.card.id]?.intervalMin ?? 0
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if !revealed {
                    Button { revealed = true } label: {
                        Text("Reveal").frame(maxWidth: .infinity).padding(.vertical, 2)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    let labels = AnkiScheduler.previewLabels(currentIntervalMin: interval)
                    HStack(spacing: 8) {
                        rateButton(.again, labels[.again] ?? "", due: due, color: .red)
                        rateButton(.hard, labels[.hard] ?? "", due: due, color: .orange)
                        rateButton(.good, labels[.good] ?? "", due: due, color: .green)
                        rateButton(.easy, labels[.easy] ?? "", due: due, color: .blue)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func rateButton(_ rating: AnkiRating, _ subtitle: String,
                            due: ReviewPlan.Due, color: Color) -> some View {
        Button { rate(rating, due) } label: {
            VStack(spacing: 2) {
                Text(rating.rawValue.capitalized).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption2).opacity(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.glass).tint(color)
    }

    private func images(for due: ReviewPlan.Due) -> [String] {
        store.library.first { $0.id == due.setID }?.images ?? []
    }

    private func load() {
        guard queue.isEmpty, reviewedCount == 0 else { return }
        queue = reviews.dueAcross(store.library)
        revealed = false
    }

    private func rate(_ rating: AnkiRating, _ due: ReviewPlan.Due) {
        let kept = reviews.rate(rating, card: due.card)
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
