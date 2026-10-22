package com.stethoscore.app.ui.learn

import com.stethoscore.app.data.AnswerEvent
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.data.LearnDefaults
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.Pretest
import com.stethoscore.app.data.RetentionForecast
import com.stethoscore.app.data.SecuredRule
import com.stethoscore.app.data.StudyRhythm
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.SymptomBlocks
import com.stethoscore.app.quiz.MockRecords
import com.stethoscore.app.ui.home.HomeRound
import com.stethoscore.app.ui.mock.MockLibrary
import com.stethoscore.app.ui.mock.QuestionPick
import java.io.File
import java.time.Instant
import java.time.ZoneId

// The library read through the learning-science pieces (iOS
// Shared/Learn/LearnStore.swift, with StoreInsight's confident mistakes and
// LibraryRows' flagged quiz): what is secured, what the run-up to the exam
// asks for, the symptom blocks, and the day's misses. Every quiz built here
// is temporary (MockLibrary.temporaryQuiz) and keeps the questions' own ids,
// so answers land on them.

internal object LearnLibrary {
    private fun zone(): ZoneId = ZoneId.systemDefault()

    // MARK: lock it in

    /** Where every answered question stands. */
    fun securedStandings(store: StudyStore): Map<String, SecuredRule.Standing> = SecuredRule.standings(store.answerLog, zone())

    /** Each library question's subject, once per id. */
    fun questionSubjects(store: StudyStore): Map<String, String> =
        MockLibrary.mcqPicks(store.library).associate { it.question.id to MockLibrary.subjectName(it.set) }

    /** Questions one or two days from secured that a right answer today would move on. */
    fun lockInPicks(store: StudyStore, standings: Map<String, SecuredRule.Standing>? = null,
                    now: Long = System.currentTimeMillis()): List<QuestionPick> {
        val known = standings ?: securedStandings(store)
        val picks = MockLibrary.mcqPicks(store.library) { pick ->
            ((known[pick.question.id] ?: SecuredRule.Standing.New) as? SecuredRule.Standing.Building)?.let { it.n > 0 } == true
        }
        val today = Instant.ofEpochMilli(now).atZone(zone()).toLocalDate()
        val rightToday = store.answerLog.filter { it.correct && Instant.ofEpochMilli(it.at).atZone(zone()).toLocalDate() == today }
            .map { it.questionId }.toSet()
        val open = picks.filter { it.question.id !in rightToday }
        val order = SecuredRule.closeToSecure(open.map { it.question.id }, known)
        val byId = LinkedHashMap<String, QuestionPick>()
        for (p in open) byId.putIfAbsent(p.question.id, p)
        return order.mapNotNull { byId[it] }
    }

    fun lockInQuiz(store: StudyStore, limit: Int = 20): StudySet =
        MockLibrary.temporaryQuiz("Lock it in", "Lock it in", lockInPicks(store).take(limit).shuffled())

    // MARK: mistakes and the day's rhythm

    /** Questions whose last answer was wrong. */
    fun lastWrongPicks(store: StudyStore): List<QuestionPick> =
        MockLibrary.mcqPicks(store.library) { store.answerHistory[it.question.id]?.lastOrNull() == false }

    fun mistakesQuiz(store: StudyStore, limit: Int = 30): StudySet =
        MockLibrary.temporaryQuiz("Your mistakes", "Mistakes", lastWrongPicks(store).shuffled().take(limit))

    /** The questions got wrong while sure, still in the library. */
    fun confidentMistakePicks(store: StudyStore): List<QuestionPick> {
        val ids = store.confidentMistakeIds
        if (ids.isEmpty()) return emptyList()
        return MockLibrary.mcqPicks(store.library) { it.question.id in ids }
    }

    fun confidentMistakesQuiz(store: StudyStore, limit: Int = 20): StudySet =
        MockLibrary.temporaryQuiz("Confident mistakes", "Confident mistakes", confidentMistakePicks(store).shuffled().take(limit))

    /** Every flagged question still in the library, once each. */
    fun flaggedPicks(store: StudyStore): List<QuestionPick> =
        if (store.flagged.isEmpty()) emptyList() else MockLibrary.mcqPicks(store.library) { it.question.id in store.flagged }

    fun flaggedQuiz(store: StudyStore): StudySet? {
        val picks = flaggedPicks(store)
        if (picks.isEmpty()) return null
        return MockLibrary.temporaryQuiz("Flagged questions", "Flagged", picks.shuffled())
    }

    /** Questions never answered, mixed across the library: never offered in exam week. */
    fun untriedQuiz(store: StudyStore, limit: Int = 20): StudySet {
        val fresh = MockLibrary.mcqPicks(store.library) { store.answerHistory[it.question.id].orEmpty().isEmpty() }
        return MockLibrary.temporaryQuiz("New questions", "Mixed", fresh.shuffled().take(limit))
    }

    /** The library's questions for these ids, in the ids' order. */
    fun picks(store: StudyStore, ids: List<String>): List<QuestionPick> {
        val wanted = ids.toSet()
        val byId = LinkedHashMap<String, QuestionPick>()
        for (p in MockLibrary.mcqPicks(store.library) { it.question.id in wanted }) byId.putIfAbsent(p.question.id, p)
        return ids.mapNotNull { byId[it] }
    }

    /** Today's misses, for the evening re-read. */
    fun bedtimePicks(store: StudyStore, now: Long = System.currentTimeMillis()): List<QuestionPick> =
        picks(store, StudyRhythm.missed(now, store.answerLog, zone()))

    /** Yesterday's misses not yet answered today, for the morning check. */
    fun morningPicks(store: StudyStore, now: Long = System.currentTimeMillis()): List<QuestionPick> =
        picks(store, StudyRhythm.morningItems(now, store.answerLog, zone()))

    fun morningCheckQuiz(store: StudyStore, now: Long = System.currentTimeMillis()): StudySet =
        MockLibrary.temporaryQuiz("Morning check", "Morning check", morningPicks(store, now).take(10))

    /** One question as a quiz of its own (the question of the day). */
    fun singleQuestionQuiz(store: StudyStore, id: String): StudySet? {
        val pick = picks(store, listOf(id)).firstOrNull() ?: return null
        return MockLibrary.temporaryQuiz("Question of the day", MockLibrary.subjectName(pick.set), listOf(pick))
    }

    // MARK: exam week

    /** Everything the lift-off button weighs up. */
    fun examSituation(store: StudyStore, dueCards: Int, mocksFile: File?, now: Long = System.currentTimeMillis()): ExamWeekPlanner.Situation {
        val exam = store.examDate
        val standings = securedStandings(store)
        val weakest = HomeRound.subjectStats(store).firstOrNull { it.answered > 0 && it.accuracy < 0.8 }?.name
        val untried = MockLibrary.mcqPicks(store.library) { store.answerHistory[it.question.id].orEmpty().isEmpty() }.size
        return ExamWeekPlanner.Situation(
            phase = ExamWeekPlanner.phase(exam?.let { Instant.ofEpochMilli(it) }, Instant.ofEpochMilli(now), zone()),
            dueCards = dueCards,
            confidentErrors = confidentMistakePicks(store).size,
            missed = lastWrongPicks(store).size,
            flagged = flaggedPicks(store).size,
            closeToSecure = lockInPicks(store, standings, now).size,
            untried = untried,
            morningCheck = if (LearnMarks.morningCheckWanted(now)) morningPicks(store, now).size else 0,
            mockDone = LearnMarks.mockDone(exam, mocksFile),
            weakestSubject = weakest,
        )
    }

    /** The exam-day forecast for every deck in the library. */
    fun examForecast(store: StudyStore, now: Long = System.currentTimeMillis()): RetentionForecast.Forecast =
        RetentionForecast.forecast(deckCardIds(store), store.reviews, now, store.examDate)

    fun deckCardIds(store: StudyStore): List<String> =
        store.library.filter { it.kind == StudySetKind.ANKI }.flatMap { set -> set.cards.map { it.id } }

    // MARK: symptom blocks

    /** Every library question as the symptom blocks see it. */
    fun symptomItems(store: StudyStore): List<SymptomBlocks.Item> = MockLibrary.mcqPicks(store.library).mapNotNull { pick ->
        val q = pick.question
        if (q.correctIndex !in q.options.indices) null else SymptomBlocks.Item(q.id, q.stem, q.options[q.correctIndex])
    }

    /** A block's questions, interleaved, at most [limit]. */
    fun symptomQuiz(store: StudyStore, block: SymptomBlocks.Block, limit: Int = 20): StudySet {
        val wanted = block.ids.toSet()
        val items = symptomItems(store).filter { it.id in wanted }
        val order = SymptomBlocks.interleaved(items).take(limit).map { it.id }
        return MockLibrary.temporaryQuiz(block.presentation.blockTitle, block.presentation.name, picks(store, order))
    }

    /** The options and right answer of each question in [picks], for the mix-ups. */
    fun optionsById(picks: List<QuestionPick>): Map<String, SymptomBlocks.Options> =
        picks.associate { it.question.id to SymptomBlocks.Options(it.question.options, it.question.correctIndex) }

    /** Answers given to [ids] since [since]. */
    fun answersSince(store: StudyStore, ids: Set<String>, since: Long): List<AnswerEvent> =
        store.answerLog.filter { it.at >= since && it.questionId in ids }
}

/**
 * Small marks kept on this device (iOS LearnMarks): whether the mock was sat
 * for this exam date, whether the morning check was done today, which sets
 * have had their pretest.
 */
internal object LearnMarks {
    const val morningKey = "learn.morning.done"
    const val pretestKey = "learn.pretest.seen"

    private fun dayKey(at: Long): String = Instant.ofEpochMilli(at).atZone(ZoneId.systemDefault()).toLocalDate().toString()

    /**
     * Whether a mock paper was finished in the run-up to this exam date: from
     * the start of the mock window (T-10) to the end of the day itself.
     */
    fun mockDone(exam: Long?, mocksFile: File?): Boolean {
        if (exam == null || mocksFile == null) return false
        val zone = ZoneId.systemDefault()
        val day = Instant.ofEpochMilli(exam).atZone(zone).toLocalDate()
        val opens = day.minusDays(10).atStartOfDay(zone).toInstant().toEpochMilli()
        val closes = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        return MockRecords.load(mocksFile).any { it.date in opens until closes }
    }

    /** The morning check is offered until it is opened, and only in the morning (before noon). */
    fun morningCheckWanted(now: Long = System.currentTimeMillis(), defaults: LearnDefaults = LearnDefaults.shared): Boolean {
        val hour = Instant.ofEpochMilli(now).atZone(ZoneId.systemDefault()).hour
        if (hour < 4 || hour >= 12) return false
        return defaults.string(morningKey) != dayKey(now)
    }

    fun markMorningDone(now: Long = System.currentTimeMillis(), defaults: LearnDefaults = LearnDefaults.shared) =
        defaults.set(morningKey, dayKey(now))

    /** Whether the pretest has been offered for a set. */
    fun pretestSeen(setId: String, defaults: LearnDefaults = LearnDefaults.shared): Boolean = setId in defaults.strings(pretestKey)

    fun markPretestSeen(setId: String, defaults: LearnDefaults = LearnDefaults.shared) {
        val seen = defaults.strings(pretestKey)
        if (setId in seen) return
        // a few hundred sets is more than anybody opens; keep the newest
        defaults.setStrings(pretestKey, (seen + setId).takeLast(500))
    }
}

/** Which sets get a pretest, and its questions (iOS GuessFirst). */
internal object GuessFirst {
    /** Textbooks and narrate sets: the sets that are read rather than answered. */
    fun offers(set: StudySet): Boolean = set.kind == StudySetKind.BOOK || set.kind == StudySetKind.NARRATE

    /** The text a set is read from. */
    fun text(set: StudySet): String = when (set.kind) {
        StudySetKind.BOOK -> set.bookMarkdown
        StudySetKind.NARRATE -> set.narrateSegments.joinToString(" ") { it.text }
        else -> set.sources.flatMap { s -> s.pages.map { it.text } }.joinToString("\n")
    }

    /** FNV-1a over the id's characters, so the same set asks the same questions on every launch. */
    fun seed(set: StudySet): ULong {
        var seed = 1_469_598_103_934_665_603uL
        for (byte in set.id.uppercase().toByteArray(Charsets.UTF_8)) seed = (seed xor byte.toUByte().toULong()) * 1_099_511_628_211uL
        return seed
    }

    fun questions(set: StudySet): List<MCQQuestion> = Pretest.questions(text(set), seed = seed(set))

    /** Whether this set should get its pretest now: first opening, and enough text to ask about. */
    fun isDue(set: StudySet, defaults: LearnDefaults = LearnDefaults.shared): Boolean =
        offers(set) && !LearnMarks.pretestSeen(set.id, defaults) && questions(set).isNotEmpty()
}

/** Up to and including the first full stop that ends a sentence (iOS RuleWriter.firstSentence). */
internal fun firstSentence(text: String): String {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return ""
    for (i in trimmed.indices) {
        if (trimmed[i] in ".!?" && (i + 1 == trimmed.length || trimmed[i + 1].isWhitespace())) return trimmed.substring(0, i + 1)
    }
    return trimmed
}
