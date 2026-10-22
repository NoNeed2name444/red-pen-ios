package com.stethoscore.app.data

import com.stethoscore.app.data.ExamWeekPlanner.Mission
import com.stethoscore.app.data.ExamWeekPlanner.Phase
import com.stethoscore.app.ui.ward.checks
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID

// A port of ios/RedPen/Tests/BedPlanTests.swift, case for case:
// today's revision and the Progress screen's readings - which items the
// plan holds and in what order, the weak topics (and that the weakest of
// them always has a place, which is what the Progress screen promises), the
// minutes, the study rhythm read from the days studied, and the words
// around the numbers.
class BedPlanTest {
    private val zone: ZoneId = ZoneId.of("Europe/London")
    private val day = 86_400_000L
    private val now: Instant = ZonedDateTime.of(2026, 9, 24, 12, 0, 0, 0, zone).toInstant()
    private val nowMs = now.toEpochMilli()

    private fun topic(name: String, correct: Int, of: Int, questions: Int = 40) = BedPlan.Topic(name, questions, of, correct)
    private fun fresh(name: String, mode: BedPlan.Mode = BedPlan.Mode.questions, items: Int = 42, daysAgo: Double = 1.0, subject: String = "Renal") =
        BedPlan.FreshSet(UUID.randomUUID().toString(), name, subject, mode, items, nowMs - (daysAgo * day).toLong())
    private fun station(title: String, resumes: Boolean = false, daysAgo: Double = 1.0) =
        BedPlan.Station(UUID.randomUUID().toString(), title, resumes, nowMs - (daysAgo * day).toLong())
    private fun kinds(beds: List<BedPlan.Bed>): List<String> = beds.map {
        when (it.kind) {
            is BedPlan.Kind.Priority -> "priority"
            is BedPlan.Kind.DueCards -> "due"
            is BedPlan.Kind.Weakest -> "weakest"
            is BedPlan.Kind.Fresh -> "fresh"
            is BedPlan.Kind.OsceStation -> "station"
        }
    }

    private val topics = listOf(
        topic("Cardiology", 30, of = 40),      // 75%: not below the line
        topic("Renal", 12, of = 25),           // 48%
        topic("Endocrine", 2, of = 4),         // 50% but only 4 answers
        topic("Neurology", 13, of = 25),       // 52%
        topic("Haematology", 0, of = 0),       // never tried
    )
    private val spots = BedPlan.weakSpots(topics)

    private val full = BedPlan.Input(
        phase = Phase.Building(30), mission = Mission.DueCards(12), dueCards = 12, dueFrom = listOf("Cardiology"),
        topics = topics, fresh = listOf(fresh("Nephrotic syndrome")), stations = listOf(station("CVS examination")),
        secondsPerQuestion = 75, stationMinutes = 8,
    )

    @Test fun weakSpots() = checks {
        check("weak spots: tried five times or more and under 75%, weakest first",
            spots.map { it.name } == listOf("Renal", "Neurology"), "${spots.map { it.name }}")
        check("exactly 75% does not need a consult", spots.none { it.name == "Cardiology" })
        check("four answers are not enough to judge", spots.none { it.name == "Endocrine" })
        check("a subject never tried is not a weak spot", spots.none { it.name == "Haematology" })
        check("a tie in accuracy goes to the one with more answers",
            BedPlan.weakSpots(listOf(topic("A", 5, of = 10), topic("B", 10, of = 20))).map { it.name } == listOf("B", "A"))
        check("percent is rounded", topic("x", 12, of = 25).percent == 48 && topic("y", 2, of = 3).percent == 67)
    }

    @Test fun theRound() = checks {
        val round = BedPlan.beds(full)
        check("the round: cards due, weakest, a new set, a station",
            kinds(round) == listOf("due", "weakest", "fresh", "station"), "${kinds(round)}")
        check("beds are numbered from one", round.map { it.number } == listOf(1, 2, 3, 4))
        check("bed 1 is overlined with the one subject the due cards come from",
            round[0].overline == "1 · Cardiology", round[0].overline)
        check("and says how many are due", round[0].title == "12 cards due" && round[0].status == BedPlan.Status.due)
        check("the weakest topic is the first weak spot",
            round[1].ward == "Renal" && round[1].title == "Weakest topic · 48%" && round[1].status == BedPlan.Status.weak, "${round[1]}")
        check("its drill is twenty MCQs", round[1].detail == "20 MCQs, missed ones first", round[1].detail)
        check("the new set is New, with its kind and size",
            round[2].title == "Nephrotic syndrome" && round[2].detail == "MCQ · 42 questions · not started"
                && round[2].status == BedPlan.Status.new, round[2].detail)
        check("the station is timed at the exam's station length, with no chip",
            round[3].ward == "OSCE station" && round[3].detail == "8 min timed" && round[3].status == null)
        check("minutes: 12 cards at 10 s is 2, 20 MCQs at 75 s is 25, 20 of a new set 25, a station 8",
            round.map { it.minutes } == listOf(2, 25, 25, 8), "${round.map { it.minutes }}")
        check("the summary counts what is to do and adds the minutes",
            BedPlan.summary(round) == "4 to do · 60 min", BedPlan.summary(round))
        check("one is 1 to do", BedPlan.summary(listOf(round[3])) == "1 to do · 8 min")
        check("an empty round says so", BedPlan.summary(emptyList()) == "Nothing due")
        check("VoiceOver hears the heading without separators",
            BedPlan.spokenSummary(round) == "Today’s revision: 4 to do, about 60 minutes.", BedPlan.spokenSummary(round))
        check("and an empty round in words", BedPlan.spokenSummary(emptyList()) == "Today’s revision: nothing due.")
        check("each bed has its own id", round.map { it.id }.toSet().size == round.size)
        check("VoiceOver hears the bed whole",
            round[0].spoken == "Item 1, Cardiology. 12 cards due. Spaced review. About 2 minutes. Due", round[0].spoken)

        // the planner's priority goes first, and pushes the station off a full round
        val morningRound = BedPlan.beds(full.copy(mission = Mission.MorningCheck(3)))
        check("the morning check takes bed 1", kinds(morningRound) == listOf("priority", "due", "weakest", "fresh"), "${kinds(morningRound)}")
        check("never more than four beds", morningRound.size == BedPlan.most)
        check("the morning check is three questions from yesterday",
            morningRound[0].title == "3 questions from yesterday" && morningRound[0].ward == "Morning check")
    }

    @Test fun priorities() = checks {
        // missions another bed already holds are not doubled
        for (mission in listOf(Mission.DueCards(12), Mission.Weakest("Renal"), Mission.NewQuestions, Mission.Nothing)) {
            check("no priority bed for $mission", BedPlan.priority(mission) == null)
        }
        for (mission in listOf(Mission.ExamKit, Mission.MorningCheck(1), Mission.Mock, Mission.ConfidentErrors(2), Mission.Mistakes(3),
            Mission.LockIn(4), Mission.Flagged(5))) {
            check("a priority bed for $mission", BedPlan.priority(mission) == mission)
        }
    }

    @Test fun decksSetsAndStations() = checks {
        // several decks
        val spreadDue = BedPlan.beds(full.copy(dueFrom = listOf("Cardiology", "Renal", "Respiratory")))[0]
        check("due cards from several subjects", spreadDue.ward == "Spaced review" && spreadDue.detail == "From 3 subjects", "$spreadDue")
        check("one card is singular", BedPlan.bed(BedPlan.Kind.DueCards(1), 1, full).title == "1 card due")

        // the newest unstarted set, and nothing new in exam week
        val older = fresh("Older set", daysAgo = 5.0)
        val newer = fresh("Newer set", daysAgo = 1.0)
        val picked = BedPlan.beds(full.copy(fresh = listOf(older, newer))).firstOrNull { it.kind is BedPlan.Kind.Fresh }
        check("the newest unstarted set takes the bed", picked?.title == "Newer set", picked?.title ?: "none")
        check("an empty set never takes a bed", BedPlan.newest(listOf(fresh("Empty", items = 0))) == null)
        val weekRound = BedPlan.beds(full.copy(phase = Phase.ExamWeek(5), mission = Mission.ConfidentErrors(2)))
        check("exam week: no new set", "fresh" !in kinds(weekRound), "${kinds(weekRound)}")
        check("exam week: the confident errors first, then due, weakest, station",
            kinds(weekRound) == listOf("priority", "due", "weakest", "station"), "${kinds(weekRound)}")
        val dayRound = BedPlan.beds(full.copy(phase = Phase.ExamDay, mission = Mission.ExamKit))
        check("exam day: the kit and nothing else", kinds(dayRound) == listOf("priority") && dayRound[0].title == "Your exam-day kit")

        // new questions when the planner wants them and no set is new
        val untried = BedPlan.Input(mission = Mission.NewQuestions, untried = 37)
        val untriedRound = BedPlan.beds(untried)
        check("new questions take a bed when no set is new",
            untriedRound.size == 1 && untriedRound[0].title == "37 not tried yet" && untriedRound[0].status == BedPlan.Status.new, "$untriedRound")
        check("but a new set is the better bed", kinds(BedPlan.beds(untried.copy(fresh = listOf(fresh("Brand new"))))) == listOf("fresh"))

        // the planner's own weakest subject, when no subject is judged yet
        val earlyRound = BedPlan.beds(BedPlan.Input(mission = Mission.Weakest("Renal"), topics = listOf(topic("Renal", 1, of = 3, questions = 8))))
        check("the planner's weakest subject still gets its bed",
            earlyRound.size == 1 && earlyRound[0].ward == "Renal" && earlyRound[0].detail == "8 MCQs, missed ones first", "$earlyRound")

        // stations: one part way through first
        val resumed = station("Abdominal exam", resumes = true, daysAgo = 9.0)
        val newestStation = station("Breaking bad news", daysAgo = 1.0)
        check("a station part way through comes before a newer one", BedPlan.station(listOf(newestStation, resumed))?.title == "Abdominal exam")
        check("and says it carries on",
            BedPlan.beds(BedPlan.Input(stations = listOf(resumed)))[0].detail == "8 min timed · carry on where you left off")

        // the weakest topic named by Vitals is always on the round
        for (mission in listOf(Mission.MorningCheck(2), Mission.LockIn(4), Mission.Flagged(1), Mission.Mock, Mission.Mistakes(9))) {
            val input = full.copy(mission = mission)
            val weakestBed = BedPlan.beds(input).firstOrNull { it.kind is BedPlan.Kind.Weakest }
            check("weakest stays on a full round ($mission)", weakestBed?.ward == BedPlan.weakSpots(input.topics).firstOrNull()?.name)
        }

        // a quiet library: no beds
        check("nothing waiting, no beds", BedPlan.beds(BedPlan.Input()).isEmpty())
    }

    @Test fun theConsultLine() = checks {
        // the Vitals screen's consult line says only what the round does
        for (phase in listOf(Phase.NoDate, Phase.Building(40), Phase.MockWindow(9), Phase.ExamWeek(3), Phase.ExamDay, Phase.After)) {
            val input = full.copy(phase = phase, mission = if (phase == Phase.ExamDay) Mission.ExamKit else Mission.LockIn(3))
            val spotsNow = BedPlan.weakSpots(input.topics)
            val note = BedPlan.consultNote(spotsNow, phase, anyJudged = true)
            val named = note.startsWith(spotsNow[0].name + ", the weakest, is in today")
            val onRound = BedPlan.beds(input).any { (it.kind as? BedPlan.Kind.Weakest)?.topic?.name == spotsNow[0].name }
            check("the consult line names the weakest only when the round holds it ($phase)", named == onRound, "$note / on round: $onRound")
        }
        check("the consult line on exam day says why they wait",
            BedPlan.consultNote(spots, Phase.ExamDay, anyJudged = true).startsWith("Exam day"))
        check("the consult line names the weakest",
            BedPlan.consultNote(spots, Phase.Building(20), anyJudged = true) == "Renal, the weakest, is in today’s revision automatically.")
        check("no weak spot, but subjects judged",
            BedPlan.consultNote(emptyList(), Phase.NoDate, anyJudged = true)
                == "No weak topics: every topic with 5 or more answers is at 75% or better.")
        check("no subject judged yet",
            BedPlan.consultNote(emptyList(), Phase.NoDate, anyJudged = false) == "A subject shows here once it has 5 answers and is under 75%.")
    }

    @Test fun minutes() = checks {
        check("minutes round up", BedPlan.minutes(seconds = 61) == 2 && BedPlan.minutes(seconds = 60) == 1)
        check("and never fall under one", BedPlan.minutes(seconds = 0) == 1)
        check("a textbook's first sitting is three pages",
            BedPlan.firstSittingMinutes(fresh("Book", BedPlan.Mode.textbook, items = 40), secondsPerQuestion = 75) == 9)
        check("a deck's first sitting is twenty cards",
            BedPlan.firstSittingMinutes(fresh("Deck", BedPlan.Mode.cards, items = 200), secondsPerQuestion = 75) == 4)
        check("about one minute is singular", BedPlan.aboutMinutes(1) == "About 1 minute")
    }

    private fun days(offsets: List<Int>, from: Instant = now): Map<String, Int> =
        offsets.associate { RhythmReading.key(from.atZone(zone).toLocalDate().minusDays(it.toLong())) to 5 }

    private fun read(days: Map<String, Int>) = RhythmReading.read(days, now, zone)

    @Test fun theStudyRhythm() = checks {
        check("the key is StudyLog's yyyy-MM-dd", RhythmReading.key(now, zone) == "2026-09-24", RhythmReading.key(now, zone))

        val none = read(emptyMap())
        check("no history: no trace yet", none.rhythm == RhythmReading.Rhythm.noTrace && none.words == "No trace yet")
        check("a strip is always fourteen days", none.beats.size == RhythmReading.window)
        check("zero counts are no history", read(mapOf("2026-09-23" to 0)).rhythm == RhythmReading.Rhythm.noTrace)

        val steady = read(days((0 until 14).filter { it % 7 != 3 }))
        check("most days, short gaps: regular", steady.rhythm == RhythmReading.Rhythm.regular && steady.words == "Sinus · regular",
            "${steady.rhythm} ${steady.activeDays}/${steady.span}")
        check("its line counts the days", steady.line == "Studied 12 of the last 14 days.", steady.line)
        check("today is the last beat", steady.beats.last())

        val patchy = read(days(listOf(0, 4, 5, 9, 13)))
        check("some days with long gaps: irregular", patchy.rhythm == RhythmReading.Rhythm.irregular, "${patchy.rhythm}")

        val gappy = read(days((0 until 14).filter { it !in listOf(4, 5, 6) }))
        check("three days off in a row is not regular, however many days", gappy.rhythm == RhythmReading.Rhythm.irregular, "${gappy.rhythm}")

        val away = read(days(listOf(8, 9, 10, 11, 12, 13)))
        check("a week with nothing: resting", away.rhythm == RhythmReading.Rhythm.resting && away.line.startsWith("Nothing in the last 7 days"),
            "${away.rhythm}")
        val long = read(days(listOf(40)))
        check("studying long ago and not since: resting, not no trace", long.rhythm == RhythmReading.Rhythm.resting)

        // the day is not over: nothing yet today does not count against the strip
        val breakfast = read(days((1 until 14).toList()))
        check("nothing yet today: the strip ends yesterday, still regular",
            breakfast.rhythm == RhythmReading.Rhythm.regular && breakfast.beats.last(), "${breakfast.rhythm}")

        // a new student is read over the days since starting
        val newcomer = read(days(listOf(0, 1, 2)))
        check("three days in, three days studied: regular over three days",
            newcomer.rhythm == RhythmReading.Rhythm.regular && newcomer.span == 3 && newcomer.line == "Studied 3 of the last 3 days.",
            "${newcomer.span} ${newcomer.line}")
        val first = read(days(listOf(0)))
        check("the first day says day, not 1 days", first.line == "Studied 1 of the last day.", first.line)
        check("VoiceOver hears the rhythm", steady.spoken.startsWith("Study rhythm, regular."), steady.spoken)

        // the study log and the dated answers, together
        val answersOn = listOf(now, now, now.minusMillis(3 * day))
        val together = RhythmReading.merged(mapOf("2026-09-24" to 1, "2026-09-20" to 4), answersOn, zone)
        check("merged: the larger count each day", together["2026-09-24"] == 2 && together["2026-09-20"] == 4, "$together")
        check("merged: a day only the answers know still counts", together["2026-09-21"] == 1, "$together")
        check("merged days read as studied", read(RhythmReading.merged(emptyMap(), listOf(now), zone)).rhythm == RhythmReading.Rhythm.regular)
        check("no word is alarming", listOf(none, steady, patchy, away).all { reading ->
            val text = (reading.words + " " + reading.line).lowercase()
            listOf("arrest", "flatline", "fail", "bad", "lazy", "danger").none { text.contains(it) }
        })
    }

    @Test fun theWords() = checks {
        check("countdown with no date: none", WardWords.countdown(null) == null)
        check("countdown after the exam: none", WardWords.countdown(-2) == null)
        check("countdown names finals by default", WardWords.countdown(23) == "Finals in 23 days")
        check("countdown names the chosen exam", WardWords.countdown(23, exam = "PLAB 1") == "PLAB 1 in 23 days")
        check("countdown tomorrow and today",
            WardWords.countdown(1) == "Finals tomorrow" && WardWords.countdown(0, exam = "Step 1") == "Step 1 today")
        check("a blank exam name is finals", WardWords.countdown(3, exam = "  ") == "Finals in 3 days")

        check("greeting by the hour", WardWords.greeting(8) == "Good morning"
            && WardWords.greeting(14) == "Good afternoon" && WardWords.greeting(21) == "Good evening"
            && WardWords.greeting(2) == "Good evening")
        check("greeting with a first name", WardWords.greeting(9, name = "Sam Patel") == "Good morning, Sam")
        check("no greeting by the stand-in name", WardWords.greeting(9, name = "Me") == "Good morning")
        check("no greeting by email", WardWords.firstName("sam@example.edu") == null)
        check("no greeting by a blank name", WardWords.firstName("  ") == null && WardWords.firstName(null) == null)

        check("standing: the whole range above the mark", WardWords.standing(0.62, 0.74, 0.6) == "on track for a pass")
        check("standing: below, for now", WardWords.standing(0.40, 0.55, 0.6) == "below the pass mark for now")
        check("standing: across the mark", WardWords.standing(0.55, 0.66, 0.6) == "around the pass mark")
        check("the vitals line joins them",
            WardWords.vitalsLine("Finals in 23 days", "on track for a pass") == "Finals in 23 days · on track for a pass")
        check("the vitals line without an estimate is the countdown",
            WardWords.vitalsLine("Finals in 23 days", null) == "Finals in 23 days")
        check("no countdown, no line", WardWords.vitalsLine(null, "on track for a pass") == null)
    }

}
