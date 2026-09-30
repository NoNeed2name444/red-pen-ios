import Foundation

// An exam-faithful mock paper: the real paper's length and clock for the
// student's exam, drawn from their own library, with nothing said about right
// or wrong until the end.
//
// Foundation only, so the assembly and the marking can be tested on Linux.

/// One timed part of a sitting: a PLAB paper, an MRCP paper, one USMLE block.
/// A section's time is its own: time left over does not carry into the next,
/// and once a section is closed its questions cannot be gone back to.
struct MockSectionSpec: Hashable, Codable {
    var title: String
    var questions: Int
    var minutes: Int
}

/// A paper as the exam sets it.
struct MockPaperSpec: Hashable, Identifiable {
    var id: String
    var title: String
    var sections: [MockSectionSpec]
    /// A plain line on how the real exam runs it.
    var note: String

    var questionCount: Int { sections.reduce(0) { $0 + $1.questions } }
    var minutes: Int { sections.reduce(0) { $0 + $1.minutes } }
}

/// The papers each exam sits.
enum MockFormat {
    /// USMLE Step 1 sits up to seven 60-minute blocks of up to 40 questions.
    static let usmleBlockQuestions = 40
    static let usmleBlockMinutes = 60
    static let usmleMaxBlocks = 7

    /// The papers a track offers. USMLE's is built from a count of blocks.
    static func papers(for track: ExamTrack, usmleBlocks: Int = 2) -> [MockPaperSpec] {
        switch track {
        case .plab:
            let s = MockSectionSpec(title: "PLAB 1", questions: 180, minutes: 180)
            return [MockPaperSpec(id: "plab1", title: "PLAB 1 paper", sections: [s],
                                  note: "180 single-best-answer questions in 3 hours, as the GMC sets it.")]
        case .mrcp:
            let one = MockSectionSpec(title: "Paper 1", questions: 100, minutes: 180)
            let two = MockSectionSpec(title: "Paper 2", questions: 100, minutes: 180)
            let note: String = "MRCP(UK) Part 1 is two papers of 100 best-of-five questions, 3 hours each, on one day. Sit one now and the other later."
            return [MockPaperSpec(id: "mrcp1", title: "MRCP Part 1, paper 1", sections: [one], note: note),
                    MockPaperSpec(id: "mrcp2", title: "MRCP Part 1, paper 2", sections: [two], note: note)]
        case .mrcs:
            // the colleges publish the times, not a fixed count: Part A's
            // pace is about a question a minute
            let one = MockSectionSpec(title: "Paper 1", questions: 180, minutes: 180)
            let two = MockSectionSpec(title: "Paper 2", questions: 120, minutes: 120)
            let note: String = "MRCS Part A is Applied Basic Sciences (3 hours) and Principles of Surgery-in-General (2 hours) on one day. The colleges publish the times rather than a fixed question count, so this keeps Part A's pace of about a question a minute."
            return [MockPaperSpec(id: "mrcsa1", title: "MRCS A, Applied Basic Sciences", sections: [one], note: note),
                    MockPaperSpec(id: "mrcsa2", title: "MRCS A, Principles of Surgery", sections: [two], note: note)]
        case .usmle:
            let count: Int = min(max(usmleBlocks, 1), usmleMaxBlocks)
            let blocks: [MockSectionSpec] = (1...count).map { n in
                MockSectionSpec(title: "Block \(n)", questions: usmleBlockQuestions, minutes: usmleBlockMinutes)
            }
            let note: String = "Step 1-style blocks: up to 40 questions in 60 minutes each. The real exam has up to seven, with break time between them."
            return [MockPaperSpec(id: "usmle\(count)", title: "USMLE-style, \(count) block" + (count == 1 ? "" : "s"),
                                  sections: blocks, note: note)]
        case .general:
            let s = MockSectionSpec(title: "Paper", questions: 100, minutes: 125)
            return [MockPaperSpec(id: "general", title: "Practice paper", sections: [s],
                                  note: "100 questions in 2 hours 5 minutes. Pick your exam in Settings for its real paper.")]
        }
    }
}

/// A question that could go into the paper: only what assembly needs.
struct MockCandidate: Hashable {
    var id: UUID
    var subject: String
}

/// A paper put together from the library.
struct MockAssembly: Hashable {
    /// The sections as they will be sat. Short when the library is short:
    /// each keeps the real paper's pace, so its time shrinks with it.
    var sections: [MockSectionSpec]
    /// Question ids, section by section.
    var questionIds: [[UUID]]
    /// How many the real paper has.
    var wanted: Int
    /// Said before starting, when the library cannot fill the paper.
    var shortfallNote: String?

    var count: Int { questionIds.reduce(0) { $0 + $1.count } }
    var isShort: Bool { count < wanted }
}

enum MockAssembler {
    /// Below this there is no paper worth the name.
    static let minimumQuestions = 10

    /// Draws a paper from `pool`, spreading it across subjects the way a real
    /// paper spreads across the syllabus: one question from each subject in
    /// turn, so a big deck in one subject cannot fill the paper on its own.
    /// Order within the paper is then shuffled, so subjects do not come in runs.
    /// Nil when there are fewer than `minimumQuestions`.
    static func assemble<R: RandomNumberGenerator>(_ spec: MockPaperSpec, from pool: [MockCandidate],
                                                   using rng: inout R) -> MockAssembly? {
        let unique: [MockCandidate] = dedupe(pool)
        guard unique.count >= minimumQuestions else { return nil }
        let wanted: Int = spec.questionCount
        let picked: [MockCandidate] = spread(unique, take: wanted, using: &rng)
        var order: [MockCandidate] = picked
        order.shuffle(using: &rng)
        let sections: [MockSectionSpec] = fitted(spec.sections, to: order.count)
        var ids: [[UUID]] = []
        var at: Int = 0
        for section in sections {
            let end: Int = at + section.questions
            ids.append(order[at..<end].map(\.id))
            at = end
        }
        let note: String? = order.count < wanted ? shortfall(have: order.count, spec: spec, sections: sections) : nil
        return MockAssembly(sections: sections, questionIds: ids, wanted: wanted, shortfallNote: note)
    }

    static func assemble(_ spec: MockPaperSpec, from pool: [MockCandidate]) -> MockAssembly? {
        var rng = SystemRandomNumberGenerator()
        return assemble(spec, from: pool, using: &rng)
    }

    /// What is said when the library can't fill the paper.
    static func shortfall(have: Int, spec: MockPaperSpec, sections: [MockSectionSpec]) -> String {
        let minutes: Int = sections.reduce(0) { $0 + $1.minutes }
        return "Your library has \(have) questions; \(spec.title) has \(spec.questionCount). This mock uses all \(have) at the real paper's pace (\(minutes) min), so it is shorter than the exam. Make more question sets to sit the full paper."
    }

    static func dedupe(_ pool: [MockCandidate]) -> [MockCandidate] {
        var seen: Set<UUID> = []
        return pool.filter { seen.insert($0.id).inserted }
    }

    /// Round-robin across subjects, each subject's own order shuffled.
    static func spread<R: RandomNumberGenerator>(_ pool: [MockCandidate], take: Int,
                                                 using rng: inout R) -> [MockCandidate] {
        var bySubject: [String: [MockCandidate]] = [:]
        for c in pool { bySubject[c.subject, default: []].append(c) }
        var subjects: [String] = bySubject.keys.sorted()
        subjects.shuffle(using: &rng)
        let queues: [[MockCandidate]] = subjects.map { name in
            var list: [MockCandidate] = bySubject[name] ?? []
            list.shuffle(using: &rng)
            return list
        }
        var out: [MockCandidate] = []
        var round: Int = 0
        while out.count < take {
            var any: Bool = false
            for i in queues.indices where round < queues[i].count {
                any = true
                out.append(queues[i][round])
                if out.count == take { break }
            }
            if !any { break }
            round += 1
        }
        return out
    }

    /// The sections cut down to `count` questions: whole sections first, and
    /// the last one short, each at the real paper's pace (at least a minute).
    static func fitted(_ sections: [MockSectionSpec], to count: Int) -> [MockSectionSpec] {
        var left: Int = count
        var out: [MockSectionSpec] = []
        for s in sections where left > 0 {
            let n: Int = min(s.questions, left)
            var cut = s
            cut.questions = n
            if n < s.questions {
                let scaled: Double = Double(s.minutes) * Double(n) / Double(max(1, s.questions))
                cut.minutes = max(1, Int(scaled.rounded(.up)))
            }
            out.append(cut)
            left -= n
        }
        return out
    }
}

// MARK: - marking

/// One answer in a sitting, marked after the end.
struct MockMark: Hashable, Codable {
    var questionId: UUID
    var subject: String
    /// Nil when it was left unanswered.
    var picked: Int?
    var correct: Bool
    var flagged: Bool = false
    /// Seconds the question was on screen, in total.
    var seconds: Double = 0
}

/// One subject's line on the results page.
struct MockSubjectScore: Hashable, Identifiable {
    var subject: String
    var total: Int
    var answered: Int
    var correct: Int
    var id: String { subject }
    var fraction: Double { total == 0 ? 0 : Double(correct) / Double(total) }
}

/// The results of a sitting.
struct MockResult: Hashable {
    var marks: [MockMark]
    var passMark: Double

    var total: Int { marks.count }
    var correct: Int { marks.filter(\.correct).count }
    var unanswered: Int { marks.filter { $0.picked == nil }.count }
    var fraction: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    var passed: Bool { fraction >= passMark }

    /// By subject, weakest first; ties by name.
    var bySubject: [MockSubjectScore] {
        var rows: [String: MockSubjectScore] = [:]
        for m in marks {
            var row = rows[m.subject] ?? MockSubjectScore(subject: m.subject, total: 0, answered: 0, correct: 0)
            row.total += 1
            if m.picked != nil { row.answered += 1 }
            if m.correct { row.correct += 1 }
            rows[m.subject] = row
        }
        return rows.values.sorted { a, b in
            if a.fraction != b.fraction { return a.fraction < b.fraction }
            return a.subject < b.subject
        }
    }

    /// Average seconds per answered question.
    var secondsPerQuestion: Double {
        let spent: Double = marks.reduce(0) { $0 + $1.seconds }
        return total == 0 ? 0 : spent / Double(total)
    }
}

/// Where the student should be by now, the checkpoint pacing on the clock:
/// "Q60 by 1:00".
enum MockPacing {
    /// The question number the student should have reached `elapsed`
    /// seconds into a section of `questions` over `minutes`.
    static func target(elapsed: Double, questions: Int, minutes: Int) -> Int {
        let whole: Double = Double(max(1, minutes)) * 60
        let share: Double = min(1, max(0, elapsed / whole))
        return Int((share * Double(questions)).rounded(.down))
    }
}

/// A small seeded generator for repeatable assembly in tests.
struct MockSeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
