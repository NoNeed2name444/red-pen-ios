package com.stethoscore.app.ui.vitals

import com.stethoscore.app.data.BedPlan
import com.stethoscore.app.data.CalibrationRow
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.data.ReadinessEstimate
import com.stethoscore.app.data.ReasonShare
import com.stethoscore.app.data.RhythmReading
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.StudyStreak
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MistakeReason
import com.stethoscore.app.ui.home.HomeRound
import com.stethoscore.app.ui.mock.MockLibrary
import com.stethoscore.app.ui.mock.QuestionPick
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.roundToInt

// The numbers behind the Vitals screen (upstream AnalyticsView.swift's
// snapshot, daily target, syllabus gaps and Focus next), worked out in one
// pass over what the store keeps, apart from the screen so they can be
// tested on the JVM. Nothing new is stored.

/** Answers and right answers, added up. */
class Tally(var answered: Int = 0, var correct: Int = 0) {
    val accuracy: Double get() = if (answered == 0) 0.0 else correct.toDouble() / answered
    fun add(right: Boolean) { answered += 1; if (right) correct += 1 }
}

/** The latest wrong answer to one question. */
data class WrongAnswer(val pick: QuestionPick, val date: Long, val reason: MistakeReason?, val picked: Int?)

/** Which way a subject is going: the last two weeks against before. */
@Suppress("EnumEntryName")
enum class Trend(val label: String) { up("Improving"), down("Slipping"), flat("Steady") }

/** What the syllabus check found for the chosen exam. */
data class CoverageGaps(val missing: Int, val total: Int, val first: String?, val covered: Int, val thin: Int, val track: ExamTrack)

/** What tapping a Focus next row starts. */
sealed class FocusAction {
    data class Drill(val subject: String) : FocusAction()
    object ConfidentQuiz : FocusAction()
    object Due : FocusAction()
    object Coverage : FocusAction()
    data class Reason(val reason: MistakeReason) : FocusAction()
}

/** The glyphs a Focus next row can carry (iOS's SF Symbol names, drawn by VitalsScreen). */
@Suppress("EnumEntryName")
enum class FocusGlyph { scope, warning, cards, checklist, reason }

/** One suggested next step, with the reason it is suggested. */
data class FocusItem(
    val id: String, val title: String,
    /** The short "why": "31% right in Renal over 42 answers". */
    val detail: String,
    val glyph: FocusGlyph, val score: Double, val action: FocusAction,
    /** The subject, for a drill, so its row can show a sparkline. */
    val subject: String? = null,
)

/** Everything the page shows, worked out in one pass over the answer log. */
data class VitalsSnapshot(
    val stats: List<BedPlan.Topic>,
    val due: Int,
    val confidentWrong: Int,
    val shares: List<ReasonShare>,
    val weeks: List<WeekPoint>,
    val days: List<DayPoint>,
    val wrong: List<WrongAnswer>,
    val trends: Map<String, Trend>,
    val studiedThisMonth: Int,
    val readiness: ReadinessEstimate?,
    /** Answers in the last 30 days. */
    val lastMonthAnswered: Int,
    val lastMonthCorrect: Int,
    /** Amount studied per day, keyed yyyy-MM-dd. */
    val dayCounts: Map<String, Int>,
    /** Amount studied today. */
    val today: Int,
    /** Each subject's accuracy day by day over the last 14 days. */
    val sparks: Map<String, List<SparkPoint>>,
    val calibration: List<CalibrationRow>,
    /** Answers the readiness estimate can read. */
    val recentCount: Int,
    /** Whether any of it is example history. */
    val includesExamples: Boolean,
    val streak: Int,
    /** The missed days a rest day covered. */
    val restDays: Set<String>,
) {
    /** Accuracy over the last 30 days, or null with no answers in them. */
    val monthAccuracy: Double? get() = if (lastMonthAnswered > 0) lastMonthCorrect.toDouble() / lastMonthAnswered else null
}

object VitalsNumbers {
    private const val day = 86_400_000L

    fun snapshot(store: StudyStore, track: ExamTrack, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): VitalsSnapshot {
        val picks = HashMap<String, QuestionPick>()
        for (pick in MockLibrary.mcqPicks(store.library)) picks[pick.question.id] = pick
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val weekAnswered = IntArray(8)
        val weekCorrect = IntArray(8)
        val perDay = HashMap<String, Int>()
        val recent = HashMap<String, Tally>()
        val earlier = HashMap<String, Tally>()
        val fortnight = now - 14 * day
        val month30 = now - 30 * day
        val lastMonth = Tally()
        val sparkDays = HashMap<String, MutableMap<LocalDate, Tally>>()
        for (event in store.answerLog) {
            if (event.at >= month30) lastMonth.add(event.correct)
            val date = Instant.ofEpochMilli(event.at).atZone(zone).toLocalDate()
            val key = RhythmReading.key(date)
            perDay[key] = (perDay[key] ?: 0) + 1
            val daysAgo = ChronoUnit.DAYS.between(date, today)
            if (daysAgo in 0 until 56) {
                val week = 7 - (daysAgo / 7).toInt()
                weekAnswered[week] += 1
                if (event.correct) weekCorrect[week] += 1
            }
            val pick = picks[event.questionId] ?: continue
            val subject = MockLibrary.subjectName(pick.set)
            if (event.at >= fortnight) {
                recent.getOrPut(subject) { Tally() }.add(event.correct)
                sparkDays.getOrPut(subject) { HashMap() }.getOrPut(date) { Tally() }.add(event.correct)
            } else {
                earlier.getOrPut(subject) { Tally() }.add(event.correct)
            }
        }
        val weeks = (0 until 8).filter { weekAnswered[it] > 0 }.map { week ->
            WeekPoint(today.minusDays(((7 - week) * 7 + 6).toLong()), weekAnswered[week], weekCorrect[week].toDouble() / weekAnswered[week])
        }

        // the study log: answers checked and cards rated (StudyLog's days)
        val log = HomeRound.studyDays(store, zone)
        // studied per day for the last 30 days: the larger of the two records
        val days = (29 downTo 0).map { back ->
            val d = today.minusDays(back.toLong())
            val key = RhythmReading.key(d)
            DayPoint(d, maxOf(log[key] ?: 0, perDay[key] ?: 0))
        }
        // days with anything done this month, from either record
        val month = RhythmReading.key(today).take(7)
        val studiedKeys = log.filter { it.value > 0 }.keys + perDay.keys
        val studiedThisMonth = studiedKeys.count { it.startsWith(month) }
        // every day's amount, the larger of the two records, for the calendar
        val dayCounts = HashMap(log)
        for ((key, count) in perDay) if (count > (dayCounts[key] ?: 0)) dayCounts[key] = count

        val sparks = sparkDays.mapValues { (_, byDay) -> byDay.map { SparkPoint(it.key, it.value.accuracy) }.sortedBy { it.day } }

        val trends = HashMap<String, Trend>()
        for ((subject, latest) in recent) {
            val before = earlier[subject] ?: continue
            if (before.answered < 3 || latest.answered < 3) continue
            val change = latest.accuracy - before.accuracy
            trends[subject] = if (change > 0.05) Trend.up else if (change < -0.05) Trend.down else Trend.flat
        }

        // the latest wrong answer to each question still in the library
        val wrong = mutableListOf<WrongAnswer>()
        val seen = HashSet<String>()
        for (event in store.answerLog.asReversed()) {
            if (event.correct) continue
            if (wrong.size >= 40 || !seen.add(event.questionId)) continue
            val pick = picks[event.questionId] ?: continue
            wrong.add(WrongAnswer(pick, event.at, store.mistakeReasons[event.questionId]?.reason?.let { MistakeReason.from(it) }, event.picked))
        }

        val due = store.dueAcross(now).size
        val active = dayCounts.filter { it.value > 0 }.keys
        val streak = StudyStreak.summary(active, Instant.ofEpochMilli(now), zone)
        return VitalsSnapshot(
            stats = HomeRound.subjectStats(store), due = due,
            confidentWrong = StoreInsight.confidentMistakePicks(store).size,
            shares = StoreInsight.reasonShares(store, now = now),
            weeks = weeks, days = days, wrong = wrong, trends = trends, studiedThisMonth = studiedThisMonth,
            readiness = StoreInsight.readiness(store, due, track),
            lastMonthAnswered = lastMonth.answered, lastMonthCorrect = lastMonth.correct,
            dayCounts = dayCounts, today = dayCounts[RhythmReading.key(today)] ?: 0, sparks = sparks,
            calibration = StoreInsight.calibration(store), recentCount = StoreInsight.recentAnswers(store).size,
            includesExamples = StoreInsight.includesExampleData(store),
            streak = streak.streak, restDays = streak.restDays,
        )
    }

    /**
     * How much to do today: the pace that gets through every question in the
     * library by the exam date, or 30 when no date is set or it has passed.
     * The second is whether it came from the exam date.
     */
    fun dailyTarget(store: StudyStore, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Pair<Int, Boolean> {
        val exam = store.examDate ?: return 30 to false
        val days = ExamWeekPlanner.daysLeft(Instant.ofEpochMilli(exam), Instant.ofEpochMilli(now), zone)
        val questions = store.library.filter { it.kind == StudySetKind.MCQ }.sumOf { it.questions.size }
        if (days <= 0 || questions <= 0) return 30 to false
        return maxOf(1, ceil(questions.toDouble() / days).toInt()) to true
    }

    /** The day's target in words, for the rings' footnote. */
    fun ringsNote(fromExam: Boolean): String {
        val pace = if (fromExam) "the pace that gets through your library by the exam." else "30 until you set an exam date."
        return "Tap a ring for what is behind it. Syllabus is the share of your exam’s topics your library covers. Today’s target is $pace"
    }

    /** The share of the exam's topics covered, once the check has run. */
    fun syllabusShare(gaps: CoverageGaps?): Double? = if (gaps == null || gaps.total <= 0) null else gaps.covered.toDouble() / gaps.total

    fun syllabusSpoken(gaps: CoverageGaps?): String =
        if (gaps == null || gaps.total <= 0) "still checking"
        else "${gaps.covered} topics covered, ${gaps.thin} thin, ${gaps.missing} missing, of ${gaps.total}"

    /** "Practise what you didn’t know" and the rest: the fix offered for each reason. */
    fun fixTitle(reason: MistakeReason): String = when (reason) {
        MistakeReason.didntKnow -> "Practise what you didn’t know"
        MistakeReason.misread -> "Slow reading drill"
        MistakeReason.changedAnswer -> "Stop changing right answers"
        MistakeReason.outOfTime -> "Timed drill"
        MistakeReason.lookalikes -> "Tell lookalikes apart"
    }

    /** The reading tip shown over the questions for the reasons that call for reading. */
    fun tip(reason: MistakeReason): String? = when (reason) {
        MistakeReason.changedAnswer -> "Change an answer only when you find a clue in the stem you missed the first time, not because a second option starts to look good. Your first answer was right here."
        MistakeReason.lookalikes -> "For each, name the one feature that tells the right answer from the option you chose."
        else -> null
    }

    const val confidentTip = "These felt certain and were not: usually a fact learned wrongly rather than one not learned. Read the explanation, then quiz them again."

    /**
     * Every candidate next step with its score, best first, five at most.
     * Each score is out of about 100, "how many marks this is likely worth":
     * a weak subject: how often it is missed, trusted fully from 20 answers;
     * confident mistakes: 40, and 5 more for each one; cards waiting: 15, and
     * 1 more for each card, at most 85; syllabus gaps: 10, and up to 60 more
     * for the share of topics missing; the commonest reason for a lost mark:
     * its share, trusted fully from 5.
     */
    fun focusItems(s: VitalsSnapshot, gaps: CoverageGaps?): List<FocusItem> {
        val items = mutableListOf<FocusItem>()
        for (subject in s.stats.filter { it.answered >= 5 && it.accuracy < 0.75 }.take(2)) {
            val percent = (subject.accuracy * 100).roundToInt()
            val trust = minOf(1.0, subject.answered / 20.0)
            val missed = (1 - subject.accuracy) * 100
            items.add(FocusItem("drill-" + subject.name, "Drill ${subject.name}",
                "$percent% right in ${subject.name} over ${subject.answered} answers", FocusGlyph.scope, missed * trust,
                FocusAction.Drill(subject.name), subject.name))
        }
        if (s.confidentWrong > 0) {
            val n = s.confidentWrong
            items.add(FocusItem("confident", "Confident mistakes quiz", "$n question${if (n == 1) "" else "s"} you were sure of and got wrong",
                FocusGlyph.warning, minOf(95.0, 40.0 + n * 5), FocusAction.ConfidentQuiz))
        }
        if (s.due > 0) {
            items.add(FocusItem("due", "Review cards due", "${s.due} card${if (s.due == 1) "" else "s"} waiting for review",
                FocusGlyph.cards, minOf(85.0, 15.0 + s.due), FocusAction.Due))
        }
        if (gaps != null && gaps.missing > 0 && gaps.total > 0) {
            val exam = if (gaps.track == ExamTrack.general) "syllabus" else gaps.track.rawValue.uppercase(Locale.ROOT)
            var detail = "${gaps.missing} of ${gaps.total} $exam topics have nothing in your library"
            if (gaps.first != null) detail += ", such as ${gaps.first}"
            items.add(FocusItem("gaps", "Fill syllabus gaps", detail, FocusGlyph.checklist,
                10 + 60 * gaps.missing.toDouble() / gaps.total, FocusAction.Coverage))
        }
        val top = s.shares.firstOrNull()
        if (top != null && top.count >= 2) {
            val percent = (top.share * 100).roundToInt()
            items.add(FocusItem("reason", fixTitle(top.reason),
                "${top.reason.title}: $percent% of the reasons you gave, last ${StoreInsight.reasonWindowDays} days",
                FocusGlyph.reason, percent * minOf(1.0, top.count / 5.0), FocusAction.Reason(top.reason)))
        }
        return items.sortedByDescending { it.score }.take(5)
    }

    /** The average over the days in the last 30 studied at all, or null with none. */
    fun dailyAverage(days: List<DayPoint>): Int? {
        val active = days.filter { it.count > 0 }
        if (active.isEmpty()) return null
        return (active.sumOf { it.count }.toDouble() / active.size).roundToInt()
    }
}
