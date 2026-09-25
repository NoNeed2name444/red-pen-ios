import Foundation

/// One question together with the set it lives in - the set is needed for
/// its subject and for the pictures the question's `imageIndex` points into.
struct QuestionPick {
    var set: StudySet
    var question: MCQQuestion
}

/// How one subject is going, across every MCQ set filed under it.
struct SubjectStats: Identifiable, Hashable {
    var subject: String
    /// Distinct questions in the library under this subject.
    var questions: Int
    /// Answers checked, counting a question answered twice as two.
    var answered: Int
    var correct: Int

    var id: String { subject }
    var accuracy: Double { answered == 0 ? 0 : Double(correct) / Double(answered) }
}

/// The parts of the library that are about how the studying is going rather
/// than what is being studied: flags, the answer history, and the quizzes
/// put together from them.
///
/// Every quiz built here is temporary. It is opened, not saved, so a drill or
/// a flagged-questions round never turns up as a new set in the library.
/// Question ids are kept as they are, so a flag set or an answer given in one
/// of these quizzes lands on the real question.
extension Store {

    /// How many answers per question are remembered. Enough to see whether a
    /// question is still being missed; old enough history says nothing.
    static let historyDepth = 10

    /// How many dated answers are kept across every question - comfortably
    /// more than the 200 the readiness estimate reads, and small on disk.
    static let answerLogDepth = 2_000

    // MARK: flags

    func toggleFlag(_ id: UUID) {
        if flagged.contains(id) { flagged.remove(id) } else { flagged.insert(id) }
        save()
    }

    /// Every flagged question still in the library, once each - a question
    /// copied into a Mistakes set keeps its id, and should not come up twice.
    var flaggedQuestions: [QuestionPick] {
        guard !flagged.isEmpty else { return [] }
        if let memo = flaggedMemo, memo.at == changeCount { return memo.picks }
        let picks: [QuestionPick] = mcqPicks { self.flagged.contains($0.question.id) }
        flaggedMemo = (at: changeCount, picks: picks)
        return picks
    }

    // MARK: answer history

    /// Remembers one checked answer.
    ///
    /// Only for a question that is really in the library: a quiz made on the
    /// spot from a deck of cards has questions that exist for one sitting, and
    /// their history would be rows nothing could ever read.
    ///
    /// `saving: false` is for a caller about to save the library anyway -
    /// the quiz saves its position after every answer, and the library file
    /// is the whole of everything, so writing it twice per tap is waste.
    ///
    /// `confidence` is how sure the student said they were before checking,
    /// when they said; it goes into the dated log with the answer.
    ///
    /// `picked` is the option chosen, as its index in the question's own
    /// option list (not the shuffled slot), so a wrong answer can later show
    /// what was chosen.
    ///
    /// `hinted` is whether the attending's hint was shown first: kept on the
    /// dated log so the answer counts as right "with help".
    func recordAnswer(_ questionId: UUID, correct: Bool, confidence: AnswerConfidence? = nil,
                      picked: Int? = nil, hinted: Bool = false, saving: Bool = true) {
        guard library.contains(where: { set in
            set.kind == .mcq && set.questions.contains { $0.id == questionId }
        }) else { return }
        var past = answerHistory[questionId] ?? []
        past.append(correct)
        answerHistory[questionId] = Array(past.suffix(Self.historyDepth))
        var event = AnswerEvent(questionId: questionId, correct: correct, confidence: confidence,
                                picked: picked)
        if hinted { event.hinted = true }
        answerLog.append(event)
        if answerLog.count > Self.answerLogDepth {
            answerLog.removeFirst(answerLog.count - Self.answerLogDepth)
        }
        if saving { save() }
    }

    /// Questions whose most recent answer was wrong although the student had
    /// said they were sure - the misconceptions, which are worth more
    /// attention than the honest guesses.
    var confidentMistakeIds: Set<UUID> {
        var latest: [UUID: AnswerEvent] = [:]
        for event in answerLog { latest[event.questionId] = event }
        return Set(latest.values.filter { !$0.correct && $0.confidence == .sure }.map(\.questionId))
    }

    /// Accuracy per subject, weakest first; subjects never answered go last.
    func subjectStats() -> [SubjectStats] {
        var bySubject: [String: SubjectStats] = [:]
        for pick in mcqPicks({ _ in true }) {
            let subject = Self.subjectName(pick.set)
            var stats = bySubject[subject] ?? SubjectStats(subject: subject, questions: 0, answered: 0, correct: 0)
            stats.questions += 1
            let past = answerHistory[pick.question.id] ?? []
            stats.answered += past.count
            stats.correct += past.filter { $0 }.count
            bySubject[subject] = stats
        }
        return bySubject.values.sorted { a, b in
            if (a.answered == 0) != (b.answered == 0) { return b.answered == 0 }
            if a.accuracy != b.accuracy { return a.accuracy < b.accuracy }
            return a.subject < b.subject
        }
    }

    /// Up to `limit` questions from one subject, the ones being missed first:
    /// those got wrong while sure, then those whose last answer was wrong,
    /// then those ever got wrong, then those never tried, and only then the
    /// ones always got right.
    func drill(subject: String, limit: Int = 20) -> StudySet {
        let picks = mcqPicks { Self.subjectName($0.set) == subject }
        let confident = confidentMistakeIds
        var confidentWrong: [QuestionPick] = []
        var lastWrong: [QuestionPick] = [], everWrong: [QuestionPick] = []
        var untried: [QuestionPick] = [], rest: [QuestionPick] = []
        for pick in picks {
            let past = answerHistory[pick.question.id] ?? []
            if confident.contains(pick.question.id) { confidentWrong.append(pick) }
            else if past.last == false { lastWrong.append(pick) }
            else if past.contains(false) { everWrong.append(pick) }
            else if past.isEmpty { untried.append(pick) }
            else { rest.append(pick) }
        }
        let chosen = Array((confidentWrong.shuffled() + lastWrong.shuffled() + everWrong.shuffled()
                            + untried.shuffled() + rest.shuffled()).prefix(limit))
        return Self.temporaryQuiz(named: "Drill \u{2013} \(subject)", subject: subject,
                                  from: chosen.shuffled())
    }

    // MARK: building a temporary quiz

    /// A quiz of these questions, not saved anywhere.
    ///
    /// Each set's pictures are copied in once and the questions' picture
    /// numbers moved along to match, the same re-basing `combine` does; a
    /// question pointing at a picture its set no longer has loses the
    /// picture rather than showing somebody else's.
    static func temporaryQuiz(named name: String, subject: String, from picks: [QuestionPick]) -> StudySet {
        var out = StudySet(name: name, subject: subject, kind: .mcq)
        var bases: [UUID: Int] = [:]
        for pick in picks {
            var q = pick.question
            if let i = q.imageIndex {
                if pick.set.images.indices.contains(i) {
                    let base: Int
                    if let known = bases[pick.set.id] {
                        base = known
                    } else {
                        base = out.images.count
                        out.images.append(contentsOf: pick.set.images)
                        bases[pick.set.id] = base
                    }
                    q.imageIndex = i + base
                } else {
                    q.imageIndex = nil
                }
            }
            out.questions.append(q)
        }
        return out
    }

    /// Every MCQ question in the library that passes `keep`, once per id.
    func mcqPicks(_ keep: (QuestionPick) -> Bool) -> [QuestionPick] {
        var seen: Set<UUID> = []
        var out: [QuestionPick] = []
        for set in library where set.kind == .mcq {
            for question in set.questions where !seen.contains(question.id) {
                let pick = QuestionPick(set: set, question: question)
                guard keep(pick) else { continue }
                seen.insert(question.id)
                out.append(pick)
            }
        }
        return out
    }

    /// A set's subject as the Progress screen groups it: blank is "General".
    static func subjectName(_ set: StudySet) -> String {
        let trimmed = set.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "General" : trimmed
    }
}
