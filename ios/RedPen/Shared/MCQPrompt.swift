import Foundation

/// The instructions sent to whichever model is writing the questions.
///
/// Split out of MCQGenerator because it is shared: Apple's on-device model and
/// the downloaded Gemma fallback are given the same rules, and only the last
/// paragraph differs - Apple's `@Generable` guarantees the output shape, so it
/// is not asked for JSON.
///
/// The rules themselves are carried over from the web app's `buildPrompt()`,
/// including the two item-writing tells students actually report: a distractor
/// that can be eliminated on sight, and the longest option being the answer.
extension MCQGenerator {

    /// How much of the pasted source text is actually sent per generation
    /// call - matches the web app's MAX_PROMPT_CHARS.
    static var maxPromptChars: Int { 45_000 }

    static func buildPrompt(sourceText: String, count: Int, subject: String, highYield: Bool,
                            requestJSONShape: Bool = false,
                            alreadyAsked: [MCQCoverage.Asked] = [],
                            exam: ExamTrack = .current) -> String {
        var lines: [String] = [
            exam.mcqStyle,
            "",
        ]
        if !sourceText.isEmpty {
            lines.append("SOURCE MATERIAL (the student's own notes — use ONLY facts found in it):")
            lines.append("\"\"\"")
            lines.append(sourceText)
            lines.append("\"\"\"")
            lines.append("")
        }
        if !subject.isEmpty && subject != "General" {
            lines.append("Topic to focus on: \"\(subject)\". Every question in this set must specifically test this topic" +
                (sourceText.isEmpty ? "" : " — draw only on the parts of the source material relevant to it, and ignore parts of the source that aren't") +
                ". Interpret the topic as written (it may name a disease, a drug or drug class, a mechanism, a lab test, an exam theme, or anything else) and build the whole set around it rather than around the source material's overall subject.")
            lines.append("A topic being given does not mean a narrow set: aim for COMPREHENSIVE coverage of that topic. Identify every distinct fact, mechanism, subtype, complication, diagnostic criterion, or exam angle the source material offers on it — not just the first or most obvious one — and spread the \(count) questions across all of them in rough proportion to how much the source covers each, rather than writing several questions that circle back to the same one or two facts.")
            lines.append("")
        } else {
            lines.append("No specific topic was given, so aim for comprehensive coverage" +
                (!sourceText.isEmpty
                    ? " of the source material: identify every distinct medically-relevant fact, concept, finding, or topic it contains — not just the first or most prominent one — and make sure the set as a whole tests across all of them, in rough proportion to how much of the source each one occupies, rather than repeatedly circling back to a handful of favorites. Skip only content with no medical relevance (e.g. citations, formatting, or administrative text)."
                    : " — write a well-rounded general set") + ".")
            lines.append("")
        }
        lines.append("Write exactly \(count) multiple-choice questions. Follow these rules strictly:")
        lines.append("1. Each question has exactly 5 options. Do not prefix options with letters or numbers — just the option text.")
        lines.append("2. SINGLE BEST ANSWER format: more than one option may be defensible or partially true, but exactly one option must clearly be the BEST answer given the full picture. Every distractor must be the SAME kind of answer as the best one and genuinely in contention — if the best answer is a diagnosis, all 5 must be diagnoses from the same differential; if it's a drug, all 5 must be drugs a clinician would realistically consider here; if it's a lab value or number, all 5 must be plausible values in the same range. Never include an option that's a different category of answer, off-topic, or eliminable on sight — that's the single biggest tell students report, worse even than length. Draw distractors from closely related diagnoses or conditions in the same category, the correct action taken at the wrong stage of workup or management, a classic mix-up (a drug from the same class with a different indication/side-effect/mechanism, a similar-sounding eponym or criterion, a lab value just outside the diagnostic threshold), or the specific wrong answer students most commonly pick in practice. A student should need real, specific knowledge to eliminate each distractor — if you can imagine a student ruling one out without knowing the topic, rewrite it to be more specific and more plausible.")
        lines.append("3. Never use \"all of the above\" or \"none of the above\".")
        lines.append("4. CRITICAL — length is the other giveaway students report (\"the longest option is always right\"), and it's not fixed by randomizing option order, since the length travels with the answer text itself: write the best answer in its natural, complete form, then write each of the 4 distractors to that SAME level of clinical specificity and length — within about 2-3 words of it and of each other. If a distractor is coming out shorter, add real clinical detail (a mechanism, a qualifier, a specific value) to lengthen it, never vague filler; if the best answer is coming out longer, tighten the wording rather than dropping the detail that makes it correct. Before you finalize each question, look at your own 5 options as a student would: is one option noticeably longer, more hedged, or more specific than the rest? If so, rewrite until none of them stand out — a student must not be able to shortcut the question by picking the longest, most detailed-sounding option.")
        lines.append("5. Vary the question style across the set, and deliberately mix two kinds of difficulty: (a) reasoning/application questions — brief clinical vignettes (age/sex/presentation/findings) and \"best next step / most likely diagnosis / most specific finding\" questions that require synthesizing several findings, and (b) pure memorization questions that test one specific fact, number, definition, classification, criterion, mechanism, or eponym directly, answerable only by having actually memorized it — no vignette or context clues to reason from. At least one in five questions in the set should be this recall-only style.")
        lines.append("6. In the explanation for each question: state why the best answer is best, and explicitly address at least one other option that is tempting or partially correct, explaining why it falls short of best. Never refer to options by a letter or position (\"option A\", \"the first choice\") — the order they're shown in is randomized after you write them, so a letter reference would be wrong. Refer to each option by its actual content instead (e.g. \"metformin\" or \"the biopsy finding of...\").")
        lines.append("7. Every question must be answerable from the source material above — never invent facts outside it.")
        if highYield { lines.append("8. Favor the highest-yield, most exam-relevant facts in the source material.") }

        // What the earlier batches already used up. Without this every batch
        // independently picks the most obvious facts in the source, and a long
        // set becomes the same eight questions written ten ways.
        let avoidance = MCQCoverage.avoidanceNote(alreadyAsked)
        if !avoidance.isEmpty { lines.append(avoidance) }

        // @Generable makes Apple's on-device path guarantee its own output
        // shape, but a plain-text model (the Gemma fallback) has to be asked
        // for it directly - the same JSON instruction the web app's
        // Claude-backed prompt used before this app existed.
        if requestJSONShape {
            lines.append("")
            lines.append("Reply with ONLY a single JSON object — no markdown code fences, no commentary before or after it — of exactly this shape:")
            lines.append(#"{"questions":[{"stem":"...","options":["...","...","...","...","..."],"correctIndex":0,"explanation":"..."}]}"#)
            lines.append("\"options\" must have exactly 5 strings. \"correctIndex\" is the zero-based index into options of the best answer.")
        }
        return lines.joined(separator: "\n")
    }
}
