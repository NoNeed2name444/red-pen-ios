package com.stethoscore.app.data

import com.stethoscore.app.data.ExamWeekPlanner.Checkpoint
import com.stethoscore.app.data.ExamWeekPlanner.Mission
import com.stethoscore.app.data.ExamWeekPlanner.Phase
import com.stethoscore.app.data.SecuredRule.Standing
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MockRandom
import com.stethoscore.app.ui.ward.checks
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.ceil

// upstream/ios/RedPen/Tests/LearnTests.swift, case for case: the exam-day
// forecast and exam cap, "lock it in", the exam-week planner, the symptom
// classifier, the pretest writer and the daily rhythm. Dates are epoch ms
// and a calendar is a time zone (Europe/London, as there).
//
// One case reads differently: iOS checks that the exam cap reads the same
// UserDefaults key as ExamTrack. Android keeps one exam date, on StudyStore,
// and both the countdown and the cap read it, so the check here is that a
// rating made through the store is capped by the store's exam date.
class LearnTest {
    @get:Rule val folder = TemporaryFolder()

    private val zone: ZoneId = ZoneId.of("Europe/London")
    private val day: Long = 86_400_000L
    // noon on a fixed day, well away from midnight and clock changes
    private val now: Long = ZonedDateTime.of(2026, 3, 2, 12, 0, 0, 0, zone).toInstant().toEpochMilli()

    private fun id(): String = java.util.UUID.randomUUID().toString()

    @Test fun theForecast() = checks {
        check("recall is 90% exactly one stability after a review",
            abs(RetentionForecast.recall(elapsedDays = 10.0, stability = 10.0) - 0.9) < 1e-9)
        check("and falls further the longer it is left",
            RetentionForecast.recall(30.0, 10.0) < RetentionForecast.recall(20.0, 10.0))
        check("a card not seen since just now is fully recalled",
            abs(RetentionForecast.recall(0.0, 3.0) - 1) < 1e-9)

        val tenDay = ReviewRecord(due = now + 10 * day, intervalMin = 10.0 * 1440, reviews = 3, lapses = 0, ratedAt = now)
        val lapsed = ReviewRecord(due = now + 10 * day, intervalMin = 10.0 * 1440, reviews = 6, lapses = 3, ratedAt = now)
        check("lapses make a card less stable than its interval",
            RetentionForecast.stabilityDays(lapsed) < RetentionForecast.stabilityDays(tenDay))
        check("a card never rated has no recall to forecast", RetentionForecast.recall(null, now) == null)

        val a = id(); val b = id(); val c = id()
        val records = mapOf(a to tenDay, b to lapsed)
        val exam = now + 30 * day
        val f = RetentionForecast.forecast(listOf(a, b, c), records, now, exam)
        check("the forecast counts studied and unseen cards apart", f.studied == 2 && f.unseen == 1, "${f.studied} ${f.unseen}")
        check("recall on exam day is below today's", f.onExamDay < f.today, "${f.onExamDay} ${f.today}")
        check("so reviews are needed to reach 90%", f.reviewsNeeded >= 2, "${f.reviewsNeeded}")
        check("over the days left", f.days == 30, "${f.days}")
        check("and not on course yet", !f.onCourse)
        check("a per-day figure rounds up", f.perDay == ceil(f.reviewsNeeded.toDouble() / 30).toInt())

        // a card reviewed yesterday with a long interval needs nothing before an exam in three days
        val solid = ReviewRecord(due = now + 20 * day, intervalMin = 20.0 * 1440, reviews = 5, lapses = 0, ratedAt = now - day)
        check("a solid card needs no review before a near exam",
            RetentionForecast.reviewsToTarget(solid, now, now + 3 * day) == 0)
        check("a weak card needs at least one", RetentionForecast.reviewsToTarget(lapsed, now, exam) >= 1)
        val plan = RetentionForecast.reviewsToTarget(
            ReviewRecord(due = now, intervalMin = 10.0, reviews = 1, lapses = 0, ratedAt = now), now, exam)
        check("a card just learned needs a handful, not dozens", plan >= 2 && plan < RetentionForecast.maxPlanned, "$plan")
        val noExam = RetentionForecast.forecast(listOf(a), records, now, null)
        check("without an exam there is no review plan", noExam.reviewsNeeded == 0)

        val byDay = RetentionForecast.dueByDay(listOf(a, b, c), records, now, 14, zone)
        check("an unrated card is due today", byDay[0] == 1, "$byDay")
        check("and cards due in ten days land on day ten", byDay[10] == 2, "$byDay")
    }

    @Test fun theExamCap() = checks {
        // iOS: "the cap reads the same key as ExamTrack" - here, the store's one exam date (see the note above)
        val store = StudyStore(folder.root)
        val capExam = now + 12 * day
        store.setExamDate(capExam)
        val mature = ReviewRecord(due = now, intervalMin = 30.0 * 1440, reviews = 3, ratedAt = now - 30 * day)
        val viaStore = ReviewOptions.after(AnkiRating.EASY, mature, now, store.examDate, store.reviewSettings.scheduler)
        check("the cap reads the same exam date as the countdown", viaStore.due <= capExam - day,
            "${(viaStore.due - now) / day.toDouble()} d")

        val capped = ExamCap.capped(30.0 * 1440, now, capExam)
        check("an interval past the exam is brought back before it", capped <= 11.0 * 1440, "${capped / 1440} d")
        check("to about two days before", abs(capped - 10.0 * 1440) < 1, "${capped / 1440} d")
        check("an interval well before the exam is untouched", ExamCap.capped(4.0 * 1440, now, capExam) == 4.0 * 1440)
        check("learning steps under a day are untouched", ExamCap.capped(600.0, now, now + 3_600_000L * 5) == 600.0)
        check("no exam, no cap", ExamCap.capped(30.0 * 1440, now, null) == 30.0 * 1440)
        check("a past exam changes nothing", ExamCap.capped(30.0 * 1440, now, now - day) == 30.0 * 1440)
        val close = ExamCap.capped(4.0 * 1440, now, now + 2 * day)
        check("with the exam two days off, a card comes back halfway", abs(close - 1440) < 1, "$close")
        val rated = ReviewPlan.after(AnkiRating.EASY, ReviewRecord(due = now, intervalMin = 30.0 * 1440), now, capExam)
        check("a rating stores the capped interval", rated.due <= capExam - day, "${(rated.due - now) / day.toDouble()} d")
        val labels = AnkiScheduler.previewLabels(30.0 * 1440, now, capExam)
        check("and the button promises the same", labels[AnkiRating.EASY] == "in 10 d", labels[AnkiRating.EASY] ?: "nil")
    }

    private fun event(id: String, right: Boolean, daysAgo: Double, hour: Double = 0.0, hinted: Boolean? = null) =
        AnswerEvent(id, right, at = now - (daysAgo * day).toLong() + (hour * 3_600_000).toLong(), hinted = hinted)

    @Test fun lockItIn() = checks {
        val q = id()
        check("never answered is new", SecuredRule.standing(emptyList(), zone) == Standing.New)
        check("three right answers in one day are one day",
            SecuredRule.standing(listOf(event(q, true, 0.0), event(q, true, 0.0, 1.0), event(q, true, 0.0, 2.0)), zone) == Standing.Building(1))
        check("right on three separate days is secured",
            SecuredRule.standing(listOf(event(q, true, 5.0), event(q, true, 3.0), event(q, true, 1.0)), zone) == Standing.Secured)
        check("a slip after that starts again",
            SecuredRule.standing(listOf(event(q, true, 5.0), event(q, true, 3.0), event(q, true, 1.0), event(q, false, 0.0)), zone) == Standing.Building(0))
        check("a slip in between resets the count",
            SecuredRule.standing(listOf(event(q, true, 5.0), event(q, false, 4.0), event(q, true, 3.0), event(q, true, 1.0)), zone) == Standing.Building(2))
        check("events out of order are read in date order",
            SecuredRule.standing(listOf(event(q, true, 1.0), event(q, false, 4.0), event(q, true, 3.0), event(q, true, 5.0)), zone) == Standing.Building(2))
        val helped = event(q, true, 1.0, hinted = true)
        check("right with the hint is neither a day towards locking in nor a slip",
            SecuredRule.standing(listOf(event(q, true, 5.0), event(q, true, 3.0), helped), zone) == Standing.Building(2))

        val q2 = id(); val q3 = id()
        val standings = SecuredRule.standings(listOf(event(q, true, 5.0), event(q, true, 3.0), event(q, true, 1.0),
            event(q2, true, 2.0), event(q2, true, 1.0)), zone)
        val rings = SecuredRule.rings(mapOf(q to "Cardiology", q2 to "Cardiology", q3 to "Renal"), standings)
        check("rings come per subject", rings.map { it.subject } == listOf("Cardiology", "Renal"), "${rings.map { it.subject }}")
        check("with secured, building and new counted", rings[0].secured == 1 && rings[0].building == 1 && rings[1].new == 1)
        check("close to secure puts two-of-three first", SecuredRule.closeToSecure(listOf(q, q2, q3), standings) == listOf(q2))
        check("a question already right today does not count again today",
            !SecuredRule.countsToday(q, listOf(event(q, true, 0.0)), now, zone))
    }

    private fun phase(days: Int): Phase =
        ExamWeekPlanner.phase(Instant.ofEpochMilli(now + days * day), Instant.ofEpochMilli(now), zone)

    @Test fun examWeek() = checks {
        check("no date, no phase", ExamWeekPlanner.phase(null, Instant.ofEpochMilli(now), zone) == Phase.NoDate)
        check("six weeks out is building", phase(42) == Phase.Building(42))
        check("T-10 is the mock window", phase(10) == Phase.MockWindow(10))
        check("T-8 still is", phase(8) == Phase.MockWindow(8))
        check("T-7 is exam week", phase(7) == Phase.ExamWeek(7))
        check("and holds back new material", phase(3).holdsNewMaterial)
        check("the day itself", phase(0) == Phase.ExamDay)
        check("and after it", phase(-2) == Phase.After)

        fun mission(s: ExamWeekPlanner.Situation) = ExamWeekPlanner.mission(s)
        check("exam day opens the kit whatever is due",
            mission(ExamWeekPlanner.Situation(Phase.ExamDay, dueCards = 40)) == Mission.ExamKit)
        check("a morning check comes before due cards",
            mission(ExamWeekPlanner.Situation(Phase.Building(30), dueCards = 12, morningCheck = 3)) == Mission.MorningCheck(3))
        check("due cards come before anything else",
            mission(ExamWeekPlanner.Situation(Phase.Building(30), dueCards = 12, confidentErrors = 5)) == Mission.DueCards(12))
        check("the mock window suggests a mock",
            mission(ExamWeekPlanner.Situation(Phase.MockWindow(9), confidentErrors = 5)) == Mission.Mock)
        check("a mock missed in its window is still offered at T-7",
            mission(ExamWeekPlanner.Situation(Phase.ExamWeek(7), confidentErrors = 2)) == Mission.Mock)
        check("but not once it is done",
            mission(ExamWeekPlanner.Situation(Phase.ExamWeek(7), confidentErrors = 2, mockDone = true)) == Mission.ConfidentErrors(2))
        check("exam week goes to confident errors, then mistakes",
            mission(ExamWeekPlanner.Situation(Phase.ExamWeek(4), missed = 6)) == Mission.Mistakes(6))
        check("and never to new questions",
            mission(ExamWeekPlanner.Situation(Phase.ExamWeek(4), untried = 200, weakestSubject = "Renal")) == Mission.Nothing)
        check("far out, the half-secured come before the weakest subject",
            mission(ExamWeekPlanner.Situation(Phase.Building(40), closeToSecure = 8, weakestSubject = "Renal")) == Mission.LockIn(8))
        check("then the weakest subject",
            mission(ExamWeekPlanner.Situation(Phase.NoDate, weakestSubject = "Renal")) == Mission.Weakest("Renal"))

        val plab = ExamWeekPlanner.checkpoints(ExamWeekPlanner.paper(ExamTrack.plab))
        check("PLAB pacing: Q60 by 1:00, Q120 by 2:00, Q180 by 3:00",
            plab == listOf(Checkpoint(60, 60), Checkpoint(120, 120), Checkpoint(180, 180)), "$plab")
        val usmle = ExamWeekPlanner.checkpoints(ExamWeekPlanner.paper(ExamTrack.usmle))
        check("a USMLE block is paced in quarters", usmle.map { it.question } == listOf(10, 20, 30, 40), "$usmle")
        val mrcp = ExamWeekPlanner.checkpoints(ExamWeekPlanner.paper(ExamTrack.mrcp))
        check("an MRCP paper ends at Q100 at 3:00", mrcp.last() == Checkpoint(180, 100), "$mrcp")
        check("MRCS is paced but not claimed as the paper's own format", !ExamWeekPlanner.paper(ExamTrack.mrcs).published)
        check("clock reads hours and minutes", ExamWeekPlanner.clock(135) == "2:15")
    }

    private fun tags(stem: String): List<String> = SymptomBlocks.presentations(stem).map { it.id }

    /** The suite's own generator: a 64-bit LCG. */
    private class Fixed : MockRandom {
        var s: ULong = 7uL
        override fun next(): ULong {
            s = s * 6364136223846793005uL + 1442695040888963407uL
            return s
        }
    }

    @Test fun symptomBlocks() = checks {
        check("central chest pain is chest pain",
            tags("A 58-year-old man has 40 minutes of central chest pain radiating to the jaw.") == listOf("chest-pain"))
        check("denied chest pain is not", !tags("She is breathless on exertion and denies chest pain.").contains("chest-pain"))
        check("but the breathlessness in the same sentence is",
            tags("She is breathless on exertion and denies chest pain.") == listOf("breathless"))
        check("a negation in an earlier sentence does not carry over",
            tags("No fever. He has pleuritic chest pain and is short of breath.") == listOf("chest-pain", "breathless"))
        check("'but' starts a new clause",
            tags("No cough but sudden shortness of breath after a long flight.") == listOf("breathless"))
        check("a groin lump is tagged",
            tags("A 70-year-old woman has a lump in the groin below and lateral to the pubic tubercle.") == listOf("groin-lump"))
        check("words are matched whole, not inside others",
            tags("He has a headache-free interval.") == listOf("headache") && tags("Headaches for a month.") == listOf("headache"))
        check("'no' as part of another word is not a negation",
            tags("A known smoker with nocturnal chest pain.") == listOf("chest-pain"))
        check("a stem with no complaint gets no tag", tags("Which enzyme is deficient in Gaucher disease?").isEmpty())
        check("a collapsed patient is a collapse", tags("She collapsed while standing in a queue.") == listOf("collapse"))

        val items = mutableListOf<SymptomBlocks.Item>()
        listOf("Acute coronary syndrome", "Pulmonary embolism", "Aortic dissection",
            "Pericarditis", "Acute coronary syndrome", "Pneumothorax").forEachIndexed { i, answer ->
            items.add(SymptomBlocks.Item(id(), "Case $i: sudden chest pain for an hour.", answer))
        }
        items.add(SymptomBlocks.Item(id(), "A 30-year-old with a headache.", "Migraine"))
        val blocks = SymptomBlocks.blocks(items)
        check("six chest pain questions across five causes make a block",
            blocks.size == 1 && blocks[0].presentation.id == "chest-pain" && blocks[0].causes == 5,
            "${blocks.map { Triple(it.id, it.ids.size, it.causes) }}")
        check("one headache question does not", blocks.none { it.id == "headache" })
        check("but is listed when thin ones are asked for",
            SymptomBlocks.blocks(items, includeThin = true).any { it.id == "headache" })
        val sameAnswer = (0 until 6).map { SymptomBlocks.Item(id(), "Chest pain $it.", "Pericarditis") }
        check("six questions with one answer are not a block (nothing to tell apart)", SymptomBlocks.blocks(sameAnswer).isEmpty())

        val chest = items.take(6)
        val mixed = SymptomBlocks.interleaved(chest, Fixed())
        check("interleaving keeps every question", mixed.map { it.id }.toSet() == chest.map { it.id }.toSet())
        var repeats = 0
        for (i in 1 until mixed.size) if (SymptomBlocks.normalised(mixed[i].answer) == SymptomBlocks.normalised(mixed[i - 1].answer)) repeats += 1
        check("and never puts the same answer twice in a row here", repeats == 0, "${mixed.map { it.answer }}")

        val cq = id()
        val confusions = SymptomBlocks.confusions(
            mapOf(cq to SymptomBlocks.Options(listOf("ACS", "PE", "Dissection"), 2)),
            listOf(AnswerEvent(cq, false, at = now, picked = 0), AnswerEvent(cq, false, at = now, picked = 0),
                AnswerEvent(cq, true, at = now, picked = 2)))
        check("the confusion table counts what was picked against what it was",
            confusions == listOf(SymptomBlocks.Confusion("ACS", "Dissection", 2)), "$confusions")
    }

    private val chapter = """
        # Hernias

        An inguinal hernia emerges above and medial to the pubic tubercle.
        A femoral hernia emerges below and lateral to the pubic tubercle.
        A femoral hernia is more common in women and carries a high risk of strangulation.
        An indirect inguinal hernia passes through the deep ring lateral to the inferior epigastric vessels.
        A direct inguinal hernia pushes through Hesselbach's triangle medial to the inferior epigastric vessels.
        A saphena varix is a dilatation of the saphenous vein at the saphenofemoral junction and has a cough impulse.
        The saphena varix disappears when the patient lies down and may show a fluid thrill.
        Inguinal lymphadenopathy is often multiple and may follow infection in the leg or perineum.
        Lymphadenopathy in the groin should prompt examination of the lower limb, anus and genitalia.
        Strangulation of a hernia causes pain, tenderness and features of bowel obstruction.
    """.trimIndent()

    @Test fun guessFirst() = checks {
        val pre = Pretest.questions(chapter, seed = 42uL)
        check("a pretest is five questions", pre.size == 5, "${pre.size}")
        check("each with five options", pre.all { it.options.size == 5 })
        check("and one blank in its stem", pre.all { it.stem.split("_____").size == 2 }, "${pre.map { it.stem }}")
        check("the answer fills the blank back to the sentence",
            pre.all { it.explanation.lowercase().contains(it.options[it.correctIndex].lowercase()) })
        check("options are all different", pre.all { q -> q.options.map { it.lowercase() }.toSet().size == 5 })
        check("no option is already in the stem", pre.all { q ->
            q.options.withIndex().all { (i, o) -> i == q.correctIndex || !Pretest.words(q.stem).map { it.lowercase() }.contains(o.lowercase()) }
        })
        check("the same text gives the same pretest",
            Pretest.questions(chapter, seed = 42uL).map { it.stem + it.options.joinToString("") } == pre.map { it.stem + it.options.joinToString("") })
        check("too little text gives none rather than a bad one", Pretest.questions("Short note. Nothing here.").isEmpty())
        check("blanks match whole words",
            Pretest.blanked("renal", "The adrenal gland sits on the renal pole.") == "The adrenal gland sits on the _____ pole.")
        check("markdown marks are stripped", Pretest.plain("## **Bold** heading") == "Bold heading")
        check("a term said twice is blanked both times, so the stem does not give it away",
            Pretest.blanked("lupus", "Lupus nephritis is common in lupus.") == "_____ nephritis is common in _____.")
    }

    @Test fun theDailyRhythm() = checks {
        val m1 = id(); val m2 = id(); val m3 = id()
        val yesterday = now - day
        val log = listOf(
            AnswerEvent(m1, false, at = yesterday),
            AnswerEvent(m2, false, at = yesterday),
            AnswerEvent(m2, true, at = yesterday + 600_000),
            AnswerEvent(m3, false, at = yesterday + 900_000),
            AnswerEvent(m3, true, at = now - 600_000),
        )
        check("the day's misses are those last got wrong that day", StudyRhythm.missed(yesterday, log, zone) == listOf(m1, m3))
        check("the morning check leaves out what is already answered today", StudyRhythm.morningItems(now, log, zone) == listOf(m1))

        val cands = listOf(StudyRhythm.Candidate(m1, "Renal", 5), StudyRhythm.Candidate(m2, "Renal", 5),
            StudyRhythm.Candidate(m3, "Cardiology", 5), StudyRhythm.Candidate(id(), "Renal", 7))
        val pick = StudyRhythm.questionOfTheDay(cands, listOf("Renal", "Cardiology"), mapOf(m2 to Standing.Building(2)), now, zone)
        check("the question of the day comes from the weakest subject, nearest to secured", pick == m2)
        check("and is the same all day",
            StudyRhythm.questionOfTheDay(cands, listOf("Renal"), emptyMap(), now, zone) ==
                StudyRhythm.questionOfTheDay(cands, listOf("Renal"), emptyMap(), now + 3_600_000, zone))
        check("a question with more options than buttons is never chosen",
            StudyRhythm.questionOfTheDay(listOf(cands[3]), listOf("Renal"), emptyMap(), now) == null)
        check("the body lists the options by letter", StudyRhythm.questionBody("Which?", listOf("One", "Two")).contains("B  Two"))
        check("a long option is cut for its button", StudyRhythm.abbreviated("x".repeat(50)).length == 34)
        check("bedtime mentions sleep only in exam week",
            StudyRhythm.bedtimeBody(3, 5).contains("sleep") && !StudyRhythm.bedtimeBody(3, 30).contains("sleep"))
        val at = Instant.ofEpochMilli(ReminderSettings.next(22 * 60, now, zone)).atZone(zone)
        val today = Instant.ofEpochMilli(now).atZone(zone)
        check("a reminder later today is today's", at.toLocalDate() == today.toLocalDate() && at.hour == 22)
        val early = Instant.ofEpochMilli(ReminderSettings.next(7 * 60, now, zone)).atZone(zone)
        check("one already past is tomorrow's", ChronoUnit.DAYS.between(today.toLocalDate(), early.toLocalDate()) == 1L)

        // refused permission turns every reminder off (audit #37)
        val reminderDefaults = LearnDefaults.Memory()
        val keys = listOf(ReminderSettings.questionKey, ReminderSettings.bedtimeKey, ReminderSettings.morningKey)
        for (key in keys) reminderDefaults.setBool(key, true)
        ReminderSettings.refused(reminderDefaults)
        check("a refusal turns the reminders off", keys.all { !reminderDefaults.bool(it) })
    }
}
