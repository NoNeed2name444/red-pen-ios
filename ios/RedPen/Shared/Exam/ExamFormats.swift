import Foundation

// The chosen exam's paper: the mock paper's sections and clock, the exam-day
// kit's pacing, and a mock drawn in the blueprint's proportions. Kept apart
// from MockPaper.swift and ExamWeekPlanner.swift so those stay as they were
// for a student with no exam chosen.

extension MockFormat {
    /// The papers an exam offers. A blockwise exam (USMLE, COMLEX, SMLE,
    /// IFOM) is sat as the number of blocks chosen; one whose sections are
    /// sat apart (MRCP's two papers, MRCS A, FMGE's parts) offers each on its
    /// own; anything else is one paper.
    static func papers(for exam: TargetExam, blocks: Int = 2) -> [MockPaperSpec] {
        guard !exam.sections.isEmpty else { return [] }
        if exam.sitsBlockwise {
            let n: Int = min(max(blocks, 1), exam.sections.count)
            let chosen: [MockSectionSpec] = Array(exam.sections.prefix(n))
            let unit: String = chosen[0].title.split(separator: " ").dropLast().joined(separator: " ").lowercased()
            let noun: String = unit.isEmpty ? "block" : unit
            return [MockPaperSpec(id: "\(exam.id)-\(n)", title: "\(exam.shortName), \(n) \(noun)" + (n == 1 ? "" : "s"),
                                  sections: chosen, note: exam.paperNote)]
        }
        if exam.sitsSeparately {
            return exam.sections.enumerated().map { i, section in
                MockPaperSpec(id: "\(exam.id)-p\(i + 1)", title: "\(exam.shortName), \(section.title)",
                              sections: [section], note: exam.paperNote)
            }
        }
        return [MockPaperSpec(id: exam.id, title: "\(exam.shortName) paper", sections: exam.sections, note: exam.paperNote)]
    }
}

extension ExamWeekPlanner {
    /// The paper the exam-day kit paces: one block of a blockwise exam, one
    /// paper of one sat in parts, else the whole paper. "Published" only when
    /// the exam's format is confirmed.
    static func paper(for exam: TargetExam) -> Paper {
        let first: MockSectionSpec = exam.sections.first ?? MockSectionSpec(title: exam.shortName, questions: 60, minutes: 60)
        if exam.sitsBlockwise || exam.sitsSeparately {
            return Paper(name: "\(exam.shortName) \(first.title.lowercased())", questions: first.questions,
                         minutes: first.minutes, published: exam.formatConfirmed)
        }
        let q: Int = exam.sections.reduce(0) { $0 + $1.questions }
        let m: Int = exam.sections.reduce(0) { $0 + $1.minutes }
        return Paper(name: exam.shortName, questions: q, minutes: m, published: exam.formatConfirmed)
    }
}

/// A mock drawn in the blueprint's proportions: each area gets its share of
/// the paper from the questions filed under it, an area the library is short
/// on gives its places to the others, and questions no area claims fill
/// what is left.
enum ExamMock {

    static func select<R: RandomNumberGenerator>(_ pool: [(candidate: MockCandidate, domain: ExamDomain?)],
                                                 wanted: Int, plan: [BlueprintArea],
                                                 using rng: inout R) -> [MockCandidate] {
        var seen = Set<UUID>()
        var byDomain: [ExamDomain: [MockCandidate]] = [:]
        var loose: [MockCandidate] = []
        for entry in pool where seen.insert(entry.candidate.id).inserted {
            if let d = entry.domain, plan.contains(where: { $0.domain == d }) {
                byDomain[d, default: []].append(entry.candidate)
            } else {
                loose.append(entry.candidate)
            }
        }
        for key in Array(byDomain.keys) { byDomain[key]?.shuffle(using: &rng) }
        loose.shuffle(using: &rng)
        let target: Int = min(wanted, seen.count)
        var picked: [MockCandidate] = []
        // rounds of quotas: what one area cannot fill goes to the others
        var remaining: [BlueprintArea] = plan.filter { !(byDomain[$0.domain] ?? []).isEmpty }
        while picked.count < target && !remaining.isEmpty {
            let need: Int = target - picked.count
            let quotas: [(area: BlueprintArea, questions: Int)] = ExamBlueprint.quotas(count: need, plan: remaining)
            var progressed = false
            for row in quotas {
                var list: [MockCandidate] = byDomain[row.area.domain] ?? []
                let take: Int = min(row.questions, list.count)
                if take > 0 {
                    picked += list.prefix(take)
                    list.removeFirst(take)
                    byDomain[row.area.domain] = list
                    progressed = true
                }
            }
            remaining = remaining.filter { !(byDomain[$0.domain] ?? []).isEmpty }
            if !progressed { break }
        }
        if picked.count < target {
            picked += loose.prefix(target - picked.count)
        }
        return Array(picked.prefix(target))
    }
}

extension PassMark {
    /// The chosen exam's rough pass mark, or the track's.
    static func typical(for exam: TargetExam?, track: ExamTrack) -> Double {
        exam?.passMark ?? typical(for: track)
    }
}
