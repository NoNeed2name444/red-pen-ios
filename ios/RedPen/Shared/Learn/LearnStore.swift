import Foundation

/// The library read through the learning-science pieces: what is secured,
/// what the run-up to the exam asks for, the symptom blocks, and the day's
/// misses. Every quiz built here is temporary, like the drills in
/// StoreStudy, and keeps the questions' own ids so answers land on them.
@MainActor
extension Store {

    // MARK: lock it in

    /// Where every answered question stands.
    func securedStandings() -> [UUID: SecuredRule.Standing] {
        SecuredRule.standings(answerLog)
    }

    /// Each library question's subject, once per id.
    func questionSubjects() -> [UUID: String] {
        var out: [UUID: String] = [:]
        for pick in mcqPicks({ _ in true }) { out[pick.question.id] = Self.subjectName(pick.set) }
        return out
    }

    /// Secured, building and new across the library.
    func securedTotals(_ standings: [UUID: SecuredRule.Standing]? = nil) -> SecuredRule.Ring {
        let known = standings ?? securedStandings()
        let rings = SecuredRule.rings(subjects: questionSubjects(), standings: known)
        var total = SecuredRule.Ring(subject: "All", secured: 0, building: 0, new: 0)
        for r in rings {
            total.secured += r.secured
            total.building += r.building
            total.new += r.new
        }
        return total
    }

    /// Questions one or two days from secured that a right answer today
    /// would move on.
    func lockInPicks(_ standings: [UUID: SecuredRule.Standing]? = nil, now: Date = Date()) -> [QuestionPick] {
        let known = standings ?? securedStandings()
        let picks = mcqPicks { pick in
            if case .building(let n) = known[pick.question.id] ?? .new { return n > 0 }
            return false
        }
        let today = Calendar.current.startOfDay(for: now)
        let rightToday = Set(answerLog.filter { $0.correct && Calendar.current.startOfDay(for: $0.date) == today }
            .map(\.questionId))
        let open = picks.filter { !rightToday.contains($0.question.id) }
        let order = SecuredRule.closeToSecure(open.map(\.question.id), standings: known)
        let byID = Dictionary(open.map { ($0.question.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byID[$0] }
    }

    func lockInQuiz(limit: Int = 20) -> StudySet {
        Self.temporaryQuiz(named: "Lock it in", subject: "Lock it in",
                           from: Array(lockInPicks().prefix(limit)).shuffled())
    }

    // MARK: mistakes and the day's rhythm

    /// Questions whose last answer was wrong.
    var lastWrongPicks: [QuestionPick] {
        mcqPicks { self.answerHistory[$0.question.id]?.last == false }
    }

    func mistakesQuiz(limit: Int = 30) -> StudySet {
        Self.temporaryQuiz(named: "Your mistakes", subject: "Mistakes",
                           from: Array(lastWrongPicks.shuffled().prefix(limit)))
    }

    /// The library's questions for these ids, in the ids' order.
    func picks(ids: [UUID]) -> [QuestionPick] {
        let wanted = Set(ids)
        let found = mcqPicks { wanted.contains($0.question.id) }
        let byID = Dictionary(found.map { ($0.question.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }

    /// Today's misses, for the evening re-read.
    func bedtimePicks(now: Date = Date()) -> [QuestionPick] {
        picks(ids: StudyRhythm.missed(on: now, events: answerLog))
    }

    /// Yesterday's misses not yet answered today, for the morning check.
    func morningPicks(now: Date = Date()) -> [QuestionPick] {
        picks(ids: StudyRhythm.morningItems(now: now, events: answerLog))
    }

    func morningCheckQuiz(now: Date = Date()) -> StudySet {
        Self.temporaryQuiz(named: "Morning check", subject: "Morning check",
                           from: Array(morningPicks(now: now).prefix(10)))
    }

    /// One question as a quiz of its own (the question of the day, opened
    /// from its notification).
    func singleQuestionQuiz(_ id: UUID) -> StudySet? {
        guard let pick = picks(ids: [id]).first else { return nil }
        return Self.temporaryQuiz(named: "Question of the day", subject: Self.subjectName(pick.set), from: [pick])
    }

    /// Today's question for the notification: the weakest subject first.
    func questionOfTheDay(now: Date = Date()) -> QuestionPick? {
        let all = mcqPicks { _ in true }
        let candidates = all.map {
            StudyRhythm.Candidate(id: $0.question.id, subject: Self.subjectName($0.set),
                                  optionCount: $0.question.options.count)
        }
        let weakest = subjectStats().filter { $0.answered > 0 }.map(\.subject)
        guard let id = StudyRhythm.questionOfTheDay(candidates, weakestFirst: weakest,
                                                    standings: securedStandings(), day: now) else { return nil }
        return all.first { $0.question.id == id }
    }

    // MARK: exam week

    /// examSituation, remembered until the library, the due count or the
    /// hour changes - the Today card asks on every redraw of the library.
    func cachedSituation(dueCards: Int, now: Date = Date()) -> ExamWeekPlanner.Situation {
        let hour = Int(now.timeIntervalSince1970 / 3600)
        let mocks = ExamStore.shared.mocks.first?.id.uuidString ?? "-"
        let key = "\(changeCount)-\(dueCards)-\(hour)-\(ExamCap.storedDate()?.timeIntervalSince1970 ?? 0)-\(mocks)"
        if let memo = LearnMarks.situationMemo, memo.key == key { return memo.value }
        let value = examSituation(dueCards: dueCards, now: now)
        LearnMarks.situationMemo = (key, value)
        return value
    }

    /// Everything the lift-off button weighs up.
    func examSituation(dueCards: Int, now: Date = Date()) -> ExamWeekPlanner.Situation {
        let exam = ExamCap.storedDate()
        let standings = securedStandings()
        let weakest = subjectStats().first { $0.answered > 0 && $0.accuracy < 0.8 }?.subject
        let untried = mcqPicks { (self.answerHistory[$0.question.id] ?? []).isEmpty }.count
        return ExamWeekPlanner.Situation(
            phase: ExamWeekPlanner.phase(exam: exam, now: now),
            dueCards: dueCards,
            confidentErrors: confidentMistakePicks.count,
            missed: lastWrongPicks.count,
            flagged: flaggedQuestions.count,
            closeToSecure: lockInPicks(standings, now: now).count,
            untried: untried,
            morningCheck: LearnMarks.morningCheckWanted(now: now) ? morningPicks(now: now).count : 0,
            mockDone: LearnMarks.mockDone(for: exam),
            weakestSubject: weakest)
    }

    // MARK: symptom blocks

    /// Every library question as the symptom blocks see it.
    func symptomItems() -> [SymptomBlocks.Item] {
        mcqPicks { _ in true }.compactMap { pick in
            let q = pick.question
            guard q.options.indices.contains(q.correctIndex) else { return nil }
            return SymptomBlocks.Item(id: q.id, stem: q.stem, answer: q.options[q.correctIndex])
        }
    }

    /// A block's questions, interleaved, at most `limit`.
    func symptomQuiz(_ block: SymptomBlocks.Block, limit: Int = 20) -> StudySet {
        let wanted = Set(block.ids)
        let items = symptomItems().filter { wanted.contains($0.id) }
        let order = SymptomBlocks.interleaved(items).prefix(limit).map(\.id)
        return Self.temporaryQuiz(named: block.presentation.blockTitle, subject: block.presentation.name,
                                  from: picks(ids: Array(order)))
    }
}

/// Small marks kept on this device: whether the mock was sat for this exam
/// date (read from ExamStore's finished sittings), whether the morning check was done today, which sets have had their
/// pretest.
@MainActor
enum LearnMarks {
    private static let morningKey = "learn.morning.done"
    private static let pretestKey = "learn.pretest.seen"

    /// The last situation worked out, and what it was worked out from.
    static var situationMemo: (key: String, value: ExamWeekPlanner.Situation)?
    static var forecastMemo: (key: String, value: RetentionForecast.Forecast)?

    /// Forgets the memo, after something it does not watch changed (the
    /// morning check being marked).
    static func invalidate() { situationMemo = nil }

    /// Whether a mock paper (Features/Mock) was finished in the run-up to
    /// this exam date: from the start of the mock window (T-10) on. Only a
    /// sitting that reached its results counts - one started and left does
    /// not - so the lift-off button keeps offering it until it is sat.
    static func mockDone(for exam: Date?) -> Bool {
        guard let exam else { return false }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: exam)
        guard let opens = calendar.date(byAdding: .day, value: -10, to: day),
              let closes = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return ExamStore.shared.mocks.contains { $0.date >= opens && $0.date < closes }
    }

    /// The morning check is offered until it is opened, and only in the
    /// morning (before noon).
    static func morningCheckWanted(now: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: now)
        guard hour >= 4 && hour < 12 else { return false }
        return UserDefaults.standard.string(forKey: morningKey) != StudyLog.key(for: now)
    }

    static func markMorningDone(now: Date = Date()) {
        UserDefaults.standard.set(StudyLog.key(for: now), forKey: morningKey)
        invalidate()
    }

    /// Whether the pretest has been offered for a set.
    static func pretestSeen(_ setID: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: pretestKey) ?? []).contains(setID.uuidString)
    }

    static func markPretestSeen(_ setID: UUID) {
        var seen = UserDefaults.standard.stringArray(forKey: pretestKey) ?? []
        guard !seen.contains(setID.uuidString) else { return }
        seen.append(setID.uuidString)
        // a few hundred sets is more than anybody opens; keep the newest
        UserDefaults.standard.set(Array(seen.suffix(500)), forKey: pretestKey)
    }
}

extension ReviewStore {
    /// The exam-day forecast for every deck in the library, remembered until
    /// the schedule, the library or the hour changes.
    func examForecast(_ sets: [StudySet], libraryVersion: Int, now: Date = Date()) -> RetentionForecast.Forecast {
        let exam = ExamCap.storedDate()
        let hour = Int(now.timeIntervalSince1970 / 3600)
        let key = "\(changeCount)-\(libraryVersion)-\(hour)-\(exam?.timeIntervalSince1970 ?? 0)"
        if let memo = LearnMarks.forecastMemo, memo.key == key { return memo.value }
        let ids = sets.flatMap { $0.deckCards.map(\.id) }
        let value = RetentionForecast.forecast(cardIDs: ids, records: records, now: now, exam: exam)
        LearnMarks.forecastMemo = (key, value)
        return value
    }
}

@MainActor
extension Store {
    /// Questions never answered, mixed across the library - "something new"
    /// when nothing else is waiting. Never offered in exam week.
    func untriedQuiz(limit: Int = 20) -> StudySet {
        let fresh = mcqPicks { (self.answerHistory[$0.question.id] ?? []).isEmpty }
        return Self.temporaryQuiz(named: "New questions", subject: "Mixed",
                                  from: Array(fresh.shuffled().prefix(limit)))
    }
}
