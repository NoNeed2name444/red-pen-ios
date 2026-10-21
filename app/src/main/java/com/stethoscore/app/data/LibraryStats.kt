package com.stethoscore.app.data

import com.stethoscore.app.quiz.AnswerConfidence
import com.stethoscore.app.quiz.MistakeReason
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** One question with the set it lives in (iOS QuestionPick). */
data class QuestionPick(val set: StudySet, val question: MCQQuestion)

/** How one subject is going (iOS SubjectStats). */
data class SubjectStats(val subject: String, val questions: Int, val answered: Int, val correct: Int) {
    val accuracy: Double get() = if (answered == 0) 0.0 else correct.toDouble() / answered
}

/** How often each confidence was right (iOS CalibrationRow). */
data class CalibrationRow(val confidence: AnswerConfidence, val answered: Int, val correct: Int) {
    val accuracy: Double get() = if (answered == 0) 0.0 else correct.toDouble() / answered
}

/** One reason for losing marks and its share (iOS ReasonShare). */
data class ReasonShare(val reason: MistakeReason, val count: Int, val share: Double)

/**
 * What the library's By subject page and its quizzes read from the store
 * (iOS Persistence/StoreStudy.swift and Shared/Insight/StoreInsight.swift):
 * subjects weakest first, the drill, confidence, why marks are lost, and
 * quizzes put together on the spot without being saved to the library.
 */
object LibraryStats {
    const val reasonWindowDays = 30
    private const val DAY_MS = 86_400_000L

    /** A set's subject as the Progress screen groups it: blank is "General". */
    fun subjectName(set: StudySet): String = set.subject.trim().ifEmpty { "General" }

    /** Every question in the library once, with its set, that [keep] accepts. */
    fun mcqPicks(store: StudyStore, keep: (QuestionPick) -> Boolean = { true }): List<QuestionPick> {
        val seen = mutableSetOf<String>()
        val out = mutableListOf<QuestionPick>()
        for (set in store.library) {
            if (set.kind != StudySetKind.MCQ) continue
            for (question in set.questions) {
                if (question.id in seen) continue
                val pick = QuestionPick(set, question)
                if (!keep(pick)) continue
                seen += question.id
                out += pick
            }
        }
        return out
    }

    /** Subjects tried first, weakest first; untried ones after, by name. */
    fun subjectStats(store: StudyStore): List<SubjectStats> {
        val bySubject = LinkedHashMap<String, SubjectStats>()
        for (pick in mcqPicks(store)) {
            val subject = subjectName(pick.set)
            val stats = bySubject[subject] ?: SubjectStats(subject, 0, 0, 0)
            val past = store.answerHistory[pick.question.id].orEmpty()
            bySubject[subject] = stats.copy(questions = stats.questions + 1, answered = stats.answered + past.size,
                correct = stats.correct + past.count { it })
        }
        return bySubject.values.sortedWith { a, b ->
            when {
                (a.answered == 0) != (b.answered == 0) -> if (b.answered == 0) -1 else 1
                a.accuracy != b.accuracy -> a.accuracy.compareTo(b.accuracy)
                else -> a.subject.compareTo(b.subject)
            }
        }
    }

    /** Up to [limit] questions from [subject]: wrong while sure first, then wrong last time, ever wrong, untried, the rest. */
    fun drill(store: StudyStore, subject: String, limit: Int = 20): StudySet {
        val picks = mcqPicks(store) { subjectName(it.set) == subject }
        val confident = store.confidentMistakeIds
        val confidentWrong = mutableListOf<QuestionPick>(); val lastWrong = mutableListOf<QuestionPick>()
        val everWrong = mutableListOf<QuestionPick>(); val untried = mutableListOf<QuestionPick>(); val rest = mutableListOf<QuestionPick>()
        for (pick in picks) {
            val past = store.answerHistory[pick.question.id].orEmpty()
            when {
                pick.question.id in confident -> confidentWrong += pick
                past.lastOrNull() == false -> lastWrong += pick
                false in past -> everWrong += pick
                past.isEmpty() -> untried += pick
                else -> rest += pick
            }
        }
        val chosen = (confidentWrong.shuffled() + lastWrong.shuffled() + everWrong.shuffled() + untried.shuffled() + rest.shuffled()).take(limit)
        return temporaryQuiz("Drill – $subject", subject, chosen.shuffled())
    }

    /** A quiz of [picks], each question's picture carried over with its set's pictures. */
    fun temporaryQuiz(name: String, subject: String, picks: List<QuestionPick>): StudySet {
        val images = mutableListOf<String>()
        val bases = mutableMapOf<String, Int>()
        val questions = picks.map { pick ->
            val q = pick.question
            val i = q.imageIndex ?: return@map q
            if (i !in pick.set.images.indices) return@map q.copy(imageIndex = null)
            val base = bases.getOrPut(pick.set.id) { images.size.also { images += pick.set.images } }
            q.copy(imageIndex = i + base)
        }
        return StudySet(name = name, subject = subject, kind = StudySetKind.MCQ, questions = questions, images = images)
    }

    /** The selected sets' questions in one quiz, at most 50 (iOS LibraryView.startMixedQuiz). */
    fun mixedQuiz(sets: List<StudySet>): StudySet? {
        val chosen = sets.filter { it.kind == StudySetKind.MCQ }
        val seen = mutableSetOf<String>()
        val picks = chosen.flatMap { set -> set.questions.filter { seen.add(it.id) }.map { QuestionPick(set, it) } }
        if (picks.isEmpty()) return null
        val subjects = chosen.map { subjectName(it) }.toSet()
        val subject = if (subjects.size == 1) subjects.first() else "Mixed"
        return temporaryQuiz("Mixed quiz", subject, picks.shuffled().take(50))
    }

    /** The flagged questions as a quiz, or null when none are flagged. */
    fun flaggedQuiz(store: StudyStore): StudySet? {
        val picks = mcqPicks(store) { it.question.id in store.flagged }
        if (picks.isEmpty()) return null
        return temporaryQuiz("Flagged questions", "Flagged", picks.shuffled())
    }

    fun calibration(store: StudyStore): List<CalibrationRow> {
        val rows = LinkedHashMap<AnswerConfidence, CalibrationRow>()
        for (event in store.answerLog) {
            val level = AnswerConfidence.from(event.confidence) ?: continue
            val row = rows[level] ?: CalibrationRow(level, 0, 0)
            rows[level] = row.copy(answered = row.answered + 1, correct = row.correct + if (event.correct) 1 else 0)
        }
        return AnswerConfidence.entries.mapNotNull { rows[it] }
    }

    fun confidentMistakePicks(store: StudyStore): List<QuestionPick> {
        val ids = store.confidentMistakeIds
        if (ids.isEmpty()) return emptyList()
        return mcqPicks(store) { it.question.id in ids }
    }

    fun confidentMistakesQuiz(store: StudyStore, limit: Int = 20): StudySet =
        temporaryQuiz("Confident mistakes", "Confident mistakes", confidentMistakePicks(store).shuffled().take(limit))

    fun reasonShares(store: StudyStore, days: Int = reasonWindowDays, now: Long = System.currentTimeMillis()): List<ReasonShare> {
        val since = now - days * DAY_MS
        val counts = LinkedHashMap<MistakeReason, Int>()
        for (note in store.mistakeReasons.values) {
            if (note.at < since) continue
            val reason = MistakeReason.from(note.reason) ?: continue
            counts[reason] = (counts[reason] ?: 0) + 1
        }
        val total = counts.values.sum()
        if (total == 0) return emptyList()
        return counts.map { ReasonShare(it.key, it.value, it.value.toDouble() / total) }
            .sortedWith { a, b -> if (a.count != b.count) b.count - a.count else a.reason.rawValue.compareTo(b.reason.rawValue) }
    }

    fun picks(store: StudyStore, reason: MistakeReason, days: Int = reasonWindowDays, now: Long = System.currentTimeMillis()): List<QuestionPick> {
        val since = now - days * DAY_MS
        val notes = store.mistakeReasons.filter { it.value.reason == reason.rawValue && it.value.at >= since }
        if (notes.isEmpty()) return emptyList()
        return mcqPicks(store) { it.question.id in notes }.sortedByDescending { notes[it.question.id]?.at ?: Long.MIN_VALUE }
    }

    fun reasonQuiz(store: StudyStore, reason: MistakeReason, name: String, limit: Int = 20): StudySet =
        temporaryQuiz(name, name, picks(store, reason).take(limit).shuffled())

    fun timedDrill(store: StudyStore, limit: Int = 10): StudySet {
        val chosen = picks(store, MistakeReason.outOfTime).toMutableList()
        val seen = chosen.map { it.question.id }.toMutableSet()
        if (chosen.size < limit) {
            val wrong = mcqPicks(store) { it.question.id !in seen && store.answerHistory[it.question.id]?.lastOrNull() == false }.shuffled()
            chosen += wrong; seen += wrong.map { it.question.id }
        }
        if (chosen.size < limit) chosen += mcqPicks(store) { it.question.id !in seen }.shuffled()
        return temporaryQuiz("Timed drill", "Timed drill", chosen.take(limit).shuffled())
    }

    /** The study day an answer falls on: days turn at 4 a.m., as everywhere else. */
    fun studyDay(at: Long, zone: ZoneId = ZoneId.systemDefault()): LocalDate =
        Instant.ofEpochMilli(at).atZone(zone).minusHours(4).toLocalDate()

    /** Questions answered today, and the run of days with any answered, today or yesterday its end. */
    fun streakAndToday(store: StudyStore, now: Long = System.currentTimeMillis()): Pair<Int, Int> {
        val days = store.answerLog.groupingBy { studyDay(it.at) }.eachCount()
        val today = studyDay(now)
        var day = if ((days[today] ?: 0) > 0) today else today.minusDays(1)
        var streak = 0
        while ((days[day] ?: 0) > 0) { streak++; day = day.minusDays(1) }
        return streak to (days[today] ?: 0)
    }

    /** How far through a set the student is, or null for nothing to count (iOS WardHome.progress). */
    fun progress(store: StudyStore, set: StudySet): Double? {
        val total = set.itemCount
        if (total <= 0) return null
        val done = when (set.kind) {
            StudySetKind.MCQ -> set.questions.count { store.answerHistory[it.id].orEmpty().isNotEmpty() }
            StudySetKind.ANKI -> set.cards.count { (store.reviews[it.id]?.reviews ?: 0) > 0 }
            StudySetKind.OSCE -> store.osceProgress[set.id]?.let { p ->
                set.osceChecklists.take(p.checklistIndex).sumOf { it.steps.size } + p.stepIndex } ?: 0
            StudySetKind.NARRATE -> return null
            else -> store.readingProgress[set.id]?.position ?: 0
        }
        return minOf(1.0, done.toDouble() / total)
    }
}
