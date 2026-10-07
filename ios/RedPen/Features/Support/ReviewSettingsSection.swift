import SwiftUI

/// Settings > Review, as one Form section: daily limits, the scheduler,
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
        Section {
            Stepper(value: $newPerDay, in: 0...500, step: 5) {
                LabeledContent { obs(limitWords(newPerDay)) } label: { Text("New cards a day") }
            }
            .accessibilityIdentifier("reviewNewPerDay")
            Stepper(value: $reviewsPerDay, in: 0...2000, step: 25) {
                LabeledContent { obs(limitWords(reviewsPerDay)) } label: { Text("Reviews a day") }
            }
            .accessibilityIdentifier("reviewReviewsPerDay")
            Picker("Scheduler", selection: $schedulerRaw) {
                ForEach(ReviewScheduler.allCases) { kind in
                    Text(kind.title).tag(kind.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("reviewScheduler")
            Toggle("Ask how sure I am", isOn: $asksConfidence)
            LabeledContent { obs("\(reviews.records.count)") } label: { Text("Cards scheduled") }
            if reviews.suspendedCount > 0 {
                Button("Let \(reviews.suspendedCount) suspended card\(reviews.suspendedCount == 1 ? "" : "s") back in") {
                    reviews.unsuspendAll()
                }
            }
        } header: {
            Text(l10n: "Review")
        } footer: {
            Text(footer)
        }
        .onChange(of: newPerDay) { _, _ in reviews.settingsChanged() }
        .onChange(of: reviewsPerDay) { _, _ in reviews.settingsChanged() }
        .onChange(of: schedulerRaw) { _, _ in reviews.settingsChanged() }
    }

    private func obs(_ value: String) -> some View {
        Text(value)
            .font(.system(.body, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color.wardInkSecondary)
    }

    private func limitWords(_ n: Int) -> String {
        n <= 0 ? "No limit" : "\(n)"
    }

    private var footer: String {
        let scheduler: ReviewScheduler = ReviewScheduler(rawValue: schedulerRaw) ?? .classic
        let how: String
        switch scheduler {
        case .classic:
            how = "Classic is the app\u{2019}s own schedule, the same as the web version."
        case .fsrs:
            how = "FSRS-5 is the scheduler modern Anki uses: it learns how well you remember each card and aims for 90% recall. Your existing schedule carries over."
        }
        let hold: String = "Hold a card (or swipe it sideways) to bury it until tomorrow or suspend it. \u{201C}How sure are you?\u{201D} feeds Vitals."
        return how + " Limits count from 4 am. " + hold
    }
}
