import Foundation

/// What a question writer is told about the chosen exam: its format rules,
/// the blueprint weighting for a set with no single topic, and two or three
/// real exemplars in its style (few-shot). MCQPrompt puts this into every
/// MCQ prompt, on the device and in the cloud.
///
/// This is the honest meaning of "training on the exam's questions": no model
/// is fine-tuned (not possible for free); the writer is shown real, openly
/// licensed items in the exam's style and the exam's rules, every time.
enum ExamPrompt {

    /// The writer's opening line: the family's style (units, guidelines),
    /// naming the exam; or, for an exam whose family is general revision, a
    /// line of its own so NEET-PG is not written as an NBME vignette.
    static func opening(_ exam: TargetExam) -> String {
        if exam.family == .general {
            return "You are writing \(exam.name) single-best-answer questions for a medical student preparing for that exam, in its own style: \(exam.leadIns). Use \(exam.conventions)."
        }
        return exam.family.mcqStyle + " The student is preparing for \(exam.name) specifically: write to its format below."
    }

    /// The format rules, one per line.
    static func formatRules(_ exam: TargetExam) -> [String] {
        let recall: Int = Int((exam.recallShare * 100).rounded())
        var lines: [String] = [
            "EXAM FORMAT - \(exam.name):",
            "- Exactly \(exam.options) options per question.",
            "- Stems of about \(exam.stemWords.lowerBound)-\(exam.stemWords.upperBound) words" +
                (exam.stemWords.upperBound <= 60 ? ": one or two lines, as this exam asks them." : "."),
            "- Ask the way this exam asks: \(exam.leadIns).",
            "- About \(recall)% pure recall questions; the rest clinical.",
            "- Use \(exam.conventions).",
        ]
        if exam.accuracyStrictness >= 0.4 {
            lines.append("- Most questions are management decisions: the keyed answer must be the single next step current guidelines support for THIS patient at THIS point, with distractors that are right at another stage.")
        }
        if let negative = exam.negativeMarking {
            lines.append("- The exam marks \(negative), so distractors must be ones a half-prepared student would pick with confidence.")
        }
        return lines
    }

    /// The blueprint line for a set with no one topic: how the set should
    /// spread across areas, only as far as the source covers them.
    static func weighting(count: Int, plan: [BlueprintArea], examName: String, limit: Int = 8) -> String? {
        let quotas: [(area: BlueprintArea, questions: Int)] = ExamBlueprint.quotas(count: count, plan: plan)
        guard quotas.count > 1 else { return nil }
        let total: Double = plan.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        let top: [String] = quotas.prefix(limit).map { row in
            let pct: Int = Int((row.area.weight / total * 100).rounded())
            return "\(row.area.title) \(pct)% (\(row.questions))"
        }
        return "BLUEPRINT WEIGHTING: \(examName) spreads its questions roughly as " + top.joined(separator: ", ") +
            ". Where the source material covers several of these areas, give each about that many of the \(count) questions, heaviest first; never go outside the source material to fill an area."
    }

    /// The topic to pick exemplars for: the subject line first, then the
    /// start of the source; nil when neither says.
    static func topic(subject: String, source: String) -> ExamDomain? {
        let plain: Bool = subject.isEmpty || subject == "General"
        if !plain, let d = ExamBlueprint.domain(of: subject) { return d }
        let sample: String = String(source.prefix(4000))
        return sample.isEmpty ? nil : ExamBlueprint.domain(of: sample)
    }

    /// Everything the prompt gets for the exam, as lines. `placeholder`
    /// leaves the exemplars for the server to fill per batch (a cloud job).
    static func section(for exam: TargetExam, secondary: TargetExam?, subject: String, source: String,
                        count: Int, exemplars: Int, round: Int = 0, placeholder: Bool = false) -> [String] {
        var lines: [String] = formatRules(exam)
        let plain: Bool = subject.isEmpty || subject == "General"
        if plain {
            let plan: [BlueprintArea] = ExamBlueprint.plan(primary: exam, secondary: secondary)
            if let line = weighting(count: count, plan: plan, examName: exam.name) {
                lines.append("")
                lines.append(line)
            }
        }
        if exemplars > 0 {
            let domain: ExamDomain? = topic(subject: subject, source: source) ?? exam.shares.first?.domain
            let block: String = placeholder
                ? ExamExemplars.placeholder(for: exam, domain: domain, count: exemplars)
                : ExamExemplars.block(for: exam, domain: domain, count: exemplars, round: round)
            if !block.isEmpty {
                lines.append("")
                lines.append(block)
            }
        }
        lines.append("")
        return lines
    }
}
