package com.stethoscore.app.ui.vitals

import com.stethoscore.app.data.BedPlan
import com.stethoscore.app.coverage.CoverageStatus
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.ReadinessEstimate
import com.stethoscore.app.data.ReasonShare
import com.stethoscore.app.data.RuleGroup
import com.stethoscore.app.data.RuleWriter
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.coverage.SubtopicCoverage
import com.stethoscore.app.coverage.SyllabusSubtopic
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MistakeReason
import com.stethoscore.app.ui.coverage.CoverageWords
import com.stethoscore.app.ui.ward.checks
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.LocalDate

// The words and sums on the Vitals, rule sheet and Syllabus screens
// (AnalyticsView, InsightViews, RuleSheetView, CoverageView), checked on the
// JVM: what each line says, how Focus next ranks, and where the range bar
// puts its pieces. iOS keeps these inside its views, untested; the strings
// here are copied from them.
class VitalsWordsTest {
    @get:Rule val folder = TemporaryFolder()

    private fun estimate(low: Double, center: Double, high: Double, levers: List<ReadinessEstimate.Lever> = emptyList(),
                         coverage: Double = 0.0, review: Double = 0.0, thin: List<String> = emptyList(), due: Int = 0) =
        ReadinessEstimate(center, low, high, 120, center, coverage, review, thin, due, 0.6, levers)

    private fun snapshot(stats: List<BedPlan.Topic> = emptyList(), due: Int = 0, confident: Int = 0, shares: List<ReasonShare> = emptyList()) =
        VitalsSnapshot(stats, due, confident, shares, emptyList(), emptyList(), emptyList(), emptyMap(), 0, null, 0, 0, emptyMap(), 0,
            emptyMap(), emptyList(), 0, false, 0, emptySet())

    @Test fun theReadinessCard() = checks {
        check("above the mark", readinessVerdict(estimate(0.62, 0.68, 0.74)) == "Likely above the pass mark")
        check("below the mark", readinessVerdict(estimate(0.40, 0.48, 0.55)) == "Below the pass mark for now")
        check("across the mark", readinessVerdict(estimate(0.55, 0.60, 0.66)) == "Around the pass mark")
        check("the basis says it is an estimate",
            readinessBasis(estimate(0.5, 0.6, 0.7)) == "An estimate, not a prediction: your last 120 answers, the latest counting most.")
        check("and what was taken off",
            readinessBasis(estimate(0.5, 0.6, 0.7, coverage = 0.03, review = 0.01, thin = listOf("Renal"), due = 20)) ==
                "An estimate, not a prediction: your last 120 answers, the latest counting most. 3 off for 1 subject with under 10 answers. 1 off for 20 cards waiting for review.")
        check("a lever not tried", leverLine(ReadinessEstimate.Lever("Renal", 0.18, null, 0.1)) == "18% of your questions · not tried yet")
        check("a lever tried", leverLine(ReadinessEstimate.Lever("Renal", 0.18, 0.52, 0.1)) == "18% of your questions · 52% right")
        check("the pass line names the exam", passLine(estimate(0.5, 0.6, 0.7), ExamTrack.plab) == "Typical pass mark for PLAB: 60% · approximate")
        check("but not for general revision", passLine(estimate(0.5, 0.6, 0.7), ExamTrack.general) == "Typical pass mark: 60% · approximate")
        check("the monitor shows a dash with nothing to show", monitorPercent(null) == "–" && monitorPercent(0.684) == "68%")
    }

    @Test fun theRangeBar() = checks {
        val bar = RangeBarLayout.of(200.0, 0.5, 0.6, 0.7, 0.6)
        check("the range runs low to high", bar.rangeX == 100.0 && Math.abs(bar.rangeWidth - 40.0) < 1e-9, "$bar")
        check("the dot is centred on the middle", Math.abs(bar.centerX - 114.0) < 1e-9 && Math.abs(bar.markX - 119.0) < 1e-9, "$bar")
        val edge = RangeBarLayout.of(200.0, 0.99, 1.0, 1.0, 0.0)
        check("nothing runs off the end", edge.rangeWidth == 8.0 && edge.rangeX == 192.0 && edge.centerX == 188.0 && edge.markX == 0.0, "$edge")
    }

    @Test fun focusNext() = checks {
        check("nothing to do, nothing listed", VitalsNumbers.focusItems(snapshot(), null).isEmpty())
        val stats = listOf(BedPlan.Topic("Renal", 40, 20, 6), BedPlan.Topic("Neuro", 40, 10, 6), BedPlan.Topic("Cardio", 40, 4, 0),
            BedPlan.Topic("Resp", 40, 30, 21))
        val gaps = CoverageGaps(missing = 10, total = 40, first = "Headache", covered = 20, thin = 10, track = ExamTrack.plab)
        val items = VitalsNumbers.focusItems(snapshot(stats, due = 30, confident = 3,
            shares = listOf(ReasonShare(MistakeReason.misread, 4, 0.5))), gaps)
        check("five at most, best first", items.size == 5 && items.zipWithNext().all { (a, b) -> a.score >= b.score }, "${items.map { it.id }}")
        check("the weakest subject, trusted from twenty answers, leads", items[0].id == "drill-Renal" && items[0].score == 70.0, "${items[0]}")
        check("a drill says why", items[0].detail == "30% right in Renal over 20 answers", items[0].detail)
        check("under five answers is not drilled", items.none { it.id == "drill-Cardio" })
        check("confident mistakes: 40 and 5 a question", items.first { it.id == "confident" }.score == 55.0)
        check("cards waiting: 15 and 1 a card", items.first { it.id == "due" }.detail == "30 cards waiting for review")
        val all = VitalsNumbers.focusItems(snapshot(stats, due = 30, confident = 3, shares = listOf(ReasonShare(MistakeReason.misread, 4, 0.5))),
            gaps.copy(missing = 40, covered = 0, thin = 0))
        check("the gaps name the exam and an example",
            all.first { it.id == "gaps" }.detail == "40 of 40 PLAB topics have nothing in your library, such as Headache")
        val reason = VitalsNumbers.focusItems(snapshot(shares = listOf(ReasonShare(MistakeReason.misread, 4, 0.5))), null).single()
        check("the commonest reason, trusted from five", reason.title == "Slow reading drill" && reason.score == 40.0
            && reason.detail == "${MistakeReason.misread.title}: 50% of the reasons you gave, last 30 days", "$reason")
        check("one reason given is not enough", VitalsNumbers.focusItems(snapshot(shares = listOf(ReasonShare(MistakeReason.misread, 1, 1.0))), null).isEmpty())
    }

    @Test fun theRingsAndTime() = checks {
        check("the syllabus ring waits for its check", VitalsNumbers.syllabusShare(null) == null && VitalsNumbers.syllabusSpoken(null) == "still checking")
        val gaps = CoverageGaps(5, 20, null, 10, 5, ExamTrack.general)
        check("then reads the share covered", VitalsNumbers.syllabusShare(gaps) == 0.5
            && VitalsNumbers.syllabusSpoken(gaps) == "10 topics covered, 5 thin, 5 missing, of 20")
        check("the target without a date", VitalsNumbers.ringsNote(false).endsWith("Today’s target is 30 until you set an exam date."))
        val today = LocalDate.of(2026, 9, 24)
        check("the average is over the days studied",
            VitalsNumbers.dailyAverage(listOf(DayPoint(today, 0), DayPoint(today, 3), DayPoint(today, 4))) == 4)
        check("and a dash with none", VitalsNumbers.dailyAverage(listOf(DayPoint(today, 0))) == null)
        val store = StudyStore(folder.root)
        check("no exam date: thirty a day", VitalsNumbers.dailyTarget(store) == (30 to false))
    }

    @Test fun theRuleSheet() = checks {
        val q1 = MCQQuestion(stem = "Which nerve supplies the thenar muscles?", options = listOf("Median"), correctIndex = 0)
        val q2 = MCQQuestion(stem = "First-line drug for gout?", options = listOf("Colchicine"), correctIndex = 0)
        val groups = listOf(RuleGroup("Anatomy", listOf(RuleWriter.plainRule(q1, "Anatomy"))),
            RuleGroup("Rheumatology", listOf(RuleWriter.plainRule(q2, "Rheumatology"))))
        check("no search, everything", filterRuleGroups(groups, "  ") == groups)
        check("a word finds its rule", filterRuleGroups(groups, "COLCHICINE").map { it.subject } == listOf("Rheumatology"))
        check("a subject keeps all its rules", filterRuleGroups(groups, "anat").single().rules.size == 1)
        check("nothing matches, nothing shown", filterRuleGroups(groups, "aspirin").isEmpty())

        val store = StudyStore(folder.root)
        val set = StudySet(name = "Mixed", subject = "Anatomy", kind = StudySetKind.MCQ, questions = listOf(q1, q2))
        store.addSet(set)
        store.recordAnswer(q1.id, false)
        store.recordAnswer(q2.id, true)
        store.noteMistake(MistakeReason.misread.rawValue, q1.id)
        check("only the questions last got wrong want a rule", StoreInsight.missedWithoutRules(store).map { it.question.id } == listOf(q1.id))
        check("adding them says how many", StoreInsight.addRulesForMissed(store) == 1 && StoreInsight.missedWithoutRules(store).isEmpty())
        check("the shared sheet groups by subject",
            StoreInsight.ruleSheetText(store.ruleSheet) == "Rule sheet\n\nANATOMY\n• Which nerve supplies the thenar muscles? → Median\n")
        check("the reasons given, as shares", StoreInsight.reasonShares(store) == listOf(ReasonShare(MistakeReason.misread, 1, 1.0)))
        check("and the questions behind them", StoreInsight.picks(store, MistakeReason.misread).map { it.question.id } == listOf(q1.id))
    }

    @Test fun theSyllabusScreen() = checks {
        fun sub(evidence: Int, practice: Int, answered: Int, correct: Int) =
            SubtopicCoverage("Area", SyllabusSubtopic("Sub", listOf("sub")), evidence, practice, answered, correct, emptyList(), CoverageStatus.thin)
        check("nothing found", CoverageWords.detail(sub(0, 0, 0, 0)) == "Nothing in your library mentions it")
        check("reading only", CoverageWords.detail(sub(1, 0, 0, 0)) == "1 item · no questions or cards")
        check("practice and answers", CoverageWords.detail(sub(12, 3, 7, 4)) == "12 items · 3 to practise · 57% right of 7")
        check("the exam menu's short name", CoverageWords.shortName(ExamTrack.general) == "General" && CoverageWords.shortName(ExamTrack.mrcs) == "MRCS")
        check("gaps only hides the covered", !CoverageWords.passes(CoverageStatus.covered, null, true) && CoverageWords.passes(CoverageStatus.thin, null, true))
        check("a picked count shows only its own", CoverageWords.passes(CoverageStatus.covered, CoverageStatus.covered, true)
            && !CoverageWords.passes(CoverageStatus.thin, CoverageStatus.covered, false))
    }
}
