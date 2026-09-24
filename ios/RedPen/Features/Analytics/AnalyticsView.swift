import SwiftUI
import Charts

/// Analytics: where the marks are going, and what to study next.
///
/// Progress (StatsView) answers "how am I doing"; this page answers "so what
/// do I do now". It opens on a short ranked list of next steps, each one a
/// tap that starts the right thing - a drill, a quiz, the cards waiting, the
/// syllabus gaps - with one line saying why it is on the list. Under that sit
/// the evidence: the readiness estimate, how accuracy and practice have moved
/// week by week, the mistakes themselves, each subject, and the study habit.
///
/// Everything here is read from what the app already keeps: the dated answer
/// log, the per-question history, the reasons given for wrong answers, the
/// review schedule, the daily study log and the syllabus coverage check.
/// Nothing new is stored.
struct AnalyticsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @ObservedObject private var log = StudyLog.shared

    /// A quiz started from this page, with how it is to be sat.
    @State private var quiz: InsightQuiz?
    /// A page pushed from this one that is not a quiz.
    @State private var route: AnalyticsRoute?
    /// The subject the recent wrong answers are narrowed to; blank for all.
    @State private var mistakeSubject = ""
    /// What the syllabus check found missing, once it has run.
    @State private var gaps: CoverageGaps?
    /// The numbers, worked out once and kept: redrawing for a picker or a
    /// pushed page does not go through the whole answer log again. Refreshed
    /// when the page appears and shortly after the data under it changes.
    @State private var cached: AnalyticsSnapshot?
    /// Whether the page is on screen; changes made under a quiz pushed on top
    /// wait until it is back, rather than being worked out after every answer.
    @State private var visible = false

    /// Changes whenever anything the numbers are read from changes: the
    /// library and answers, the review schedule, the study log. Cheap to
    /// compare on every redraw, unlike working the numbers out.
    private var dataKey: String {
        var studied: Int = 0
        for count in log.days.values { studied += count }
        return "\(store.changeCount)-\(reviews.changeCount)-\(log.days.count)-\(studied)"
    }

    var body: some View {
        let s: AnalyticsSnapshot = cached ?? snapshot()
        let items: [FocusItem] = focusItems(s)
        ScrollViewReader { proxy in
            List {
                if s.includesExamples {
                    Section {
                        Label("Includes example data", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                heroSection(s, proxy: proxy)
                focusSection(items, sparks: s.sparks)
                Section {
                    ReadinessCard(estimate: s.readiness,
                                  answered: s.recentCount,
                                  includesExamples: s.includesExamples) { subject in
                        startQuiz(store.drill(subject: subject))
                    }
                    .id(AnalyticsAnchor.readiness)
                } header: {
                    Text("Readiness")
                }
                trendsSection(s)
                mistakesSection(s)
                subjectsSection(s)
                timeSection(s)
            }
        }
        // pushed bare from the examples hub too, so it brings its own backdrop
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        // the best next step, under the thumb; nothing there until there is one
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let top = items.first {
                StudyActionBar { startButton(top) }
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: coverageKey) { await findGaps() }
        .onAppear {
            visible = true
            cached = snapshot()
        }
        .onDisappear { visible = false }
        .onChange(of: dataKey) { _, _ in
            // off screen (a quiz pushed on top): worked out on coming back
            if visible { cached = snapshot() }
        }
        .navigationDestination(item: $quiz) { quiz in
            MCQQuizView(set: quiz.set, keepsProgress: false,
                        minReadSeconds: quiz.minReadSeconds, startsTimed: quiz.timed)
        }
        .navigationDestination(item: $route) { route in
            destination(route)
        }
    }

    /// "Start: Drill Renal" - the first of Focus next, as the screen's one
    /// main button.
    private func startButton(_ item: FocusItem) -> some View {
        let title: String = "Start: " + item.title
        return Button {
            run(item.action)
        } label: {
            Label(title, systemImage: item.symbol)
                .lineLimit(2)
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.defaultAction)
        .accessibilityHint(item.detail)
    }

    /// Scrolls the list to one of its places, gently.
    private func jump(_ proxy: ScrollViewProxy, to anchor: String) {
        withAnimation(.snappy) { proxy.scrollTo(anchor, anchor: .top) }
    }

    // MARK: - Opening things

    /// Opens a quiz, if it has any questions.
    private func startQuiz(_ set: StudySet, minReadSeconds: Int = 0, timed: Bool = false) {
        guard !set.questions.isEmpty else { return }
        quiz = InsightQuiz(set: set, minReadSeconds: minReadSeconds, timed: timed)
    }

    @ViewBuilder
    private func destination(_ route: AnalyticsRoute) -> some View {
        switch route {
        case .due:
            DueTodayView()
        case .coverage:
            CoverageView()
        case .rules:
            RuleSheetView()
        case .confident:
            InsightQuestionList(
                title: "Confident but wrong",
                tip: "These felt certain and were not: usually a fact learned wrongly rather than one not learned. Read the explanation, then quiz them again.",
                picks: store.confidentMistakePicks)
        case .reason(let reason):
            InsightQuestionList(title: reason.title, tip: Self.tip(for: reason),
                                picks: store.picks(for: reason))
        case .bySubject:
            StatsView()
        }
    }

    /// Does the one thing suggested for a reason marks are lost, the same
    /// things the Progress page offers.
    private func fix(_ reason: MistakeReason) {
        switch reason {
        case .didntKnow:
            startQuiz(store.reasonQuiz(.didntKnow, named: "Practise these"))
        case .misread:
            startQuiz(store.reasonQuiz(.misread, named: "Slow reading drill"), minReadSeconds: 15)
        case .outOfTime:
            startQuiz(store.timedDrill(), timed: true)
        case .changedAnswer, .lookalikes:
            route = .reason(reason)
        }
    }

    private static func tip(for reason: MistakeReason) -> String? {
        switch reason {
        case .changedAnswer:
            return "Change an answer only when you find a clue in the stem you missed the first time, not because a second option starts to look good. Your first answer was right here."
        case .lookalikes:
            return "For each, name the one feature that tells the right answer from the option you chose."
        default:
            return nil
        }
    }

    private func run(_ action: FocusAction) {
        switch action {
        case .drill(let subject): startQuiz(store.drill(subject: subject))
        case .confidentQuiz: startQuiz(store.confidentMistakesQuiz())
        case .due: route = .due
        case .coverage: route = .coverage
        case .reason(let reason): fix(reason)
        }
    }

    // MARK: - Syllabus gaps

    /// Re-run the coverage check when the exam, the library or the answers
    /// change - not on every redraw.
    private var coverageKey: String {
        let edited = store.library.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let answers = store.answerHistory.values.reduce(0) { $0 + $1.count }
        return "\(ExamTrack.current.rawValue)-\(store.library.count)-\(edited)-\(answers)"
    }

    /// The same keyword check the Syllabus page runs, kept to its count of
    /// subtopics nothing in the library mentions.
    private func findGaps() async {
        let library = store.library
        let history = store.answerHistory
        let track = ExamTrack.current
        let blueprint = Syllabus.areas(for: track)
        let result = await Task.detached(priority: .utility) {
            CoverageEngine.assess(library: library, history: history, areas: blueprint)
        }.value
        guard !Task.isCancelled else { return }
        let subtopics = result.flatMap { $0.subtopics }
        let missing = subtopics.filter { $0.status == .notCovered }
        gaps = CoverageGaps(missing: missing.count, total: subtopics.count,
                            first: missing.first?.subtopic.name,
                            covered: subtopics.filter { $0.status == .covered }.count,
                            thin: subtopics.filter { $0.status == .thin }.count,
                            track: track)
    }

    // MARK: - The numbers, worked out once per redraw

    private func snapshot(now: Date = Date()) -> AnalyticsSnapshot {
        let calendar = Calendar.current
        var picks: [UUID: QuestionPick] = [:]
        for pick in store.mcqPicks({ _ in true }) { picks[pick.question.id] = pick }

        // accuracy per week, oldest week first; week 7 is the last seven days
        let today = calendar.startOfDay(for: now)
        var weekAnswered = Array(repeating: 0, count: 8)
        var weekCorrect = Array(repeating: 0, count: 8)
        var perDay: [String: Int] = [:]
        var recent: [String: Tally] = [:], earlier: [String: Tally] = [:]
        let fortnight = now.addingTimeInterval(-14 * 86_400)
        let month30 = now.addingTimeInterval(-30 * 86_400)
        var lastMonth = Tally()
        var sparkDays: [String: [Date: Tally]] = [:]
        for event in store.answerLog {
            if event.date >= month30 { lastMonth.add(event.correct) }
            perDay[StudyLog.key(for: event.date), default: 0] += 1
            let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.date),
                                                  to: today).day ?? Int.max
            if daysAgo >= 0 && daysAgo < 56 {
                let week = 7 - daysAgo / 7
                weekAnswered[week] += 1
                if event.correct { weekCorrect[week] += 1 }
            }
            if let pick = picks[event.questionId] {
                let subject = Store.subjectName(pick.set)
                if event.date >= fortnight {
                    recent[subject, default: Tally()].add(event.correct)
                    sparkDays[subject, default: [:]][calendar.startOfDay(for: event.date), default: Tally()]
                        .add(event.correct)
                } else {
                    earlier[subject, default: Tally()].add(event.correct)
                }
            }
        }
        var weeks: [WeekPoint] = []
        for week in 0..<8 where weekAnswered[week] > 0 {
            let back: Int = (7 - week) * 7 + 6
            guard let start = calendar.date(byAdding: .day, value: -back, to: today)
            else { continue }
            weeks.append(WeekPoint(start: start, answered: weekAnswered[week],
                                   accuracy: Double(weekCorrect[week]) / Double(weekAnswered[week])))
        }

        // studied per day for the last 30 days: the larger of the study log's
        // count (which also counts cards) and the answers in the dated log
        var days: [DayPoint] = []
        for back in stride(from: 29, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let key = StudyLog.key(for: day)
            days.append(DayPoint(day: day, count: max(log.days[key] ?? 0, perDay[key] ?? 0)))
        }

        // days with anything done this month, from either record
        let month = String(StudyLog.key(for: now).prefix(7))
        var studiedKeys = Set(log.days.filter { $0.value > 0 }.map { $0.key })
        studiedKeys.formUnion(perDay.keys)
        let studiedThisMonth = studiedKeys.filter { $0.hasPrefix(month) }.count

        // every day's amount, the larger of the two records, for the calendar
        var dayCounts = log.days
        for (key, count) in perDay where count > (dayCounts[key] ?? 0) { dayCounts[key] = count }

        var sparks: [String: [SparkPoint]] = [:]
        for (subject, byDay) in sparkDays {
            sparks[subject] = byDay.map { SparkPoint(day: $0.key, accuracy: $0.value.accuracy) }
                .sorted { $0.day < $1.day }
        }

        var trends: [String: Trend] = [:]
        for (subject, latest) in recent {
            guard let before = earlier[subject], before.answered >= 3, latest.answered >= 3 else { continue }
            let change = latest.accuracy - before.accuracy
            let trend: Trend = change > 0.05 ? Trend.up : (change < -0.05 ? Trend.down : Trend.flat)
            trends[subject] = trend
        }

        // the latest wrong answer to each question still in the library
        var wrong: [WrongAnswer] = []
        var seen: Set<UUID> = []
        for event in store.answerLog.reversed() where !event.correct {
            guard wrong.count < 40, seen.insert(event.questionId).inserted,
                  let pick = picks[event.questionId] else { continue }
            wrong.append(WrongAnswer(pick: pick, date: event.date,
                                     reason: store.mistakeReasons[event.questionId]?.reason,
                                     picked: event.picked))
        }

        let due = reviews.dueAcross(store.library).count
        return AnalyticsSnapshot(stats: store.subjectStats(),
                                 due: due,
                                 confidentWrong: store.confidentMistakePicks.count,
                                 shares: store.reasonShares(),
                                 weeks: weeks, days: days, wrong: wrong, trends: trends,
                                 studiedThisMonth: studiedThisMonth,
                                 readiness: store.readiness(dueCards: due),
                                 lastMonth: lastMonth,
                                 dayCounts: dayCounts,
                                 today: dayCounts[StudyLog.key(for: now)] ?? 0,
                                 sparks: sparks,
                                 calibration: store.calibration(),
                                 recentCount: store.recentAnswers.count,
                                 includesExamples: store.includesExampleData)
    }

    // MARK: - The rings at the top

    private static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    /// How much to do today: the pace that gets through every question in the
    /// library by the exam date, as the library's exam countdown works it out,
    /// or 30 when no date is set or it has passed.
    private func dailyTarget(now: Date = Date()) -> (target: Int, fromExam: Bool) {
        let stamp = UserDefaults.standard.double(forKey: ExamTrack.dateKey)
        guard stamp > 0 else { return (30, false) }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: Date(timeIntervalSince1970: stamp))).day ?? 0
        let questions = store.library.filter { $0.kind == .mcq }.reduce(0) { $0 + $1.questions.count }
        guard days > 0, questions > 0 else { return (30, false) }
        return (max(1, Int((Double(questions) / Double(days)).rounded(.up))), true)
    }

    /// Four rings: readiness against the pass mark, accuracy this month, the
    /// syllabus covered, and today against the day's target. Each is a
    /// button: Readiness and Accuracy scroll to what is behind them, Syllabus
    /// and Today open their pages.
    private func heroSection(_ s: AnalyticsSnapshot, proxy: ScrollViewProxy) -> some View {
        let goal = dailyTarget()
        let subjectsAnchor: String = s.stats.first?.id ?? AnalyticsAnchor.subjectsEmpty
        let pace: String = goal.fromExam ? "the pace that gets through your library by the exam."
                                         : "30 until you set an exam date."
        let note: String = "Tap a ring for what is behind it. The tick on Readiness is the typical pass mark. Syllabus shows covered, thin and missing topics. Today\u{2019}s target is \(pace)"
        return Section {
            HStack(alignment: .top, spacing: 4) {
                Button { jump(proxy, to: AnalyticsAnchor.readiness) } label: {
                    readinessRing(s.readiness)
                }
                .accessibilityHint("Shows the readiness estimate")
                Button { jump(proxy, to: subjectsAnchor) } label: {
                    accuracyRing(s)
                }
                .accessibilityHint("Shows accuracy subject by subject")
                Button { route = .coverage } label: {
                    syllabusRing()
                }
                .accessibilityHint("Opens the syllabus")
                Button { route = .due } label: {
                    todayRing(s, goal: goal.target)
                }
                .accessibilityHint("Opens the cards due today")
            }
            .buttonStyle(RingButtonStyle())
            .padding(.vertical, 6)
        } footer: {
            Text(note)
        }
    }

    private func accuracyRing(_ s: AnalyticsSnapshot) -> some View {
        let accuracy: Double? = s.lastMonth.answered > 0 ? s.lastMonth.accuracy : nil
        let spoken: String
        if let accuracy {
            spoken = "\(Self.percent(accuracy)) of \(s.lastMonth.answered) answers right"
        } else {
            spoken = "no answers yet"
        }
        let centre: String = accuracy.map { Self.percent($0) } ?? "\u{2013}"
        return ProgressRing(value: accuracy ?? 0, label: "Accuracy, 30 days", spoken: spoken, raised: true) {
            RingCentre(value: centre)
        }
        .frame(maxWidth: .infinity)
    }

    private func todayRing(_ s: AnalyticsSnapshot, goal target: Int) -> some View {
        let spoken: String = "\(s.today) of \(target) studied today"
        return ProgressRing(value: Double(s.today), total: Double(target),
                            tint: StudySetKind.book.tint, label: "Today",
                            spoken: spoken, raised: true) {
            RingCentre(value: "\(s.today)", caption: "of \(target)")
        }
        .frame(maxWidth: .infinity)
    }

    private func readinessRing(_ estimate: ReadinessEstimate?) -> some View {
        let spoken: String
        if let estimate {
            spoken = "estimated \(Self.percent(estimate.center)), pass mark about \(Self.percent(estimate.passMark))"
        } else {
            spoken = "answer at least \(Readiness.minimumAnswers) questions for an estimate"
        }
        let mark: Double = estimate?.passMark ?? PassMark.typical(for: .current)
        let centre: String = estimate.map { Self.percent($0.center) } ?? "\u{2013}"
        return ProgressRing(value: estimate?.center ?? 0, label: "Readiness",
                            marker: mark, spoken: spoken, raised: true) {
            RingCentre(value: centre)
        }
        .frame(maxWidth: .infinity)
    }

    private func syllabusRing() -> some View {
        let segments: [RingSegment]
        let centre: String
        let spoken: String
        if let gaps, gaps.total > 0 {
            segments = [
                RingSegment(value: Double(gaps.covered), color: .accentColor, label: "Covered"),
                RingSegment(value: Double(gaps.thin), color: Color.accentColor.opacity(0.4), label: "Thin"),
                RingSegment(value: Double(gaps.missing), color: Color.primary.opacity(0.15), label: "Missing"),
            ]
            centre = Self.percent(Double(gaps.covered) / Double(gaps.total))
            spoken = "\(gaps.covered) topics covered, \(gaps.thin) thin, \(gaps.missing) missing, of \(gaps.total)"
        } else {
            segments = []
            centre = "\u{2026}"
            spoken = "still checking"
        }
        return ProgressRing(value: 0, segments: segments, label: "Syllabus", spoken: spoken, raised: true) {
            RingCentre(value: centre)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 1. Focus next

    /// Every candidate next step with its score, best first, five at most.
    ///
    /// Each score is out of about 100 and meant to be read as "how many marks
    /// this is likely worth", in the roughest sense:
    /// - a weak subject: how often it is missed, trusted fully from 20 answers;
    /// - confident mistakes: 40, and 5 more for each one;
    /// - cards waiting: 15, and 1 more for each card, at most 85;
    /// - syllabus gaps: 10, and up to 60 more for the share of topics missing;
    /// - the commonest reason for a lost mark: its share, trusted fully from 5.
    private func focusItems(_ s: AnalyticsSnapshot) -> [FocusItem] {
        var items: [FocusItem] = []

        for subject in s.stats.filter({ $0.answered >= 5 && $0.accuracy < 0.75 }).prefix(2) {
            let percent = Int((subject.accuracy * 100).rounded())
            let trust: Double = min(1, Double(subject.answered) / 20)
            let missed: Double = (1 - subject.accuracy) * 100
            let score: Double = missed * trust
            items.append(FocusItem(
                id: "drill-" + subject.subject,
                title: "Drill \(subject.subject)",
                detail: "\(percent)% right in \(subject.subject) over \(subject.answered) answers",
                symbol: "scope",
                score: score,
                action: .drill(subject.subject), subject: subject.subject))
        }

        if s.confidentWrong > 0 {
            let n = s.confidentWrong
            items.append(FocusItem(
                id: "confident", title: "Confident mistakes quiz",
                detail: "\(n) question\(n == 1 ? "" : "s") you were sure of and got wrong",
                symbol: "exclamationmark.triangle",
                score: min(95, 40 + Double(n) * 5), action: .confidentQuiz))
        }

        if s.due > 0 {
            items.append(FocusItem(
                id: "due", title: "Review cards due",
                detail: "\(s.due) card\(s.due == 1 ? "" : "s") waiting for review",
                symbol: "rectangle.stack",
                score: min(85, 15 + Double(s.due)), action: .due))
        }

        if let gaps, gaps.missing > 0, gaps.total > 0 {
            let exam = gaps.track == .general ? "syllabus" : gaps.track.rawValue.uppercased()
            var detail = "\(gaps.missing) of \(gaps.total) \(exam) topics have nothing in your library"
            if let first = gaps.first { detail += ", such as \(first)" }
            items.append(FocusItem(
                id: "gaps", title: "Fill syllabus gaps", detail: detail,
                symbol: "checklist",
                score: 10 + 60 * Double(gaps.missing) / Double(gaps.total), action: .coverage))
        }

        if let top = s.shares.first, top.count >= 2 {
            let percent = Int((top.share * 100).rounded())
            items.append(FocusItem(
                id: "reason", title: Self.fixTitle(top.reason),
                detail: "\(top.reason.title): \(percent)% of the reasons you gave, last \(Store.reasonWindowDays) days",
                symbol: top.reason.symbol,
                score: Double(percent) * min(1, Double(top.count) / 5), action: .reason(top.reason)))
        }

        return Array(items.sorted { $0.score > $1.score }.prefix(5))
    }

    private static func fixTitle(_ reason: MistakeReason) -> String {
        switch reason {
        case .didntKnow: return "Practise what you didn\u{2019}t know"
        case .misread: return "Slow reading drill"
        case .changedAnswer: return "Stop changing right answers"
        case .outOfTime: return "Timed drill"
        case .lookalikes: return "Tell lookalikes apart"
        }
    }

    @ViewBuilder
    private func focusSection(_ items: [FocusItem], sparks: [String: [SparkPoint]]) -> some View {
        Section {
            if items.isEmpty {
                ContentUnavailableView("Nothing to focus on yet", systemImage: "scope",
                                       description: Text("Make an MCQ set and answer a few questions. The most useful next steps will show here, best first."))
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let spark: [SparkPoint] = item.subject.flatMap { sparks[$0] } ?? []
                    Button { run(item.action) } label: {
                        focusRow(item, rank: index + 1, spark: spark)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
            }
        } header: {
            Text("Focus next")
        } footer: {
            if !items.isEmpty {
                Text("Ranked by how many marks each is likely worth: weak subjects by how often they are missed, then confident mistakes, cards waiting, syllabus gaps and your commonest reason for losing a mark.")
            }
        }
    }

    private func focusRow(_ item: FocusItem, rank: Int, spark: [SparkPoint]) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Label(item.title, systemImage: item.symbol)
                    .font(.body.weight(.semibold))
                Text(item.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if spark.count >= 2 {
                    Sparkline(points: spark)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 3. Trends

    @ViewBuilder
    private func trendsSection(_ s: AnalyticsSnapshot) -> some View {
        Section {
            if s.weeks.isEmpty {
                ContentUnavailableView("No trends yet", systemImage: "chart.xyaxis.line",
                                       description: Text("Answer questions on a few different days and your weekly accuracy and daily practice will show here."))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accuracy by week").font(.subheadline.weight(.semibold))
                    weeklyChart(s.weeks)
                    Text("The last 8 weeks. The dashed line is the typical pass mark.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Studied per day").font(.subheadline.weight(.semibold))
                    dailyChart(s.days)
                    Text("The last 30 days: questions answered and cards reviewed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Trends")
        }
    }

    private func weeklyChart(_ weeks: [WeekPoint]) -> some View {
        let passMark = PassMark.typical(for: .current) * 100
        return Chart {
            ForEach(weeks) { week in
                LineMark(x: .value("Week", week.start), y: .value("Accuracy", week.accuracy * 100))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("Week", week.start), y: .value("Accuracy", week.accuracy * 100))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(30)
            }
            RuleMark(y: .value("Pass mark", passMark))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.secondary)
        }
        .chartYScale(domain: 0.0...100.0)
        .chartYAxis {
            AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text("\(Int(value.as(Double.self) ?? 0))%")
                }
            }
        }
        .frame(height: 150)
    }

    private func dailyChart(_ days: [DayPoint]) -> some View {
        Chart(days) { day in
            BarMark(x: .value("Day", day.day, unit: .day), y: .value("Studied", day.count))
                .foregroundStyle(Color.accentColor.opacity(0.7))
        }
        .frame(height: 120)
    }

    // MARK: - 4. Mistakes

    @ViewBuilder
    private func mistakesSection(_ s: AnalyticsSnapshot) -> some View {
        let subjects = Array(Set(s.wrong.map { Store.subjectName($0.pick.set) })).sorted()
        let shown = mistakeSubject.isEmpty
            ? s.wrong
            : s.wrong.filter { Store.subjectName($0.pick.set) == mistakeSubject }
        Section {
            if s.wrong.isEmpty && s.shares.isEmpty && s.calibration.isEmpty {
                ContentUnavailableView("No mistakes yet", systemImage: "checkmark.seal",
                                       description: Text("Questions you get wrong, and the reasons you give for them, will show here."))
            } else {
                if !s.shares.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why you lose marks").font(.subheadline.weight(.semibold))
                        ReasonDonut(shares: s.shares)
                        Text("The last \(Store.reasonWindowDays) days, from the reason picked after each wrong answer. Your commonest one has its fix under Focus next.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                if !s.calibration.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Right by confidence").font(.subheadline.weight(.semibold))
                        CalibrationChart(rows: s.calibration)
                        Text("Bars are how often each was right; the dashed line is roughly where it should be. \u{201C}Sure\u{201D} well under the line means facts learned wrongly.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                if s.confidentWrong > 0 {
                    Button { route = .confident } label: {
                        HStack {
                            Label("Confident but wrong", systemImage: "exclamationmark.triangle")
                            Spacer(minLength: 8)
                            Text("\(s.confidentWrong)")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
                if subjects.count > 1 {
                    Picker("Subject", selection: $mistakeSubject) {
                        Text("All subjects").tag("")
                        ForEach(subjects, id: \.self) { subject in
                            Text(subject).tag(subject)
                        }
                    }
                }
                ForEach(shown) { answer in
                    wrongRow(answer)
                }
            }
        } header: {
            Text("Mistakes")
        } footer: {
            if !s.wrong.isEmpty {
                Text("Your latest wrong answer to each question, newest first. Tap one to try it again; the list icon opens its line on the rule sheet.")
            }
        }
    }

    private func wrongRow(_ answer: WrongAnswer) -> some View {
        let q = answer.pick.question
        let right = q.options.indices.contains(q.correctIndex) ? q.options[q.correctIndex] : ""
        let subject: String = Store.subjectName(answer.pick.set)
        let when: String = answer.date.formatted(date: .abbreviated, time: .omitted)
        var line: String = "\(subject) \u{00B7} \(when)"
        if let reason = answer.reason { line += " \u{00B7} " + reason.title }
        // what was chosen instead, when it was recorded and is still one of
        // the question's options
        var chosen: String = ""
        if let picked = answer.picked, picked != q.correctIndex, q.options.indices.contains(picked) {
            chosen = "You chose " + q.options[picked]
        }
        return HStack(alignment: .top, spacing: 10) {
            Button {
                startQuiz(Store.temporaryQuiz(named: "One question", subject: Store.subjectName(answer.pick.set),
                                              from: [answer.pick]))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(q.stem).font(.subheadline).lineLimit(3)
                    if !chosen.isEmpty {
                        Label(chosen, systemImage: "xmark.circle")
                            .font(.caption).foregroundStyle(.red)
                    }
                    if !right.isEmpty {
                        Label(right, systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.green)
                    }
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this question on its own")
            if store.ruleSheet[q.id] != nil {
                // a frosted disc standing out of the row, sinking under the
                // finger; 22 points of corner on a 44-point face is a circle
                Button { route = .rules } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.body)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(PopTileStyle(cornerRadius: 22))
                .accessibilityLabel("Rule sheet")
                .help("Rule sheet")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 5. Subjects

    @ViewBuilder
    private func subjectsSection(_ s: AnalyticsSnapshot) -> some View {
        Section {
            if s.stats.isEmpty {
                ContentUnavailableView("No subjects yet", systemImage: "books.vertical",
                                       description: Text("Make an MCQ set and each subject you study will show here with its accuracy."))
                    .id(AnalyticsAnchor.subjectsEmpty)
            } else {
                ForEach(s.stats) { subject in
                    Button {
                        startQuiz(store.drill(subject: subject.subject))
                    } label: {
                        subjectRow(subject, trend: s.trends[subject.subject])
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityHint("Opens a drill of \(subject.subject)")
                }
            }
        } header: {
            HStack {
                Text("Subjects")
                Spacer(minLength: 8)
                // a glass chip standing out of the header; the finger's
                // worth of target is taller than the chip
                Button { route = .bySubject } label: {
                    Label("By subject", systemImage: "chart.bar.doc.horizontal")
                        .font(.footnote.weight(.semibold))
                        .textCase(nil)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .liquidGlassChip(tint: nil, plane: .raised)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .hoverEffect(.highlight)
                .accessibilityHint("Opens Progress, subject by subject")
            }
        } footer: {
            if !s.stats.isEmpty {
                Text("Weakest first; tap one to drill it. The arrow compares the last two weeks with before, when both have a few answers.")
            }
        }
    }

    private func subjectRow(_ s: SubjectStats, trend: Trend?) -> some View {
        let accuracy: Double = s.answered == 0 ? 0 : s.accuracy
        let percent: String = s.answered == 0 ? "\u{2013}" : Self.percent(s.accuracy)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.subject).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(s.answered) answered").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let trend {
                Image(systemName: trend.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(trend.color)
                    .accessibilityLabel(trend.label)
            }
            ProgressRing(value: accuracy, label: "", size: 22, lineWidth: 3.5) {
                EmptyView()
            }
            .accessibilityHidden(true)
            Text(percent)
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(minWidth: 40, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - 6. Time

    private func timeSection(_ s: AnalyticsSnapshot) -> some View {
        let active = s.days.filter { $0.count > 0 }
        let total = active.reduce(0) { $0 + $1.count }
        let average = active.isEmpty ? 0 : Int((Double(total) / Double(active.count)).rounded())
        return Section {
            HStack(spacing: 0) {
                figure("\(log.streak)", log.streak == 1 ? "day streak" : "days streak",
                       symbol: "flame.fill", color: .orange)
                figure("\(s.studiedThisMonth)", "days this month",
                       symbol: "calendar", color: .accentColor)
                figure(active.isEmpty ? "\u{2013}" : "\(average)", "a day studied",
                       symbol: "chart.bar.fill", color: .green)
            }
            .padding(.vertical, 4)
            StudyHeatmap(counts: s.dayCounts)
                .padding(.vertical, 6)
        } header: {
            Text("Time")
        } footer: {
            Text("The average is over the days in the last 30 you studied at all. The calendar is the last 12 weeks, a column a week, today outlined.")
        }
    }

    private func figure(_ value: String, _ caption: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color)
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(caption).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - What the page works from

/// Everything the page shows, worked out in one pass over the answer log.
private struct AnalyticsSnapshot {
    var stats: [SubjectStats]
    var due: Int
    var confidentWrong: Int
    var shares: [ReasonShare]
    var weeks: [WeekPoint]
    var days: [DayPoint]
    var wrong: [WrongAnswer]
    var trends: [String: Trend]
    var studiedThisMonth: Int
    var readiness: ReadinessEstimate?
    /// Answers in the last 30 days.
    var lastMonth: Tally
    /// Amount studied per day, keyed like StudyLog.
    var dayCounts: [String: Int]
    /// Amount studied today.
    var today: Int
    /// Each subject's accuracy day by day over the last 14 days.
    var sparks: [String: [SparkPoint]]
    var calibration: [CalibrationRow]
    /// Answers the readiness estimate can read.
    var recentCount: Int
    /// Whether any of it is the personal build's example history.
    var includesExamples: Bool
}

/// Answers and right answers, added up.
private struct Tally {
    var answered = 0
    var correct = 0
    var accuracy: Double { answered == 0 ? 0 : Double(correct) / Double(answered) }

    mutating func add(_ right: Bool) {
        answered += 1
        if right { correct += 1 }
    }
}

/// One week on the accuracy chart.
private struct WeekPoint: Identifiable {
    var start: Date
    var answered: Int
    var accuracy: Double
    var id: Date { start }
}

/// One day on the practice chart.
private struct DayPoint: Identifiable {
    var day: Date
    var count: Int
    var id: Date { day }
}

/// The latest wrong answer to one question.
private struct WrongAnswer: Identifiable {
    var pick: QuestionPick
    var date: Date
    var reason: MistakeReason?
    /// The option chosen, as its index in the question's own options.
    var picked: Int?
    var id: UUID { pick.question.id }
}

/// Which way a subject is going: the last two weeks against before.
private enum Trend {
    case up, down, flat

    var symbol: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .flat: return .secondary
        }
    }

    var label: String {
        switch self {
        case .up: return "Improving"
        case .down: return "Slipping"
        case .flat: return "Steady"
        }
    }
}

/// What the syllabus check found for the chosen exam.
private struct CoverageGaps: Hashable {
    var missing: Int
    var total: Int
    /// The first missing subtopic, as an example.
    var first: String?
    var covered: Int = 0
    var thin: Int = 0
    var track: ExamTrack
}

/// What tapping a "Focus next" row starts.
private enum FocusAction: Hashable {
    case drill(String)
    case confidentQuiz
    case due
    case coverage
    case reason(MistakeReason)
}

/// One suggested next step, with the reason it is suggested.
private struct FocusItem: Identifiable {
    var id: String
    var title: String
    /// The short "why": "31% right in Renal over 42 answers".
    var detail: String
    var symbol: String
    var score: Double
    var action: FocusAction
    /// The subject, for a drill, so its row can show a sparkline.
    var subject: String? = nil
}

/// The pages this one pushes that are not quizzes.
private enum AnalyticsRoute: Hashable {
    case due
    case coverage
    case rules
    case confident
    case reason(MistakeReason)
    /// Progress, subject by subject.
    case bySubject
}

/// The places in the list the rings at the top scroll to.
private enum AnalyticsAnchor {
    static let readiness = "analytics-readiness"
    static let subjectsEmpty = "analytics-subjects-empty"
}
