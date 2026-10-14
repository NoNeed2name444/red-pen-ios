import Foundation

/// Accuracy at one confidence level: how often "Sure" really was right.
struct CalibrationRow: Hashable, Identifiable {
    var confidence: AnswerConfidence
    var answered: Int
    var correct: Int
    var id: String { confidence.rawValue }
    var accuracy: Double { answered == 0 ? 0 : Double(correct) / Double(answered) }
}

/// One subject's rules on the rule sheet.
struct RuleGroup: Hashable, Identifiable {
    var subject: String
    var rules: [StudyRule]
    var id: String { subject }
}

/// How often one reason was given for a lost mark.
struct ReasonShare: Hashable, Identifiable {
    var reason: MistakeReason
    var count: Int
    var share: Double
    var id: String { reason.rawValue }
}

/// The parts of the library about why marks are lost and what to do about it:
/// the reasons given for wrong answers, confidence, the rule sheet, and the
/// readiness estimate. Every quiz built here is temporary, like the drills in
/// StoreStudy.
extension Store {

    /// How far back "Why you lose marks" looks.
    static let reasonWindowDays = 30

    // MARK: why a mark was lost

    /// Remembers why a question was got wrong; nil forgets it.
    func noteMistake(_ reason: MistakeReason?, for questionId: UUID) {
        if let reason {
            mistakeReasons[questionId] = MistakeNote(reason: reason)
        } else {
            guard mistakeReasons[questionId] != nil else { return }
            mistakeReasons[questionId] = nil
        }
        save()
    }

    /// The reasons given within the window, as shares of all given, most
    /// common first. Reasons never given are left out.
    func reasonShares(days: Int = Store.reasonWindowDays, now: Date = Date()) -> [ReasonShare] {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        var counts: [MistakeReason: Int] = [:]
        for note in mistakeReasons.values where note.date >= since {
            counts[note.reason, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return counts.map { ReasonShare(reason: $0.key, count: $0.value,
                                        share: Double($0.value) / Double(total)) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.reason.rawValue < b.reason.rawValue
            }
    }

    /// The questions still in the library last got wrong for `reason` within
    /// the window, newest first.
    func picks(for reason: MistakeReason, days: Int = Store.reasonWindowDays,
               now: Date = Date()) -> [QuestionPick] {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        let notes = mistakeReasons.filter { $0.value.reason == reason && $0.value.date >= since }
        guard !notes.isEmpty else { return [] }
        return mcqPicks { notes[$0.question.id] != nil }
            .sorted { (notes[$0.question.id]?.date ?? .distantPast) > (notes[$1.question.id]?.date ?? .distantPast) }
    }

    /// A quiz of the questions missed for `reason`, up to `limit`.
    func reasonQuiz(_ reason: MistakeReason, named name: String, limit: Int = 20) -> StudySet {
        let chosen = Array(picks(for: reason).prefix(limit)).shuffled()
        return Self.temporaryQuiz(named: name, subject: name, from: chosen)
    }

    /// Ten questions for a timed drill: those lost to the clock first, then
    /// the ones last got wrong, then anything, so there are always ten when
    /// the library has them.
    func timedDrill(limit: Int = 10) -> StudySet {
        var chosen = picks(for: .outOfTime)
        var seen = Set(chosen.map(\.question.id))
        if chosen.count < limit {
            let wrong = mcqPicks { pick in
                !seen.contains(pick.question.id) && self.answerHistory[pick.question.id]?.last == false
            }.shuffled()
            chosen += wrong
            seen.formUnion(wrong.map(\.question.id))
        }
        if chosen.count < limit {
            chosen += mcqPicks { !seen.contains($0.question.id) }.shuffled()
        }
        return Self.temporaryQuiz(named: "Timed drill", subject: "Timed drill",
                                  from: Array(chosen.prefix(limit)).shuffled())
    }

    // MARK: confidence

    /// Accuracy at each confidence level, over the whole dated log.
    func calibration() -> [CalibrationRow] {
        var rows: [AnswerConfidence: CalibrationRow] = [:]
        for event in answerLog {
            guard let level = event.confidence else { continue }
            var row = rows[level] ?? CalibrationRow(confidence: level, answered: 0, correct: 0)
            row.answered += 1
            if event.correct { row.correct += 1 }
            rows[level] = row
        }
        return AnswerConfidence.allCases.compactMap { rows[$0] }
    }

    /// The questions got wrong while sure, still in the library.
    var confidentMistakePicks: [QuestionPick] {
        let ids = confidentMistakeIds
        guard !ids.isEmpty else { return [] }
        return mcqPicks { ids.contains($0.question.id) }
    }

    /// A quiz of the confident mistakes, up to `limit`.
    func confidentMistakesQuiz(limit: Int = 20) -> StudySet {
        Self.temporaryQuiz(named: "Confident mistakes", subject: "Confident mistakes",
                           from: Array(confidentMistakePicks.shuffled().prefix(limit)))
    }

    // MARK: rule sheet

    /// Rules on the sheet, grouped by subject, subjects in order, each
    /// subject's rules newest first.
    var rulesBySubject: [RuleGroup] {
        let groups = Dictionary(grouping: Array(ruleSheet.values), by: { (rule: StudyRule) in rule.subject })
        let names = groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return names.map { name in
            RuleGroup(subject: name, rules: (groups[name] ?? []).sorted { $0.date > $1.date })
        }
    }

    /// Of `questions`, the ones with no rule yet.
    func questionsWithoutRules(_ questions: [MCQQuestion]) -> [MCQQuestion] {
        var seen: Set<UUID> = []
        return questions.filter { ruleSheet[$0.id] == nil && seen.insert($0.id).inserted }
    }

    /// Adds a plain rule for each question that has none; returns how many.
    @discardableResult
    func addRules(for questions: [MCQQuestion], subject: String) -> Int {
        let fresh = questionsWithoutRules(questions)
        guard !fresh.isEmpty else { return 0 }
        let name = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        for question in fresh {
            ruleSheet[question.id] = RuleWriter.plainRule(for: question,
                                                          subject: name.isEmpty ? "General" : name)
        }
        save()
        return fresh.count
    }

    /// Questions in the library whose last answer was wrong and that have no
    /// rule yet, each with its subject.
    var missedWithoutRules: [QuestionPick] {
        mcqPicks { self.answerHistory[$0.question.id]?.last == false && self.ruleSheet[$0.question.id] == nil }
    }

    /// Adds plain rules for every question last got wrong; returns how many.
    @discardableResult
    func addRulesForMissed() -> Int {
        let picks = missedWithoutRules
        guard !picks.isEmpty else { return 0 }
        for pick in picks {
            ruleSheet[pick.question.id] = RuleWriter.plainRule(for: pick.question,
                                                              subject: Self.subjectName(pick.set))
        }
        save()
        return picks.count
    }

    /// Puts a model's wording in place of the plain lines, by rule id.
    func applyWrittenRules(_ lines: [UUID: String]) {
        var changed = false
        for (id, line) in lines {
            guard var rule = ruleSheet[id] else { continue }
            rule.text = line
            rule.byAI = true
            ruleSheet[id] = rule
            changed = true
        }
        if changed { save() }
    }

    func deleteRule(_ id: UUID) {
        guard ruleSheet[id] != nil else { return }
        ruleSheet[id] = nil
        save()
    }

    /// The whole sheet as plain text, for sharing.
    var ruleSheetText: String {
        var out = ["Rule sheet", ""]
        for group in rulesBySubject {
            out.append(group.subject.uppercased())
            for rule in group.rules {
                out.append("\u{2022} \(rule.text)")
                if !rule.detail.isEmpty && !rule.byAI { out.append("  \(rule.detail)") }
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    // MARK: readiness

    /// Right or wrong for the latest answers, newest first. The dated log
    /// once there is enough of it; before then, the older per-question
    /// history, which has no dates and so no order.
    var recentAnswers: [Bool] {
        if answerLog.count >= Readiness.minimumAnswers {
            return answerLog.suffix(Readiness.window).reversed().map(\.correct)
        }
        return Array(answerHistory.values.flatMap { $0 }.prefix(Readiness.window))
    }

    func readiness(dueCards: Int, track: ExamTrack = .current) -> ReadinessEstimate? {
        Readiness.estimate(recent: recentAnswers, subjects: subjectStats(), dueCards: dueCards,
                           passMark: PassMark.typical(for: ExamChoice.effective(for: track), track: track))
    }
}

extension Store {
    /// Whether the dated history includes the personal build's made-up
    /// examples, so the screens built on it can say so.
    var includesExampleData: Bool {
        answerLog.contains { $0.isExample == true }
    }
}
