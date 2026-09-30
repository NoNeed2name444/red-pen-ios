import SwiftUI

/// The exam plan: where the run-up stands, what the student would remember
/// on the day, the next two weeks of reviews, how much is locked in per
/// subject, and what this phase asks for.
///
/// Opened from Mission Control's "Plan". Everything on it is an estimate
/// from the app's own schedule and answer history, and it says so.
struct ExamPlanView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @State private var quiz: StudySet?
    @State private var showingRules = false
    @State private var showingMock = false

    var body: some View {
        let exam: Date? = ExamCap.storedDate()
        let phase: ExamWeekPlanner.Phase = ExamWeekPlanner.phase(exam: exam, now: Date())
        let forecast: RetentionForecast.Forecast = reviews.examForecast(store.library,
                                                                      libraryVersion: store.changeCount)
        let standings: [UUID: SecuredRule.Standing] = store.securedStandings()
        let rings: [SecuredRule.Ring] = SecuredRule.rings(subjects: store.questionSubjects(), standings: standings)
        List {
            Section { PhaseHero(phase: phase) }
            // the chosen exam: countdown, blueprint coverage, readiness, study next
            Section {
                ExamDashboardCard()
            } header: {
                Text("Your exam")
            }
            Section {
                ForecastCard(forecast: forecast, phase: phase)
            } header: {
                Text("Remembering on the day")
            } footer: {
                Text("An estimate from your cards\u{2019} review intervals on a standard forgetting curve, not a measurement. No interval is allowed to run past your exam date: cards come back a day or two before it.")
            }
            Section("Due in the next two weeks") {
                DueBars(counts: dueCounts(), examDay: phase.days)
            }
            Section {
                SecuredRingsView(rings: rings)
            } header: {
                Text("Locked in")
            } footer: {
                Text("A question is locked in once you have got it right on three separate days. Getting something right in three spaced sessions keeps far more of it than three times in one sitting. A wrong answer starts its count again.")
            }
            Section("What this phase is for") { phaseActions(phase) }
        }
        .navigationTitle("Exam plan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $quiz) { MCQQuizView(set: $0, keepsProgress: false) }
        .navigationDestination(isPresented: $showingRules) { RuleSheetView() }
        .navigationDestination(isPresented: $showingMock) { MockPaperView() }
    }

    private func dueCounts() -> [Int] {
        let ids: [UUID] = store.library.flatMap { $0.deckCards.map(\.id) }
        return RetentionForecast.dueByDay(cardIDs: ids, records: reviews.records, now: Date(), days: 14)
    }

    @ViewBuilder
    private func phaseActions(_ phase: ExamWeekPlanner.Phase) -> some View {
        Text(phase.advice)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if phase.holdsNewMaterial {
            let confident: Int = store.confidentMistakePicks.count
            let missed: Int = store.lastWrongPicks.count
            if confident > 0 {
                planRow("Confident errors (\(confident))", symbol: "exclamationmark.triangle.fill") {
                    quiz = store.confidentMistakesQuiz()
                }
            }
            if missed > 0 {
                planRow("Your mistakes (\(missed))", symbol: "arrow.uturn.backward") { quiz = store.mistakesQuiz() }
            }
            planRow("Rule sheet", symbol: "list.bullet.rectangle") { showingRules = true }
        }
        let lockIn: Int = store.lockInPicks().count
        if lockIn > 0 {
            let plural: String = lockIn == 1 ? "" : "s"
            planRow("Lock in \(lockIn) question" + plural, symbol: "lock.fill") {
                quiz = store.lockInQuiz()
            }
        }
        if phase.isMockWindow {
            planRow("Sit a mock paper", symbol: "timer") { startMock() }
        }
        planRow("Symptom blocks", symbol: "stethoscope") { LearnRouter.shared.open(.symptomBlocks) }
        planRow("Exam-day kit", symbol: "checklist") { LearnRouter.shared.open(.examKit) }
    }

    /// The real mock paper (Features/Mock), pushed here. It counts as sat -
    /// and the lift-off button stops offering it - only once a sitting is
    /// finished (ExamStore.mocks, read by LearnMarks.mockDone).
    private func startMock() {
        showingMock = true
    }

    private func planRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24).accessibilityHidden(true)
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

/// The phase, large: "T-9 · Mock week".
private struct PhaseHero: View {
    let phase: ExamWeekPlanner.Phase

    var body: some View {
        let big: String = phase.days.map { $0 == 0 ? "Today" : "T-\($0)" } ?? "\u{2014}"
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(big)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.headline).font(.headline)
                if phase == .noDate {
                    Text("Set it in Settings \u{2192} Your exam.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// "If your exam were today you'd remember ~71%; do 140 reviews over the
/// next 10 days to reach 90%."
private struct ForecastCard: View {
    let forecast: RetentionForecast.Forecast
    let phase: ExamWeekPlanner.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if forecast.studied == 0 {
                Text("Review some cards and a forecast of what you would remember on the day will show here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                filled
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var filled: some View {
        let today: String = RetentionForecast.percent(forecast.today)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("~" + today)
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
            Text("if your exam were today").font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        ThinProgress(fraction: forecast.today)
        if phase.days != nil && phase != .examDay {
            let onDay: String = RetentionForecast.percent(forecast.onExamDay)
            Text("On exam day with no more reviews: ~\(onDay).")
                .font(.subheadline)
            Text(planSentence).font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        if forecast.unseen > 0 {
            let plural: String = forecast.unseen == 1 ? "" : "s"
            Text("\(forecast.unseen) card\(plural) not yet studied are not in these figures.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var planSentence: String {
        if forecast.reviewsNeeded == 0 { return "On course for 90% on the day." }
        let plural: String = forecast.days == 1 ? "" : "s"
        let perDay: String = "about \(forecast.perDay) a day"
        return "Do \(forecast.reviewsNeeded) reviews over the next \(forecast.days) day\(plural) (\(perDay)) to reach 90%."
    }
}

/// Fourteen small bars: cards falling due each day, today first.
private struct DueBars: View {
    let counts: [Int]
    /// Days to the exam, to mark its bar.
    let examDay: Int?

    var body: some View {
        let top: Int = max(1, counts.max() ?? 1)
        let total: Int = counts.reduce(0, +)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(counts.enumerated()), id: \.offset) { item in
                    bar(day: item.offset, count: item.element, top: top)
                }
            }
            .frame(height: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(total) cards due over the next two weeks, \(counts.first ?? 0) today")
            HStack {
                Text("Today").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("+13 days").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func bar(day: Int, count: Int, top: Int) -> some View {
        let share: CGFloat = CGFloat(count) / CGFloat(top)
        let height: CGFloat = max(3, 64 * share)
        let isExam: Bool = examDay == day
        let fill: Color = isExam ? Color.red : StudySetKind.anki.tint
        return VStack(spacing: 2) {
            Spacer(minLength: 0)
            Capsule().fill(fill.opacity(count == 0 ? 0.25 : 1)).frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One ring per subject: locked in, with the questions on their way lighter.
struct SecuredRingsView: View {
    let rings: [SecuredRule.Ring]

    var body: some View {
        if rings.isEmpty {
            Text("Answer some questions and each subject gets a ring here.")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            let secured: Int = rings.reduce(0) { $0 + $1.secured }
            let total: Int = rings.reduce(0) { $0 + $1.total }
            Text("\(secured) of \(total) questions locked in")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 16) {
                ForEach(rings) { ring in SubjectRing(ring: ring) }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct SubjectRing: View {
    let ring: SecuredRule.Ring

    var body: some View {
        let total: Double = Double(max(1, ring.total))
        let secured: Double = Double(ring.secured) / total
        let building: Double = Double(ring.secured + ring.building) / total
        let tint: Color = StudySetKind.mcq.tint
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
                Circle().trim(from: 0, to: building)
                    .stroke(tint.opacity(0.3), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().trim(from: 0, to: secured)
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(RetentionForecast.percent(secured))
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            .frame(width: 60, height: 60)
            Text(ring.subject).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            Text("\(ring.secured)/\(ring.total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.subject): \(ring.secured) of \(ring.total) locked in, \(ring.building) on their way")
    }
}
