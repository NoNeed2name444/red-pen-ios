package com.stethoscore.app.data

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

// A port of upstream/ios/RedPen/Shared/Learn/BedPlan.swift (today's ward
// round on the home screen) with the parts of ExamWeekPlanner it reads (the
// phase from the exam date, and the mission's cases). Pure Kotlin.
//
// The round holds at most four beds, in this order: the run-up's own
// priority (ExamWeekPlanner's mission, when it is a bed of its own); the
// cards due today; the weakest topic; the newest set nothing has been done
// in yet (never in exam week), or new questions when the planner asks for
// them; an OSCE station, one part way through first. On exam day the round
// is the kit alone. Nothing here is stored.

/** The run-up to the exam (iOS ExamWeekPlanner): its phases and the one most useful session. */
object ExamWeekPlanner {
    sealed class Phase {
        object NoDate : Phase()
        data class Building(val days: Int) : Phase()
        data class MockWindow(val days: Int) : Phase()
        data class ExamWeek(val days: Int) : Phase()
        object ExamDay : Phase()
        object After : Phase()

        /** Whether new material should be held back. */
        val holdsNewMaterial: Boolean get() = this is ExamWeek || this == ExamDay

        val headline: String get() = when (this) {
            NoDate -> "No exam date set"
            is Building -> "Learn and keep"
            is MockWindow -> "Mock week"
            is ExamWeek -> "Exam week — nothing new"
            ExamDay -> "Exam day"
            After -> "Exam done"
        }
    }

    sealed class Mission {
        object ExamKit : Mission()
        data class MorningCheck(val n: Int) : Mission()
        data class DueCards(val n: Int) : Mission()
        object Mock : Mission()
        data class ConfidentErrors(val n: Int) : Mission()
        data class Mistakes(val n: Int) : Mission()
        data class LockIn(val n: Int) : Mission()
        data class Flagged(val n: Int) : Mission()
        data class Weakest(val subject: String) : Mission()
        object NewQuestions : Mission()
        object Nothing : Mission()
    }

    /** Calendar days from today to the exam's day, in [zone]. */
    fun daysLeft(exam: Instant, now: Instant, zone: ZoneId): Int =
        ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), exam.atZone(zone).toLocalDate()).toInt()

    fun phase(exam: Instant?, now: Instant, zone: ZoneId): Phase {
        if (exam == null) return Phase.NoDate
        val days = daysLeft(exam, now, zone)
        return when {
            days < 0 -> Phase.After
            days == 0 -> Phase.ExamDay
            days <= 7 -> Phase.ExamWeek(days)
            days <= 10 -> Phase.MockWindow(days)
            else -> Phase.Building(days)
        }
    }
}

object BedPlan {
    /** The most beds a round holds. */
    const val most = 4
    /** A subject needs a consult below this accuracy... */
    const val consultBelow = 0.75
    /** ...once it has at least this many answers to judge it by. */
    const val consultAnswers = 5
    const val secondsPerCard = 10
    const val secondsPerPage = 180
    const val firstSitting = 20
    const val firstPages = 3

    /** A subject as the answer history sees it. */
    data class Topic(val name: String, val questions: Int, val answered: Int, val correct: Int) {
        val accuracy: Double get() = if (answered == 0) 0.0 else correct.toDouble() / answered
        /** 48 for 0.48. */
        val percent: Int get() = Math.round(accuracy * 100).toInt()
    }

    /** The modes a set can take a bed in. */
    enum class Mode(val label: String, val noun: String) {
        questions("MCQ", "question"), cards("Cards", "card"), textbook("Textbook", "page")
    }

    data class FreshSet(val id: String, val name: String, val subject: String, val mode: Mode, val items: Int, val createdAt: Long)

    data class Station(val setID: String, val title: String, val resumes: Boolean, val createdAt: Long)

    data class Input(
        val mission: ExamWeekPlanner.Mission = ExamWeekPlanner.Mission.Nothing,
        val phase: ExamWeekPlanner.Phase = ExamWeekPlanner.Phase.NoDate,
        val dueCards: Int = 0,
        /** The subjects the due cards come from, most cards first. */
        val dueFrom: List<String> = emptyList(),
        val topics: List<Topic> = emptyList(),
        val fresh: List<FreshSet> = emptyList(),
        val stations: List<Station> = emptyList(),
        val untried: Int = 0,
        val secondsPerQuestion: Int = 75,
        val stationMinutes: Int = 8,
        val mockMinutes: Int = 60,
    )

    /** What a bed holds, and so what a tap on it starts. */
    sealed class Kind {
        data class Priority(val mission: ExamWeekPlanner.Mission) : Kind()
        data class DueCards(val count: Int) : Kind()
        data class Weakest(val topic: Topic) : Kind()
        data class Fresh(val set: FreshSet) : Kind()
        data class OsceStation(val station: Station) : Kind()
    }

    /** The chip at the end of a bed's row. */
    enum class Status(val rawValue: String) { due("Due"), new("New"), weak("Weak"), timed("Timed"), today("Today") }

    data class Bed(val number: Int, val kind: Kind, val ward: String, val title: String, val detail: String,
                   val status: Status?, val minutes: Int) {
        /** "Bed 1 · Cardiology"; the row shows it in small caps. */
        val overline: String get() = "Bed $number · $ward"

        /** What TalkBack reads for the whole row. */
        val spoken: String get() {
            val parts = mutableListOf("Bed $number, $ward", title, detail, aboutMinutes(minutes))
            if (status != null) parts.add(status.rawValue)
            return parts.joinToString(". ")
        }

        /** The same bed keeps its identity as the beds before it come and go. */
        val id: String get() = when (kind) {
            is Kind.Priority -> "priority"
            is Kind.DueCards -> "due"
            is Kind.Weakest -> "weakest-" + kind.topic.name
            is Kind.Fresh -> "fresh-" + kind.set.id
            is Kind.OsceStation -> "station-" + kind.station.setID
        }
    }

    /** The subjects that need a consult, weakest first. */
    fun weakSpots(topics: List<Topic>): List<Topic> =
        topics.filter { it.answered >= consultAnswers && it.accuracy < consultBelow }
            .sortedWith(compareBy<Topic> { it.accuracy }.thenByDescending { it.answered }.thenBy { it.name })

    /**
     * What the round does about the subjects that need a consult, for the
     * Vitals screen: the weakest is on it automatically, except on exam day,
     * when the kit is the whole round. With none, why none.
     */
    fun consultNote(spots: List<Topic>, phase: ExamWeekPlanner.Phase, anyJudged: Boolean): String {
        val line = Math.round(consultBelow * 100).toInt()
        val first = spots.firstOrNull()
        if (first == null) {
            if (anyJudged) return "Nothing needs a consult: every subject with $consultAnswers or more answers is at $line% or better."
            return "A subject shows here once it has $consultAnswers answers and is under $line%."
        }
        if (phase == ExamWeekPlanner.Phase.ExamDay) return "Exam day: today’s ward round is your kit alone, so these can wait."
        return "${first.name}, the weakest, is on today’s ward round automatically."
    }

    /** Today's beds, numbered from 1. */
    fun beds(input: Input): List<Bed> {
        val kinds = mutableListOf<Kind>()
        if (input.phase == ExamWeekPlanner.Phase.ExamDay) {
            // nothing to learn today: the kit, and nothing else
            kinds.add(Kind.Priority(ExamWeekPlanner.Mission.ExamKit))
        } else {
            priority(input.mission)?.let { kinds.add(Kind.Priority(it)) }
            if (input.dueCards > 0) kinds.add(Kind.DueCards(input.dueCards))
            weakest(input)?.let { kinds.add(Kind.Weakest(it)) }
            if (!input.phase.holdsNewMaterial) {
                val set = newest(input.fresh)
                if (set != null) kinds.add(Kind.Fresh(set))
                else if (input.mission == ExamWeekPlanner.Mission.NewQuestions && input.untried > 0)
                    kinds.add(Kind.Priority(ExamWeekPlanner.Mission.NewQuestions))
            }
            station(input.stations)?.let { kinds.add(Kind.OsceStation(it)) }
        }
        return kinds.take(most).mapIndexed { index, kind -> bed(kind, index + 1, input) }
    }

    /** The planner's mission when it is a bed of its own. */
    fun priority(mission: ExamWeekPlanner.Mission): ExamWeekPlanner.Mission? = when (mission) {
        ExamWeekPlanner.Mission.ExamKit, is ExamWeekPlanner.Mission.MorningCheck, ExamWeekPlanner.Mission.Mock,
        is ExamWeekPlanner.Mission.ConfidentErrors, is ExamWeekPlanner.Mission.Mistakes,
        is ExamWeekPlanner.Mission.LockIn, is ExamWeekPlanner.Mission.Flagged -> mission
        else -> null
    }

    /** The weakest subject that needs a consult; failing that, the subject the planner itself would drill. */
    fun weakest(input: Input): Topic? {
        weakSpots(input.topics).firstOrNull()?.let { return it }
        val mission = input.mission
        if (mission is ExamWeekPlanner.Mission.Weakest) return input.topics.firstOrNull { it.name == mission.subject && it.questions > 0 }
        return null
    }

    fun newest(fresh: List<FreshSet>): FreshSet? =
        fresh.filter { it.items > 0 }.maxWithOrNull(compareBy<FreshSet> { it.createdAt }.thenByDescending { it.name })

    /** A station part way through first, else the newest. */
    fun station(stations: List<Station>): Station? =
        stations.maxWithOrNull(compareBy<Station> { it.resumes }.thenBy { it.createdAt }.thenByDescending { it.title })

    fun bed(kind: Kind, number: Int, input: Input): Bed {
        val q = input.secondsPerQuestion
        return when (kind) {
            is Kind.Priority -> priorityBed(kind.mission, number, input)
            is Kind.DueCards -> {
                val one = input.dueFrom.size == 1
                val ward = if (one) input.dueFrom[0] else "Spaced review"
                val detail = if (input.dueFrom.size > 1) "From ${input.dueFrom.size} subjects" else "Spaced review"
                Bed(number, kind, ward, counted(kind.count, "card") + " due", detail, Status.due, minutes(seconds = kind.count * secondsPerCard))
            }
            is Kind.Weakest -> {
                val drill = minOf(firstSitting, maxOf(1, kind.topic.questions))
                Bed(number, kind, kind.topic.name, "Weakest topic · ${kind.topic.percent}%",
                    "$drill MCQ${if (drill == 1) "" else "s"}, missed ones first", Status.weak, minutes(seconds = drill * q))
            }
            is Kind.Fresh -> {
                val set = kind.set
                val subject = set.subject.trim()
                val ward = if (subject.isEmpty() || subject == "General") set.mode.label else subject
                val detail = "${set.mode.label} · ${counted(set.items, set.mode.noun)} · not started"
                Bed(number, kind, ward, set.name, detail, Status.new, firstSittingMinutes(set, q))
            }
            is Kind.OsceStation -> {
                var detail = "${input.stationMinutes} min timed"
                if (kind.station.resumes) detail += " · carry on where you left off"
                Bed(number, kind, "OSCE station", kind.station.title, detail, null, maxOf(1, input.stationMinutes))
            }
        }
    }

    private fun priorityBed(mission: ExamWeekPlanner.Mission, number: Int, input: Input): Bed {
        val q = input.secondsPerQuestion
        val kind = Kind.Priority(mission)
        return when (mission) {
            ExamWeekPlanner.Mission.ExamKit -> Bed(number, kind, "Exam day", "Your exam-day kit",
                "What to bring, the pacing, and calm", Status.today, 5)
            is ExamWeekPlanner.Mission.MorningCheck -> Bed(number, kind, "Morning check", counted(mission.n, "question") + " from yesterday",
                "Yesterday’s misses, before anything new", Status.due, minutes(seconds = minOf(mission.n, 10) * q))
            ExamWeekPlanner.Mission.Mock -> Bed(number, kind, "Mock week", "Sit a mock paper",
                "Once, under exam timing", Status.timed, maxOf(1, input.mockMinutes))
            is ExamWeekPlanner.Mission.ConfidentErrors -> Bed(number, kind, "Sure but wrong", counted(mission.n, "confident error"),
                "Facts learned wrongly, put right first", Status.weak, minutes(seconds = minOf(mission.n, firstSitting) * q))
            is ExamWeekPlanner.Mission.Mistakes -> Bed(number, kind, "Your mistakes", counted(mission.n, "missed question"),
                "The ones you got wrong last time", Status.weak, minutes(seconds = minOf(mission.n, 30) * q))
            is ExamWeekPlanner.Mission.LockIn -> Bed(number, kind, "Lock it in", counted(mission.n, "question") + " close to secure",
                "One more right day each", Status.due, minutes(seconds = minOf(mission.n, firstSitting) * q))
            is ExamWeekPlanner.Mission.Flagged -> Bed(number, kind, "Flagged", counted(mission.n, "flagged question"),
                "The ones you marked to come back to", Status.due, minutes(seconds = mission.n * q))
            ExamWeekPlanner.Mission.NewQuestions -> Bed(number, kind, "New questions", "${input.untried} not tried yet",
                "Up to $firstSitting, mixed across your sets", Status.new, minutes(seconds = minOf(input.untried, firstSitting) * q))
            is ExamWeekPlanner.Mission.DueCards -> bed(Kind.DueCards(mission.n), number, input)
            is ExamWeekPlanner.Mission.Weakest -> {
                val topic = input.topics.firstOrNull { it.name == mission.subject } ?: Topic(mission.subject, firstSitting, 0, 0)
                bed(Kind.Weakest(topic), number, input)
            }
            ExamWeekPlanner.Mission.Nothing -> Bed(number, kind, "All quiet", "Nothing is waiting", "Come back later", null, 0)
        }
    }

    /** A new set's first sitting: twenty questions or cards, three pages. */
    fun firstSittingMinutes(set: FreshSet, secondsPerQuestion: Int): Int = when (set.mode) {
        Mode.questions -> minutes(seconds = minOf(set.items, firstSitting) * secondsPerQuestion)
        Mode.cards -> minutes(seconds = minOf(set.items, firstSitting) * secondsPerCard)
        Mode.textbook -> minutes(seconds = minOf(set.items, firstPages) * secondsPerPage)
    }

    /** The round's minutes: each bed's, added up. */
    fun minutes(beds: List<Bed>): Int = beds.sumOf { it.minutes }

    /** "4 patients · 45 min". */
    fun summary(beds: List<Bed>): String {
        if (beds.isEmpty()) return "No patients waiting"
        return counted(beds.size, "patient") + " · ${minutes(beds)} min"
    }

    /** "Today's ward round: 4 patients, about 45 minutes." */
    fun spokenSummary(beds: List<Bed>): String {
        if (beds.isEmpty()) return "Today’s ward round: no patients waiting."
        val about = aboutMinutes(minutes(beds)).lowercase()
        return "Today’s ward round: " + counted(beds.size, "patient") + ", " + about + "."
    }

    /** "About 1 minute", "About 12 minutes". */
    fun aboutMinutes(minutes: Int): String = "About ${counted(maxOf(1, minutes), "minute")}"

    /** Whole minutes, rounded up, never under one. */
    fun minutes(seconds: Int): Int = maxOf(1, (maxOf(0, seconds) + 59) / 60)

    /** "1 card", "12 cards". */
    fun counted(n: Int, noun: String): String = "$n $noun${if (n == 1) "" else "s"}"
}
