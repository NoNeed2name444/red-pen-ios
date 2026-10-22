package com.stethoscore.app.data

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

// A port of ios/RedPen/Shared/Learn/BedPlan.swift (today's ward
// round on the home screen) and Shared/Learn/ExamWeekPlanner.swift (the
// phase from the exam date, the one most useful session, and the exam-day
// kit's pacing). Pure Kotlin (BedPlanTest, LearnTest).
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
        data class Building(val left: Int) : Phase()
        data class MockWindow(val left: Int) : Phase()
        data class ExamWeek(val left: Int) : Phase()
        object ExamDay : Phase()
        object After : Phase()

        /** Whether new material should be held back. */
        val holdsNewMaterial: Boolean get() = this is ExamWeek || this == ExamDay

        /** Days left, when there is a date still to come. */
        val days: Int? get() = when (this) {
            is Building -> left
            is MockWindow -> left
            is ExamWeek -> left
            ExamDay -> 0
            NoDate, After -> null
        }

        /** Whether this is the window for a full mock. */
        val isMockWindow: Boolean get() = this is MockWindow

        val headline: String get() = when (this) {
            NoDate -> "No exam date set"
            is Building -> "Learn and keep"
            is MockWindow -> "Mock week"
            is ExamWeek -> "Exam week — nothing new"
            ExamDay -> "Exam day"
            After -> "Exam done"
        }

        /** One line of advice for the phase. */
        val advice: String get() = when (this) {
            NoDate -> "Set your exam date and the plan works back from it."
            is Building -> "New material, then reviews as they fall due. Aim to lock each question in on three separate days."
            is MockWindow -> "Sit one full mock under exam timing now. What it shows is what the last week is for."
            is ExamWeek -> "No new topics. Your mistakes, your confident errors and the rule sheet, then sleep — sleep beats cramming."
            ExamDay -> "Nothing to learn today. Eat, check the kit, pace yourself, flag and move on."
            After -> "Your exam date has passed. Set the next one when you know it."
        }

        override fun toString(): String = when (this) {
            NoDate -> "noDate"
            is Building -> "building(days: $left)"
            is MockWindow -> "mockWindow(days: $left)"
            is ExamWeek -> "examWeek(days: $left)"
            ExamDay -> "examDay"
            After -> "after"
        }
    }

    /** What is waiting, as counts, for choosing the session. */
    data class Situation(
        val phase: Phase,
        val dueCards: Int = 0,
        /** Questions got wrong while sure. */
        val confidentErrors: Int = 0,
        /** Questions whose last answer was wrong. */
        val missed: Int = 0,
        val flagged: Int = 0,
        /** Questions right on one or two days, not yet three. */
        val closeToSecure: Int = 0,
        /** Questions never answered. */
        val untried: Int = 0,
        /** Items from yesterday's misses still to re-ask this morning. */
        val morningCheck: Int = 0,
        /** Whether a mock has been sat in the mock window. */
        val mockDone: Boolean = false,
        /** The weakest subject, when there is one. */
        val weakestSubject: String? = null,
    )

    /** The session the lift-off button starts. */
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

        val title: String get() = when (this) {
            ExamKit -> "Open your exam-day kit"
            is MorningCheck -> "Morning check · $n from yesterday"
            is DueCards -> "Study $n due card${if (n == 1) "" else "s"}"
            Mock -> "Sit a mock paper"
            is ConfidentErrors -> "Fix $n confident error${if (n == 1) "" else "s"}"
            is Mistakes -> "Redo $n missed question${if (n == 1) "" else "s"}"
            is LockIn -> "Lock in $n question${if (n == 1) "" else "s"}"
            is Flagged -> "Practise $n flagged question${if (n == 1) "" else "s"}"
            is Weakest -> "Drill $subject"
            NewQuestions -> "Try new questions"
            Nothing -> "All done for now"
        }

        override fun toString(): String = when (this) {
            ExamKit -> "examKit"
            is MorningCheck -> "morningCheck($n)"
            is DueCards -> "dueCards($n)"
            Mock -> "mock"
            is ConfidentErrors -> "confidentErrors($n)"
            is Mistakes -> "mistakes($n)"
            is LockIn -> "lockIn($n)"
            is Flagged -> "flagged($n)"
            is Weakest -> "weakest(\"$subject\")"
            NewQuestions -> "newQuestions"
            Nothing -> "nothing"
        }
    }

    /**
     * The most useful session now.
     *
     * Always first: the exam-day kit on the day, and a morning check of
     * yesterday's misses (two minutes, before anything new). Cards due come
     * next in every phase, because the schedule only works if they are done
     * on the day. After that the phase decides: the mock in its window;
     * confident errors, mistakes and the half-secured in exam week; and far
     * out, locking in, then the weakest subject, then something new.
     */
    fun mission(s: Situation): Mission {
        if (s.phase == Phase.ExamDay) return Mission.ExamKit
        if (s.morningCheck > 0) return Mission.MorningCheck(s.morningCheck)
        if (s.dueCards > 0) return Mission.DueCards(s.dueCards)
        when (val phase = s.phase) {
            is Phase.MockWindow -> if (!s.mockDone) return Mission.Mock
            is Phase.ExamWeek -> {
                // a mock missed in its window can still be sat at T-7
                if (phase.days == 7 && !s.mockDone) return Mission.Mock
                if (s.confidentErrors > 0) return Mission.ConfidentErrors(s.confidentErrors)
                if (s.missed > 0) return Mission.Mistakes(s.missed)
                if (s.closeToSecure > 0) return Mission.LockIn(s.closeToSecure)
                if (s.flagged > 0) return Mission.Flagged(s.flagged)
                // no new material this week, so nothing else to offer
                return Mission.Nothing
            }
            else -> {}
        }
        if (s.confidentErrors > 0) return Mission.ConfidentErrors(s.confidentErrors)
        if (s.closeToSecure > 0) return Mission.LockIn(s.closeToSecure)
        if (s.flagged > 0) return Mission.Flagged(s.flagged)
        s.weakestSubject?.let { return Mission.Weakest(it) }
        if (s.untried > 0) return Mission.NewQuestions
        return Mission.Nothing
    }

    // MARK: the exam-day kit

    /** One pacing checkpoint: be at question [question] by [minute]. */
    data class Checkpoint(val minute: Int, val question: Int)

    /** The paper the kit paces, for a track. [published]: the exam's own format rather than a pace from ExamTrack. */
    data class Paper(val name: String, val questions: Int, val minutes: Int, val published: Boolean)

    /**
     * The paper for each track. PLAB 1 is 180 questions in three hours; an
     * MRCP(UK) Part 1 paper is 100 in three hours; a USMLE block is up to 40
     * in an hour. MRCS Part A's papers have changed format more than once,
     * so it (and general revision) gets an hour-long pace from the track's
     * seconds per question and the kit says to check the count.
     */
    fun paper(track: com.stethoscore.app.quiz.ExamTrack): Paper = when (track) {
        com.stethoscore.app.quiz.ExamTrack.plab -> Paper("PLAB 1", 180, 180, true)
        com.stethoscore.app.quiz.ExamTrack.mrcp -> Paper("MRCP(UK) Part 1 paper", 100, 180, true)
        com.stethoscore.app.quiz.ExamTrack.usmle -> Paper("USMLE block", 40, 60, true)
        com.stethoscore.app.quiz.ExamTrack.mrcs, com.stethoscore.app.quiz.ExamTrack.general -> {
            val perHour = maxOf(1, 3600 / maxOf(1, track.secondsPerQuestion))
            Paper("An hour of questions", perHour, 60, false)
        }
    }

    /**
     * Where to be as time passes: each hour for a long paper, each quarter
     * of it for a paper of an hour or less. The last checkpoint is the end.
     */
    fun checkpoints(paper: Paper): List<Checkpoint> {
        if (paper.minutes <= 0 || paper.questions <= 0) return emptyList()
        val step = if (paper.minutes > 60) 60 else maxOf(1, paper.minutes / 4)
        val out = mutableListOf<Checkpoint>()
        var minute = step
        while (minute <= paper.minutes) {
            val share = minute.toDouble() / paper.minutes
            // Swift's rounded(): to nearest, half away from zero
            val q = Math.round(share * paper.questions).toInt()
            out.add(Checkpoint(minute, minOf(paper.questions, maxOf(1, q))))
            minute += step
        }
        if (out.lastOrNull()?.minute != paper.minutes) out.add(Checkpoint(paper.minutes, paper.questions))
        return out
    }

    /** "1:00" for 60 minutes. */
    fun clock(minutes: Int): String = String.format(java.util.Locale.ROOT, "%d:%02d", minutes / 60, minutes % 60)

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
     * The Vitals screen's line under its weak spots: what today's round does
     * about them, said only as far as [beds] makes it true (the weakest spot
     * has a bed on every round but exam day's; BedPlanTest checks the
     * sentence against the round).
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
