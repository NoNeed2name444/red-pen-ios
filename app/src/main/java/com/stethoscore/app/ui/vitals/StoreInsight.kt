package com.stethoscore.app.ui.vitals

import com.stethoscore.app.data.CalibrationRow
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.Readiness
import com.stethoscore.app.data.ReadinessEstimate
import com.stethoscore.app.data.ReasonShare
import com.stethoscore.app.data.RuleGroup
import com.stethoscore.app.data.RuleWriter
import com.stethoscore.app.data.StudyRule
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.AnswerConfidence
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MistakeReason
import com.stethoscore.app.quiz.PassMark
import com.stethoscore.app.ui.home.HomeRound
import com.stethoscore.app.ui.mock.MockLibrary
import com.stethoscore.app.ui.mock.QuestionPick
import java.util.Locale

// A port of upstream/ios/RedPen/Shared/Insight/StoreInsight.swift: the parts
// of the library about why marks are lost and what to do about it - the
// reasons given for wrong answers, confidence, the rule sheet, and the
// readiness estimate. Every quiz built here is temporary
// (MockLibrary.temporaryQuiz), like the drills on home.
object StoreInsight {
    /** How far back "Why you lose marks" looks. */
    const val reasonWindowDays = 30

    private const val day = 86_400_000L

    // MARK: why a mark was lost

    /** The reasons given within the window, as shares of all given, most common first. Reasons never given are left out. */
    fun reasonShares(store: StudyStore, days: Int = reasonWindowDays, now: Long = System.currentTimeMillis()): List<ReasonShare> {
        val since = now - days * day
        val counts = LinkedHashMap<MistakeReason, Int>()
        for (note in store.mistakeReasons.values) {
            if (note.at < since) continue
            val reason = MistakeReason.from(note.reason) ?: continue
            counts[reason] = (counts[reason] ?: 0) + 1
        }
        val total = counts.values.sum()
        if (total <= 0) return emptyList()
        return counts.map { (reason, count) -> ReasonShare(reason, count, count.toDouble() / total) }
            .sortedWith(compareByDescending<ReasonShare> { it.count }.thenBy { it.reason.rawValue })
    }

    /** The questions still in the library last got wrong for [reason] within the window, newest first. */
    fun picks(store: StudyStore, reason: MistakeReason, days: Int = reasonWindowDays, now: Long = System.currentTimeMillis()): List<QuestionPick> {
        val since = now - days * day
        val notes = store.mistakeReasons.filter { it.value.reason == reason.rawValue && it.value.at >= since }
        if (notes.isEmpty()) return emptyList()
        return MockLibrary.mcqPicks(store.library) { it.question.id in notes }
            .sortedByDescending { notes[it.question.id]?.at ?: Long.MIN_VALUE }
    }

    /** A quiz of the questions missed for [reason], up to [limit]. */
    fun reasonQuiz(store: StudyStore, reason: MistakeReason, name: String, limit: Int = 20): StudySet =
        MockLibrary.temporaryQuiz(name, name, picks(store, reason).take(limit).shuffled())

    /**
     * Ten questions for a timed drill: those lost to the clock first, then
     * the ones last got wrong, then anything, so there are always ten when
     * the library has them.
     */
    fun timedDrill(store: StudyStore, limit: Int = 10): StudySet {
        val chosen = picks(store, MistakeReason.outOfTime).toMutableList()
        val seen = chosen.map { it.question.id }.toMutableSet()
        if (chosen.size < limit) {
            val wrong = MockLibrary.mcqPicks(store.library) { it.question.id !in seen && store.answerHistory[it.question.id]?.lastOrNull() == false }.shuffled()
            chosen += wrong
            seen += wrong.map { it.question.id }
        }
        if (chosen.size < limit) chosen += MockLibrary.mcqPicks(store.library) { it.question.id !in seen }.shuffled()
        return MockLibrary.temporaryQuiz("Timed drill", "Timed drill", chosen.take(limit).shuffled())
    }

    // MARK: confidence

    /** Accuracy at each confidence level, over the whole dated log. */
    fun calibration(store: StudyStore): List<CalibrationRow> {
        val rows = HashMap<AnswerConfidence, CalibrationRow>()
        for (event in store.answerLog) {
            val level = AnswerConfidence.from(event.confidence) ?: continue
            val row = rows[level] ?: CalibrationRow(level, 0, 0)
            rows[level] = row.copy(answered = row.answered + 1, correct = row.correct + if (event.correct) 1 else 0)
        }
        return AnswerConfidence.entries.mapNotNull { rows[it] }
    }

    /** The questions got wrong while sure, still in the library. */
    fun confidentMistakePicks(store: StudyStore): List<QuestionPick> {
        val ids = store.confidentMistakeIds
        if (ids.isEmpty()) return emptyList()
        return MockLibrary.mcqPicks(store.library) { it.question.id in ids }
    }

    /** A quiz of the confident mistakes, up to [limit]. */
    fun confidentMistakesQuiz(store: StudyStore, limit: Int = 20): StudySet =
        MockLibrary.temporaryQuiz("Confident mistakes", "Confident mistakes", confidentMistakePicks(store).shuffled().take(limit))

    // MARK: rule sheet

    /** Rules on the sheet, grouped by subject, subjects in order (case aside), each subject's rules newest first. */
    fun rulesBySubject(sheet: Map<String, StudyRule>): List<RuleGroup> {
        val groups = sheet.values.groupBy { it.subject }
        val names = groups.keys.sortedWith { a, b -> a.lowercase(Locale.getDefault()).compareTo(b.lowercase(Locale.getDefault())) }
        return names.map { name -> RuleGroup(name, groups[name].orEmpty().sortedByDescending { it.date }) }
    }

    /** Of [questions], the ones with no rule yet. */
    fun questionsWithoutRules(store: StudyStore, questions: List<MCQQuestion>): List<MCQQuestion> {
        val seen = HashSet<String>()
        return questions.filter { it.id !in store.ruleSheet && seen.add(it.id) }
    }

    /** Adds a plain rule for each question that has none; returns how many. */
    fun addRules(store: StudyStore, questions: List<MCQQuestion>, subject: String): Int {
        val fresh = questionsWithoutRules(store, questions)
        if (fresh.isEmpty()) return 0
        val name = subject.trim().ifEmpty { "General" }
        return store.addRules(fresh.map { RuleWriter.plainRule(it, name) })
    }

    /** Questions in the library whose last answer was wrong and that have no rule yet, each with its subject. */
    fun missedWithoutRules(store: StudyStore): List<QuestionPick> =
        MockLibrary.mcqPicks(store.library) { store.answerHistory[it.question.id]?.lastOrNull() == false && it.question.id !in store.ruleSheet }

    /** Adds plain rules for every question last got wrong; returns how many. */
    fun addRulesForMissed(store: StudyStore): Int {
        val picks = missedWithoutRules(store)
        if (picks.isEmpty()) return 0
        return store.addRules(picks.map { RuleWriter.plainRule(it.question, MockLibrary.subjectName(it.set)) })
    }

    /** The whole sheet as plain text, for sharing. */
    fun ruleSheetText(sheet: Map<String, StudyRule>): String {
        val out = mutableListOf("Rule sheet", "")
        for (group in rulesBySubject(sheet)) {
            out.add(group.subject.uppercase(Locale.getDefault()))
            for (rule in group.rules) {
                out.add("• ${rule.text}")
                if (rule.detail.isNotEmpty() && !rule.byAI) out.add("  ${rule.detail}")
            }
            out.add("")
        }
        return out.joinToString("\n")
    }

    // MARK: readiness

    /**
     * Right or wrong for the latest answers, newest first. The dated log once
     * there is enough of it; before then, the older per-question history,
     * which has no dates and so no order.
     */
    fun recentAnswers(store: StudyStore): List<Boolean> {
        if (store.answerLog.size >= Readiness.minimumAnswers) return store.answerLog.takeLast(Readiness.window).reversed().map { it.correct }
        return store.answerHistory.values.flatten().take(Readiness.window)
    }

    fun readiness(store: StudyStore, dueCards: Int, track: ExamTrack): ReadinessEstimate? =
        Readiness.estimate(recentAnswers(store), HomeRound.subjectStats(store), dueCards, PassMark.typical(track))

    /** Whether the dated history includes the personal build's made-up examples, so the screens built on it can say so. */
    fun includesExampleData(store: StudyStore): Boolean = store.answerLog.any { it.isExample == true }
}
