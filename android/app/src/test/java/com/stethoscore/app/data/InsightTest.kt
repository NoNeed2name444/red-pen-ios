package com.stethoscore.app.data

import com.stethoscore.app.coverage.CoverageEngine
import com.stethoscore.app.coverage.CoverageStatus
import com.stethoscore.app.coverage.Syllabus
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.ward.checks
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import kotlin.math.abs

// The study calendar's steps, ported case for case from the HeatLevel part
// of ios/RedPen/Tests/AccessibilityTextTests.swift (the rest of
// that suite is the quiz's spoken text, another batch's). Then Android's own
// checks of the Vitals and Insight sums iOS has no suite for: the readiness
// estimate, the rule writer's plain rules, the rule sheet's keeping, the
// syllabus keyword check and the example history.
class InsightTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun theStudyCalendar() = checks {
        check("nothing done", HeatLevel.of(0, 10) == HeatLevel.none)
        check("nothing anywhere", HeatLevel.of(3, 0) == HeatLevel.none)
        check("a little", HeatLevel.of(2, 10) == HeatLevel.light)
        check("quarter is light", HeatLevel.of(25, 100) == HeatLevel.light)
        check("some", HeatLevel.of(5, 10) == HeatLevel.some)
        check("a lot", HeatLevel.of(9, 10) == HeatLevel.lots)
        check("the busiest day", HeatLevel.of(10, 10) == HeatLevel.most)
        check("over the busiest clamps", HeatLevel.of(12, 10) == HeatLevel.most)
        check("one of one is the most", HeatLevel.of(1, 1) == HeatLevel.most)
        val strengths = HeatLevel.entries.map { it.strength }
        check("strengths rise", strengths == strengths.sorted() && strengths.first() == 0.0 && strengths.last() == 1.0, "$strengths")
        val words = HeatLevel.entries.map { it.word }.toSet()
        check("every step has its own word", words.size == HeatLevel.entries.size)
    }

    @Test fun theReadinessEstimate() = checks {
        val subjects = listOf(BedPlan.Topic("Renal", 30, 40, 20), BedPlan.Topic("Cardiology", 10, 2, 1))
        check("under twenty answers, no estimate", Readiness.estimate(List(19) { true }, subjects, 0, 0.6) == null)
        val e = Readiness.estimate(List(100) { it % 4 != 0 }, subjects, 0, 0.6)!!
        check("built on the answers given", e.answers == 100 && e.passMark == 0.6)
        check("the range holds the middle", e.low <= e.center && e.center <= e.high, "${e.low} ${e.center} ${e.high}")
        check("a thin subject takes a tenth of its share off",
            abs(e.coveragePenalty - 0.10 * 10.0 / 40) < 1e-9 && e.thinSubjects == listOf("Cardiology"), "${e.coveragePenalty}")
        check("no cards waiting, nothing off for them", e.reviewPenalty == 0.0)
        val busy = Readiness.estimate(List(100) { true }, subjects, 500, 0.6)!!
        check("cards waiting take off at most five points", busy.reviewPenalty == 0.05 && busy.dueCards == 500)
        check("only the latest window is read", Readiness.estimate(List(500) { true }, subjects, 0, 0.6)!!.answers == Readiness.window)
        check("at most three levers, the biggest gain first",
            e.levers.size <= 3 && e.levers.zipWithNext().all { (a, b) -> a.weight >= b.weight }, "${e.levers}")
        val untried = Readiness.estimate(List(40) { it % 2 == 0 }, listOf(BedPlan.Topic("Renal", 10, 40, 30), BedPlan.Topic("Neuro", 10, 0, 0)), 0, 0.6)!!
        check("a subject not tried is a lever with no accuracy", untried.levers.any { it.subject == "Neuro" && it.accuracy == null })
    }

    @Test fun plainRules() = checks {
        val q = MCQQuestion(stem = "A 30-year-old has pleuritic pain. What is the most likely diagnosis?", options = listOf("STEMI", "Acute pericarditis"),
            correctIndex = 1, explanation = "Pericarditis causes widespread ST elevation. Pain eases sitting forward.")
        val rule = RuleWriter.plainRule(q, "Cardiology")
        check("the rule is the question asked, an arrow and the answer", rule.text == "What is the most likely diagnosis? → Acute pericarditis", rule.text)
        check("its detail is the explanation's first sentence", rule.detail == "Pericarditis causes widespread ST elevation.", rule.detail)
        check("one rule per question", rule.id == q.id && rule.subject == "Cardiology" && !rule.byAI)
        check("a stem that asks nothing keeps its first twelve words",
            RuleWriter.askedPart("one two three four five six seven eight nine ten eleven twelve thirteen") ==
                "one two three four five six seven eight nine ten eleven twelve…")
        check("a decimal point does not end a sentence", RuleWriter.firstSentence("Give 0.1 units/kg. Then more.") == "Give 0.1 units/kg.")
        check("a reply's rules are read past its thinking",
            RuleWriter.parse("<think>{\"rules\":[\"no\"]}</think>Here: {\"rules\": [\" A → B \", \"C → D\"]}") == listOf("A → B", "C → D"))
        check("a reply that is not the JSON asked for is nothing", RuleWriter.parse("Sorry, I can't.") == null)
        check("the prompt numbers every question", RuleWriter.prompt(listOf(rule, rule)).contains("Question 2: " + q.stem))
    }

    @Test fun theRuleSheetIsKept() = checks {
        val store = StudyStore(folder.root)
        val q = MCQQuestion(stem = "Which nerve?", options = listOf("Ulnar", "Median"), correctIndex = 1, explanation = "")
        val added = store.addRules(listOf(RuleWriter.plainRule(q, "Anatomy")))
        check("a rule is added", added == 1 && store.ruleSheet.containsKey(q.id))
        store.applyWrittenRules(mapOf(q.id to "Thenar wasting → median nerve"))
        val reopened = StudyStore(folder.root)
        val kept = reopened.ruleSheet[q.id]
        check("the sheet survives a restart, with the written line", kept?.text == "Thenar wasting → median nerve" && kept.byAI, "$kept")
        reopened.deleteRule(q.id)
        check("a deleted rule is gone for good", StudyStore(folder.root).ruleSheet.isEmpty())
    }

    @Test fun theSyllabusKeywordCheck() = checks {
        check("British and American spellings fold together",
            CoverageEngine.fold("haemorrhage") == CoverageEngine.fold("hemorrhage") && CoverageEngine.fold("tumour") == "tumor"
                && CoverageEngine.fold("centre") == "center")
        check("short words are left alone", CoverageEngine.fold("aeon") == "aeon")
        check("nothing mentions it: not covered", CoverageEngine.status(0, 0, 0, 0) == CoverageStatus.notCovered)
        check("plenty, with practice: covered", CoverageEngine.status(5, 3, 0, 0) == CoverageStatus.covered)
        check("reading only: thin", CoverageEngine.status(9, 0, 0, 0) == CoverageStatus.thin)
        check("answered badly: thin however much there is", CoverageEngine.status(20, 20, 10, 5) == CoverageStatus.thin)
        val item = CoverageEngine.item("Subarachnoid haemorrhages present suddenly", practice = true)
        check("a phrase matches in order, plural or not", CoverageEngine.Keyword("subarachnoid hemorrhage").matches(item))
        check("the words out of order do not", !CoverageEngine.Keyword("haemorrhage subarachnoid").matches(item))
        val set = StudySet(name = "Neuro", subject = "Neurology", kind = StudySetKind.MCQ,
            questions = listOf(MCQQuestion(stem = "Thunderclap headache: which bleed?", options = listOf("Subarachnoid haemorrhage"), correctIndex = 0)))
        val areas = CoverageEngine.assess(listOf(set), mapOf(set.questions[0].id to listOf(true, false)), Syllabus.areas(ExamTrack.plab))
        val hit = areas.flatMap { it.subtopics }.filter { it.evidence > 0 }
        check("every exam's syllabus has areas", ExamTrack.entries.all { Syllabus.areas(it).isNotEmpty() })
        check("a question is found under its subtopic, with its answers", hit.any { it.answered == 2 && it.correct == 1 }, "${hit.map { it.id }}")
    }

    @Test fun theExampleHistory() = checks {
        val first = InsightExamples.make(emptyList(), now = 1_790_000_000_000L)
        val again = InsightExamples.make(emptyList(), now = 1_790_000_000_000L)
        check("four example sets, one a subject", first.sets.map { it.subject } == listOf("Cardiology", "Respiratory", "Endocrinology", "Neurology"))
        check("the same rolls every time",
            first.events.map { it.correct to it.confidence } == again.events.map { it.correct to it.confidence } &&
                first.reasons.values.map { it.reason } == again.reasons.values.map { it.reason })
        check("every answer is marked an example", first.events.all { it.isExample == true } && first.reasons.values.all { it.isExample == true })
        check("at most eight rules", first.rules.size <= 8 && first.rules.values.all { it.isExample == true })
        check("two to four answers a question", first.events.groupBy { it.questionId }.values.all { it.size in 2..4 })
    }
}
