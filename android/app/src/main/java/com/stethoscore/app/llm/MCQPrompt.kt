package com.stethoscore.app.llm

import com.stethoscore.app.exam.BlueprintArea
import com.stethoscore.app.exam.ExamBlueprint
import com.stethoscore.app.exam.ExamDomain
import com.stethoscore.app.exam.TargetExam
import com.stethoscore.app.quiz.ExamTrack
import kotlin.math.roundToInt

// The instructions every question writer is given, and the checks a written
// question passes before it is kept. Ports of iOS Shared/MCQPrompt.swift
// (buildPrompt, recallRule, differentialRules), Shared/Exam/ExamPrompt.swift,
// Shared/MCQCoverage.swift, MCQGenerator's isValidQuestion/lengthBalanced and
// ExamTrack.mcqStyle, word for word. Pure Kotlin, so all of it is tested.
//
// Not ported: ExamExemplars' bundled exemplar bank (block, copies). A cloud job
// leaves the exemplars to the server ({{EXEMPLARS:...}}, server/exams.js), which
// is the only way Android writes; a direct call is sent without exemplars.

/** The writer's opening line for a track (iOS ExamTrack.mcqStyle). */
val ExamTrack.mcqStyle: String get() = when (this) {
    ExamTrack.general -> "You are writing single-best-answer multiple-choice questions for a medical student's exam revision, in the NBME/USMLE \"one-best-answer\" style."
    ExamTrack.usmle -> "You are writing USMLE Step 1 / Step 2 CK single-best-answer questions in the NBME style: most are clinical vignettes (age, sex, setting, history, vitals, examination, labs) that end in one clear question. Use US conventional units (mg/dL, °F alongside °C), US generic drug names (acetaminophen, epinephrine) and current US guidelines (e.g. ACC/AHA, ADA, USPSTF, IDSA). Step 1 questions lean on mechanism, pathology and pharmacology; Step 2 CK questions on diagnosis, next best step and management."
    ExamTrack.plab -> "You are writing PLAB 1 single-best-answer questions (the GMC's exam) at the level of a UK foundation-year doctor: short clinical scenarios set in UK practice (GP surgery, A&E, wards) with one best answer from five. Use SI units (mmol/L, µmol/L), UK drug names (paracetamol, adrenaline), and current NICE guidance, NICE CKS and the BNF; where UK and US practice differ, the UK answer is correct. Favour common and dangerous presentations, safe prescribing, ethics and GMC Good Medical Practice."
    ExamTrack.mrcp -> "You are writing MRCP(UK) Part 1 / Part 2 written best-of-five questions at the level of a UK core medical trainee: detailed clinical scenarios with investigation results to interpret (blood tests, ECG and imaging descriptions, blood gases). Use SI units, UK drug names and current UK practice (NICE, BTS, BSG, ESC as used in the UK). Part 1 leans on the science and mechanism behind the medicine; Part 2 on diagnosis, investigation and management decisions."
    ExamTrack.mrcs -> "You are writing MRCS Part A single-best-answer questions (Royal Colleges of Surgeons): applied basic sciences - applied surgical anatomy, physiology and pathology - and the principles of surgery in general (perioperative care, trauma, surgical oncology, infection). Use SI units, UK drug names and UK surgical practice (NICE, ATLS). Anatomy questions should test relations, nerve and blood supply, and the clinical consequence of an injury."
}

/** What a question writer is told about the chosen exam (iOS ExamPrompt). */
object ExamPrompt {

    fun opening(exam: TargetExam): String {
        if (exam.family == ExamTrack.general) {
            return "You are writing ${exam.name} single-best-answer questions for a medical student preparing for that exam, in its own style: ${exam.leadIns}. Use ${exam.conventions}."
        }
        return exam.family.mcqStyle + " The student is preparing for ${exam.name} specifically: write to its format below."
    }

    fun formatRules(exam: TargetExam): List<String> {
        val recall = (exam.recallShare * 100).roundToInt()
        val lines = mutableListOf(
            "EXAM FORMAT - ${exam.name}:",
            "- Exactly ${exam.options} options per question.",
            "- Stems of about ${exam.stemWords.first}-${exam.stemWords.last} words" +
                if (exam.stemWords.last <= 60) ": one or two lines, as this exam asks them." else ".",
            "- Ask the way this exam asks: ${exam.leadIns}.",
            "- About $recall% pure recall questions; the rest clinical.",
            "- Use ${exam.conventions}.",
        )
        if (exam.accuracyStrictness >= 0.4) {
            lines += "- Most questions are management decisions: the keyed answer must be the single next step current guidelines support for THIS patient at THIS point, with distractors that are right at another stage."
        }
        exam.negativeMarking?.let { lines += "- The exam marks $it, so distractors must be ones a half-prepared student would pick with confidence." }
        return lines
    }

    fun weighting(count: Int, plan: List<BlueprintArea>, examName: String, limit: Int = 8): String? {
        val quotas = ExamBlueprint.quotas(count, plan)
        if (quotas.size <= 1) return null
        val total = plan.sumOf { it.weight }
        if (total <= 0) return null
        val top = quotas.take(limit).map { row ->
            val pct = (row.area.weight / total * 100).roundToInt()
            "${row.area.title} $pct% (${row.questions})"
        }
        return "BLUEPRINT WEIGHTING: $examName spreads its questions roughly as " + top.joinToString(", ") +
            ". Where the source material covers several of these areas, give each about that many of the $count questions, heaviest first; never go outside the source material to fill an area."
    }

    fun topic(subject: String, source: String): ExamDomain? {
        val plain = subject.isEmpty() || subject == "General"
        if (!plain) ExamBlueprint.domain(subject)?.let { return it }
        val sample = source.take(4000)
        return if (sample.isEmpty()) null else ExamBlueprint.domain(sample)
    }

    /** The server's exemplar slot (iOS ExamExemplars.placeholder). */
    fun exemplarPlaceholder(exam: TargetExam, domain: ExamDomain?, count: Int = 2): String =
        "{{EXEMPLARS:${exam.id}:${domain?.rawValue ?: ""}:${count.coerceIn(1, 3)}}}"

    /** Everything the prompt gets for the exam. Exemplars only as the server's placeholder (see above). */
    fun section(exam: TargetExam, secondary: TargetExam?, subject: String, source: String,
                count: Int, exemplars: Int, placeholder: Boolean = false): List<String> {
        val lines = formatRules(exam).toMutableList()
        if (subject.isEmpty() || subject == "General") {
            weighting(count, ExamBlueprint.plan(exam, secondary), exam.name)?.let { lines += ""; lines += it }
        }
        if (exemplars > 0 && placeholder) {
            val domain = topic(subject, source) ?: exam.shares.firstOrNull()?.domain
            lines += ""
            lines += exemplarPlaceholder(exam, domain, exemplars)
        }
        lines += ""
        return lines
    }
}

/** Making a long set actually cover the material (iOS MCQCoverage). */
object MCQCoverage {

    data class Asked(val stem: String, val key: String)

    val scaffolding: Set<String> = setOf(
        "a", "an", "the", "of", "in", "to", "with", "for", "is", "are", "and",
        "or", "on", "at", "by", "from", "as", "that", "this", "it", "be", "was",
        "were", "has", "have", "had", "after", "before", "which", "what", "who",
        "most", "likely", "best", "next", "step", "following", "patient",
        "presents", "presenting", "year", "years", "old", "man", "woman",
        "male", "female", "his", "her", "their", "you", "would", "should",
        "management", "appropriate", "initial", "than", "about", "into",
    )

    fun contentWords(text: String): Set<String> =
        text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.length > 2 && it !in scaffolding }.toSet()

    fun overlap(a: String, b: String): Double {
        val left = contentWords(a)
        val right = contentWords(b)
        if (left.isEmpty() || right.isEmpty()) return 0.0
        return (left intersect right).size.toDouble() / minOf(left.size, right.size)
    }

    fun likeness(a: String, b: String): Double {
        val left = contentWords(a)
        val right = contentWords(b)
        val union = (left union right).size
        if (union == 0 || left.isEmpty() || right.isEmpty()) return 0.0
        return (left intersect right).size.toDouble() / union
    }

    fun sameAnswer(a: String, b: String): Boolean {
        fun bare(text: String) = text.lowercase().filter { it.isLetterOrDigit() }
        val left = bare(a)
        val right = bare(b)
        if (left.isEmpty() || right.isEmpty()) return false
        if (left == right) return true
        val lw = contentWords(a)
        val rw = contentWords(b)
        if (lw.isEmpty() || rw.isEmpty()) return false
        return rw.containsAll(lw) || lw.containsAll(rw)
    }

    fun isRepeat(stem: String, key: String, of: List<Asked>, stemThreshold: Double = 0.6,
                 sameKeyThreshold: Double = 0.3, differentKeyThreshold: Double = 0.8): Boolean {
        val trimmedKey = key.trim()
        for (previous in of) {
            val previousKey = previous.key.trim()
            val similarity = overlap(stem, previous.stem)
            if (trimmedKey.isEmpty() || previousKey.isEmpty()) {
                if (similarity >= stemThreshold) return true
            } else if (sameAnswer(trimmedKey, previousKey)) {
                if (similarity >= sameKeyThreshold) return true
            } else if (likeness(stem, previous.stem) >= differentKeyThreshold) {
                return true
            }
        }
        return false
    }

    fun avoidanceNote(asked: List<Asked>, limit: Int = 40, stemLength: Int = 90): String {
        if (asked.isEmpty()) return ""
        val lines = mutableListOf(
            "",
            "ALREADY ASKED in this set - ${asked.size} question(s) so far. Do NOT test any of these facts again, and do not rewrite them as a different vignette with the same answer. Move on to parts of the source material the list below does not touch:",
        )
        for (item in asked.takeLast(limit)) {
            val stem = item.stem.trim()
            val shortened = if (stem.length > stemLength) stem.take(stemLength) + "…" else stem
            val key = item.key.trim()
            lines += "- $shortened" + if (key.isEmpty()) "" else "  [answer: $key]"
        }
        return lines.joinToString("\n")
    }
}

/** The question writer's prompt and the bar a question clears (iOS MCQGenerator + MCQPrompt). */
object MCQPrompt {

    const val maxQuestionsPerCall = 6

    fun lengthBalanced(options: List<String>, correctIndex: Int): Boolean {
        val lens = options.map { it.trim().length }
        if (correctIndex !in lens.indices) return false
        val correctLen = lens[correctIndex]
        val others = lens.filterIndexed { i, _ -> i != correctIndex }
        if (others.isEmpty()) return false
        val maxOther = others.max()
        val avgOther = others.sum().toDouble() / others.size
        return !(correctLen > maxOther && correctLen > avgOther * 1.3)
    }

    fun isValidQuestion(stem: String, options: List<String>, correctIndex: Int): Boolean =
        options.size in 4..5 && correctIndex in options.indices && stem.trim().isNotEmpty() &&
            lengthBalanced(options, correctIndex)

    fun buildPrompt(
        sourceText: String, count: Int, subject: String, highYield: Boolean,
        requestJSONShape: Boolean = false,
        alreadyAsked: List<MCQCoverage.Asked> = emptyList(),
        exam: ExamTrack = ExamTrack.general,
        target: TargetExam? = null,
        secondary: TargetExam? = null,
        exemplars: Int = 1,
        exemplarPlaceholder: Boolean = false, topicText: String? = null,
    ): String {
        val chosen = target?.takeIf { it.family == exam }
        val options = chosen?.options ?: 5
        val lines = mutableListOf(chosen?.let { ExamPrompt.opening(it) } ?: exam.mcqStyle, "")
        if (sourceText.isNotEmpty()) {
            lines += "SOURCE MATERIAL (the student's own notes — use ONLY facts found in it):"
            lines += "\"\"\""
            lines += sourceText
            lines += "\"\"\""
            lines += ""
        }
        if (subject.isNotEmpty() && subject != "General") {
            lines += "Topic to focus on: \"$subject\". Every question in this set must specifically test this topic" +
                (if (sourceText.isEmpty()) "" else " — draw only on the parts of the source material relevant to it, and ignore parts of the source that aren't") +
                ". Interpret the topic as written (it may name a disease, a drug or drug class, a mechanism, a lab test, an exam theme, or anything else) and build the whole set around it rather than around the source material's overall subject."
            lines += "A topic being given does not mean a narrow set: aim for COMPREHENSIVE coverage of that topic. Identify every distinct fact, mechanism, subtype, complication, diagnostic criterion, or exam angle the source material offers on it — not just the first or most obvious one — and spread the $count questions across all of them in rough proportion to how much the source covers each, rather than writing several questions that circle back to the same one or two facts."
            lines += ""
        } else {
            lines += "No specific topic was given, so aim for comprehensive coverage" +
                (if (sourceText.isNotEmpty())
                    " of the source material: identify every distinct medically-relevant fact, concept, finding, or topic it contains — not just the first or most prominent one — and make sure the set as a whole tests across all of them, in rough proportion to how much of the source each one occupies, rather than repeatedly circling back to a handful of favorites. Skip only content with no medical relevance (e.g. citations, formatting, or administrative text)."
                else " — write a well-rounded general set") + "."
            lines += ""
        }
        if (chosen != null) {
            lines += ExamPrompt.section(chosen, secondary, subject, topicText ?: sourceText, count, exemplars, exemplarPlaceholder)
        }
        lines += "Write exactly $count multiple-choice questions. Follow these rules strictly:"
        lines += "1. Each question has exactly $options options. Do not prefix options with letters or numbers — just the option text."
        lines += "2. SINGLE BEST ANSWER format: more than one option may be defensible or partially true, but exactly one option must clearly be the BEST answer given the full picture. Every distractor must be the SAME kind of answer as the best one and genuinely in contention — if the best answer is a diagnosis, all $options must be diagnoses from the same differential; if it's a drug, all $options must be drugs a clinician would realistically consider here; if it's a lab value or number, all $options must be plausible values in the same range. Never include an option that's a different category of answer, off-topic, or eliminable on sight — that's the single biggest tell students report, worse even than length. Draw distractors from closely related diagnoses or conditions in the same category, the correct action taken at the wrong stage of workup or management, a classic mix-up (a drug from the same class with a different indication/side-effect/mechanism, a similar-sounding eponym or criterion, a lab value just outside the diagnostic threshold), or the specific wrong answer students most commonly pick in practice. A student should need real, specific knowledge to eliminate each distractor — if you can imagine a student ruling one out without knowing the topic, rewrite it to be more specific and more plausible."
        lines += "3. Never use \"all of the above\" or \"none of the above\"."
        lines += "4. CRITICAL — length is the other giveaway students report (\"the longest option is always right\"), and it's not fixed by randomizing option order, since the length travels with the answer text itself: write the best answer in its natural, complete form, then write each of the ${options - 1} distractors to that SAME level of clinical specificity and length — within about 2-3 words of it and of each other. If a distractor is coming out shorter, add real clinical detail (a mechanism, a qualifier, a specific value) to lengthen it, never vague filler; if the best answer is coming out longer, tighten the wording rather than dropping the detail that makes it correct. Before you finalize each question, look at your own $options options as a student would: is one option noticeably longer, more hedged, or more specific than the rest? If so, rewrite until none of them stand out — a student must not be able to shortcut the question by picking the longest, most detailed-sounding option."
        lines += "5. Vary the question style across the set, and deliberately mix two kinds of difficulty: (a) reasoning/application questions — brief clinical vignettes (age/sex/presentation/findings) and \"best next step / most likely diagnosis / most specific finding\" questions that require synthesizing several findings, and (b) pure memorization questions that test one specific fact, number, definition, classification, criterion, mechanism, or eponym directly, answerable only by having actually memorized it — no vignette or context clues to reason from. " + recallRule(chosen)
        lines += "6. In the explanation for each question: state why the best answer is best; then give every other option its own short reason it is not the best (a clause each); and end with one line that starts \"Key point:\" and states the single fact or principle the question tests. Never refer to options by a letter or position (\"option A\", \"the first choice\") — the order they're shown in is randomized after you write them, so a letter reference would be wrong. Refer to each option by its actual content instead (e.g. \"metformin\" or \"the biopsy finding of...\")."
        lines += "7. Every question must be answerable from the source material above — never invent facts outside it."
        if (highYield) lines += "8. Favor the highest-yield, most exam-relevant facts in the source material."
        val avoidance = MCQCoverage.avoidanceNote(alreadyAsked)
        if (avoidance.isNotEmpty()) lines += avoidance
        if (requestJSONShape) {
            lines += ""
            lines += "Reply with ONLY a single JSON object — no markdown code fences, no commentary before or after it — of exactly this shape:"
            val slots = List(options) { "\"...\"" }.joinToString(",")
            lines += "{\"questions\":[{\"stem\":\"...\",\"options\":[" + slots + "],\"differential\":{\"mostLikely\":[{\"name\":\"...\",\"for\":[\"...\"],\"against\":[\"...\"],\"test\":\"...\"}],\"expanded\":[{\"name\":\"...\",\"for\":[\"...\"],\"against\":[\"...\"],\"test\":\"...\"}],\"cantMiss\":[{\"name\":\"...\",\"for\":[\"...\"],\"against\":[\"...\"],\"test\":\"...\"}]},\"correctIndex\":0,\"explanation\":\"...\"}]}"
            lines += "\"options\" must have exactly $options strings. \"correctIndex\" is the zero-based index into options of the best answer."
            lines += differentialRules
        }
        return lines.joinToString("\n")
    }

    fun recallRule(exam: TargetExam?): String {
        if (exam == null) return "At least one in five questions in the set should be this recall-only style."
        val pct = maxOf(10, (exam.recallShare * 100).roundToInt())
        return "About $pct% of the questions in the set should be this recall-only style, as ${exam.name} asks them."
    }

    val differentialRules: List<String> = listOf(
        "\"differential\": for any question built on a clinical vignette (the diagnosis, or the next investigation or treatment for it), first reason through the differential and write it here, BEFORE you choose correctIndex:",
        "- \"mostLikely\": the leading diagnosis; \"expanded\": 1 or 2 reasonable alternatives; \"cantMiss\": 1 or 2 dangerous diagnoses that must be excluded, where any fit the case (otherwise an empty list).",
        "- For each: \"for\" and \"against\" are up to 2 findings each, taken from the stem, a few words each; \"test\" is the one test that would confirm or rule it out.",
        "- Then key the answer so it fits EVERY key finding in the stem, and make the explanation agree with the differential.",
        "- Leave \"differential\" out of a pure recall question.",
        "- Follow current guidance, but never cite a source, guideline, journal or reference by name anywhere: the app cites the lecture page and any evidence it checked.",
    )
}
