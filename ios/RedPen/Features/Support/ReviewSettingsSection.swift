import SwiftUI

/// Settings > Review, as one Form section, one card: daily limits, the scheduler,
/// suspended cards, and the confidence row under questions.
///
/// Drop into the settings Form in place of the old one-line review section:
/// `ReviewSettingsSection()`. Needs the ReviewStore in the environment.
struct ReviewSettingsSection: View {
    @EnvironmentObject private var reviews: ReviewStore
    @AppStorage(ReviewSettings.newPerDayKey) private var newPerDay = 0
    @AppStorage(ReviewSettings.reviewsPerDayKey) private var reviewsPerDay = 0
    @AppStorage(ReviewSettings.schedulerKey) private var schedulerRaw = ReviewScheduler.classic.rawValue
    @AppStorage(ConfidenceSetting.key) private var asksConfidence = true

    var body: some View {
        // Android's Review group (the owner, 23 Oct): the scheduler and its
        // note, the two daily limits and theirs, in one card under its
        // small-caps heading; then the rows only iOS has.
        Section {
            VStack(alignment: .leading, spacing: WardSpace.m) {
                Text(l10n: "Review")
                    .wardSmallCaps()
                    .accessibilityAddTraits(.isHeader)
                // the control below says "Scheduler" to VoiceOver; once is enough
                Text("Scheduler").font(WardType.headline)
                    .accessibilityHidden(true)
                WardSegmented(selection: $schedulerRaw, options: ReviewScheduler.allCases.map(\.rawValue)) { raw in
                    Text(ReviewScheduler(rawValue: raw)?.title ?? raw)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Scheduler")
                .accessibilityIdentifier("reviewScheduler")
                note(schedulerNote)
                Stepper(value: $newPerDay, in: 0...500, step: 5) {
                    LabeledContent { obs(limitWords(newPerDay)) } label: { Text("New cards a day") }
                }
                .accessibilityIdentifier("reviewNewPerDay")
                Stepper(value: $reviewsPerDay, in: 0...2000, step: 25) {
                    LabeledContent { obs(limitWords(reviewsPerDay)) } label: { Text("Reviews a day") }
                }
                .accessibilityIdentifier("reviewReviewsPerDay")
                note("Learning cards always come back when due. A study day turns over at 4 am.")
                Toggle("Ask how sure I am", isOn: $asksConfidence)
                LabeledContent { obs("\(reviews.records.count)") } label: { Text("Cards scheduled") }
                if reviews.suspendedCount > 0 {
                    Button("Let \(reviews.suspendedCount) suspended card\(reviews.suspendedCount == 1 ? "" : "s") back in") {
                        reviews.unsuspendAll()
                    }
                    // its own tap, not the whole card's
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                }
            }
            .wardCard(lift: .low)
            .wardCardRow()
        }
        .onChange(of: newPerDay) { _, _ in reviews.settingsChanged() }
        .onChange(of: reviewsPerDay) { _, _ in reviews.settingsChanged() }
        .onChange(of: schedulerRaw) { _, _ in reviews.settingsChanged() }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(WardType.caption)
            .foregroundStyle(Color.wardInkSecondary)
    }

    private func obs(_ value: String) -> some View {
        Text(value)
            .font(WardType.obs)
            .monospacedDigit()
            .foregroundStyle(Color.wardInkSecondary)
    }

    private func limitWords(_ n: Int) -> String {
        n <= 0 ? "No limit" : "\(n)"
    }

    /// What the chosen scheduler does: Classic in Android's words, FSRS-5 in
    /// the plainer old line (independent review, T0160).
    private var schedulerNote: String {
        let scheduler: ReviewScheduler = ReviewScheduler(rawValue: schedulerRaw) ?? .classic
        switch scheduler {
        case .classic:
            return "Classic: the web app's intervals, the default."
        case .fsrs:
            return "FSRS-5 is the scheduler modern Anki uses: it learns how well you remember each card and aims for 90% recall. Your existing schedule carries over."
        }
    }
}
