package com.stethoscore.app.exam

import com.stethoscore.app.coverage.AreaCoverage
import com.stethoscore.app.coverage.CoverageScope
import com.stethoscore.app.coverage.CoverageStatus
import com.stethoscore.app.coverage.SubtopicCoverage
import com.stethoscore.app.coverage.SyllabusSubtopic
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MockCandidate
import com.stethoscore.app.quiz.MockFormat
import com.stethoscore.app.quiz.MockMarking
import com.stethoscore.app.quiz.MockRandom
import com.stethoscore.app.quiz.PassMark
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID
import kotlin.math.abs

// A port of upstream/ios/RedPen/Tests/ExamCatalogTests.swift, check for check:
// the catalogue's integrity (every blueprint adds up to 100%, formats are
// sane, the published USMLE numbers are the ones used), the choice and its
// fallback when the track changes, the blueprint as coverage map, readiness
// and what to study next, how a generated set divides by blueprint, its mock
// papers and pacing, and a mock drawn in the blueprint's proportions.
//
// Not ported, as Android has no such code yet: the exemplars (no bundled
// ExamExemplars index or picker), the prompts (no MCQGenerator.buildPrompt)
// and the accuracy engine's stricter cut-offs (no AccuracyModel).
class ExamCatalogTest {

    private val failures = ArrayList<String>()

    private fun check(label: String, ok: Boolean, detail: String = "") {
        if (!ok) failures.add("$label  | $detail")
    }

    private fun done() = assertTrue(failures.joinToString("\n"), failures.isEmpty())

    private fun near(a: Double, b: Double, tolerance: Double = 0.01): Boolean = abs(a - b) <= tolerance

    private val all: List<TargetExam> = ExamCatalog.all
    private val step1: TargetExam = ExamCatalog.step1
    private val ck: TargetExam = ExamCatalog.step2ck

    // MARK: - The catalogue

    @Test fun catalogue() {
        check("at least twenty exams", all.size >= 20, "${all.size}")
        check("ids are unique", all.map { it.id }.toSet().size == all.size)
        val wantedIds = listOf("step1", "step2ck", "step3", "comlex1", "comlex2", "plab1", "mrcp1", "mrcsA", "mccqe1", "amc",
            "neetpg", "inicet", "fmge", "smle", "dha", "doh", "mohap", "qchp", "omsb", "emle", "ifom")
        check("every exam asked for is there", wantedIds.all { ExamCatalog.exam(it) != null },
            wantedIds.filter { ExamCatalog.exam(it) == null }.joinToString(","))
        for (exam in all) {
            val total = exam.shares.sumOf { it.percent }
            check("${exam.id}: the blueprint sums to 100%", near(total, 100.0), "$total")
            check("${exam.id}: raw weights are near 100% (or out of 200 / 300)",
                listOf(100.0, 200.0, 300.0).any { abs(exam.totalWeight - it) / it <= 0.13 }, "${exam.totalWeight}")
            check("${exam.id}: no area twice", exam.blueprint.map { it.domain }.toSet().size == exam.blueprint.size)
            check("${exam.id}: every weight positive", exam.blueprint.all { it.weight > 0 })
            check("${exam.id}: four or five options", exam.options == 4 || exam.options == 5)
            check("${exam.id}: a paper to sit", exam.sections.isNotEmpty() && exam.sections.all { it.questions > 0 && it.minutes > 0 })
            check("${exam.id}: a sane pace", exam.secondsPerQuestion in 45..120, "${exam.secondsPerQuestion} s")
            check("${exam.id}: a sane pass mark", exam.passMark >= 0.4 && exam.passMark <= 0.8)
            check("${exam.id}: strictness 0-1", exam.accuracyStrictness >= 0 && exam.accuracyStrictness <= 1)
            check("${exam.id}: a stem range", exam.stemWords.first > 0 && exam.stemWords.last > exam.stemWords.first)
            check("${exam.id}: cites its blueprint", exam.blueprintSource.length > 20)
            check("${exam.id}: not both blockwise and separate", !(exam.sitsBlockwise && exam.sitsSeparately))
        }
        for (domain in ExamDomain.entries) {
            check("${domain.rawValue} has syllabus subtopics", ExamBlueprint.subtopics(domain).isNotEmpty())
        }
        check("the picker's regions hold every exam", ExamCatalog.byRegion.sumOf { it.exams.size } == all.size)
        done()
    }

    @Test fun publishedNumbers() {
        // the published USMLE Step 1 ranges, midpoints
        check("Step 1: cardiovascular 8% (6-10%)", near(step1.percent(ExamDomain.cardio), 8.0))
        check("Step 1: multisystem 10% (8-12%)", near(step1.percent(ExamDomain.multisystem), 10.0))
        check("Step 1: biostatistics 5% (4-6%)", near(step1.percent(ExamDomain.biostatistics), 5.0))
        check("Step 1: respiratory + renal 13% (11-15%)", near(step1.percent(ExamDomain.resp) + step1.percent(ExamDomain.renal), 13.0))
        check("Step 1 is 7 blocks of 40 in an hour", step1.sections.size == 7 && step1.secondsPerQuestion == 90)
        check("Step 2 CK: normalised from the published midpoints", near(ck.percent(ExamDomain.ethics), 12.5 / 112.5 * 100))
        check("MRCP Part 1 is out of 200", near(ExamCatalog.mrcp1.totalWeight, 200.0) && near(ExamCatalog.mrcp1.percent(ExamDomain.cardio), 7.5))
        check("NEET-PG: four options, negative marking", ExamCatalog.neetpg.options == 4 && ExamCatalog.neetpg.negativeMarking != null)
        check("a kept AI coverage check is filed per picked exam, not per track",
            CoverageScope.key(ExamTrack.general, "neetpg+") != CoverageScope.key(ExamTrack.general, "fmge+")
                && CoverageScope.key(ExamTrack.general) == ExamTrack.general.rawValue
                && !CoverageScope.key(ExamTrack.general, "a/b").contains("/"))
        check("the catalog's marking lines are read as numbers", MockMarking.penalty(ExamCatalog.neetpg.negativeMarking) == 0.25
            && abs(MockMarking.penalty(ExamCatalog.inicet.negativeMarking) - 1.0 / 3) < 1e-9
            && MockMarking.penalty(ExamCatalog.plab1.negativeMarking) == 0.0)
        check("FMGE passes at 50%", near(ExamCatalog.fmge.passMark, 0.5))
        check("Step 2 CK and 3 are stricter than Step 1", ck.accuracyStrictness > step1.accuracyStrictness
            && ExamCatalog.step3.accuracyStrictness >= ck.accuracyStrictness)
        check("the exams with unpublished formats say so", !ExamCatalog.emle.formatConfirmed && !ExamCatalog.dha.formatConfirmed
            && ExamCatalog.emle.blueprintIsApproximate)
        check("families: UK exams keep their track", ExamCatalog.plab1.family == ExamTrack.plab && ExamCatalog.mrcp1.family == ExamTrack.mrcp
            && ExamCatalog.mrcsA.family == ExamTrack.mrcs && step1.family == ExamTrack.usmle && ExamCatalog.smle.family == ExamTrack.general)
        done()
    }

    // MARK: - The choice

    @Test fun choice() {
        val defaults = MemoryExamDefaults()
        check("nothing chosen, nothing asked", ExamChoice.picked(defaults) == null && !ExamChoice.hasAsked(defaults))
        ExamChoice.choose(ExamCatalog.smle, ExamCatalog.dha, defaults)
        check("choosing moves the track to the exam's family", ExamChoice.currentTrack(defaults) == ExamTrack.general)
        check("the choice is effective under its track", ExamChoice.effective(ExamTrack.general, defaults)?.id == "smle")
        check("the second exam comes with it", ExamChoice.secondary(ExamTrack.general, defaults)?.id == "dha")
        check("the accuracy engine is told", near(defaults.double(ExamChoice.strictnessKey), 0.2)
            && defaults.string(ExamChoice.strictnessFamilyKey) == "general")
        check("answered once chosen", ExamChoice.hasAsked(defaults))
        check("another track lets go of it", ExamChoice.effective(ExamTrack.usmle, defaults) == null
            && ExamChoice.secondary(ExamTrack.usmle, defaults) == null)
        check("the UK tracks fall back to their own exam", ExamChoice.effective(ExamTrack.plab, defaults)?.id == "plab1"
            && ExamChoice.effective(ExamTrack.mrcp, defaults)?.id == "mrcp1")
        ExamChoice.choose(step1, step1, defaults)
        check("the same exam twice is one exam", ExamChoice.pickedSecondary(defaults) == null && ExamChoice.currentTrack(defaults) == ExamTrack.usmle)
        ExamChoice.choose(null, null, defaults)
        check("clearing forgets the exam and the strictness", ExamChoice.picked(defaults) == null
            && !defaults.has(ExamChoice.strictnessKey) && ExamChoice.hasAsked(defaults))
        done()
    }

    // MARK: - The plan, coverage, readiness and priority

    private val plan: List<BlueprintArea> = ExamBlueprint.plan(ExamCatalog.neetpg)

    @Test fun plan() {
        check("the plan follows the blueprint, heaviest first", plan.firstOrNull()?.domain == ExamDomain.surgery && plan.size == ExamCatalog.neetpg.blueprint.size)
        check("area names are unique", plan.map { it.title }.toSet().size == plan.size)
        check("alone, weight is share", plan.all { near(it.weight, it.percent) })
        val both = ExamBlueprint.plan(ExamCatalog.neetpg, ExamCatalog.plab1)
        check("a second exam adds its own areas", both.size > plan.size && both.any { it.domain == ExamDomain.emergency && it.percent == 0.0 })
        check("combined weights still add to 100", near(both.sumOf { it.weight }, 100.0, 0.05))
        val surgeryAlone = plan.first { it.domain == ExamDomain.surgery }.weight
        val surgeryBoth = both.first { it.domain == ExamDomain.surgery }.weight
        check("the second exam's share is 30%", near(surgeryBoth, surgeryAlone * 0.7 + ExamCatalog.plab1.percent(ExamDomain.surgery) * 0.3))
        for (exam in all) {
            val p = ExamBlueprint.plan(exam, ExamCatalog.plab1)
            check("${exam.id} + PLAB: unique area names", p.map { it.title }.toSet().size == p.size)
        }
        done()
    }

    @Test fun quotas() {
        // quotas: largest remainder, sums to the count
        val q20 = ExamBlueprint.quotas(20, plan)
        check("quotas add up to the set", q20.sumOf { it.questions } == 20)
        check("the heaviest area gets the most", q20.firstOrNull()?.area?.domain == ExamDomain.surgery && q20.firstOrNull()?.questions == 3,
            q20.joinToString(" ") { "${it.area.domain.rawValue}=${it.questions}" })
        check("one question goes to the heaviest", ExamBlueprint.quotas(1, plan).map { it.area.domain } == listOf(ExamDomain.surgery))
        check("no questions, no quotas", ExamBlueprint.quotas(0, plan).isEmpty())
        val q200 = ExamBlueprint.quotas(200, plan)
        check("200 questions follow NEET-PG's 200-question distribution", q200.firstOrNull { it.area.domain == ExamDomain.pathology }?.questions == 14
            && q200.firstOrNull { it.area.domain == ExamDomain.community }?.questions == 16)
        done()
    }

    // coverage mapping and standings, from a hand-made assessment
    private fun sub(area: String, name: String, status: CoverageStatus, answered: Int = 0, correct: Int = 0): SubtopicCoverage =
        SubtopicCoverage(area, SyllabusSubtopic(name, listOf(name.lowercase())), if (status == CoverageStatus.notCovered) 0 else 5,
            if (status == CoverageStatus.covered) 3 else 0, answered, correct, emptyList(), status)

    @Test fun standings() {
        val small = ExamBlueprint.plan(ExamCatalog.ifom)
        val heavy = small[0]   // surgery or paediatrics, 17.5%
        val light = small.last()
        val assessed = listOf(
            AreaCoverage(heavy.syllabus, listOf(sub(heavy.title, "A", CoverageStatus.notCovered), sub(heavy.title, "B", CoverageStatus.notCovered))),
            AreaCoverage(light.syllabus, listOf(sub(light.title, "C", CoverageStatus.covered, answered = 20, correct = 18),
                sub(light.title, "D", CoverageStatus.thin))),
        )
        val standings = ExamBlueprint.standings(small, assessed)
        val heavyStanding = standings.first { it.area.id == heavy.id }
        val lightStanding = standings.first { it.area.id == light.id }
        check("coverage: covered 1, thin a half", near(lightStanding.coverage, 0.75) && near(heavyStanding.coverage, 0.0))
        check("readiness leans on the answers", lightStanding.readiness > 0.75 && near(heavyStanding.readiness, 0.35),
            "${lightStanding.readiness} ${heavyStanding.readiness}")
        check("an unassessed area starts at the prior", standings.filter { it.area.id != heavy.id && it.area.id != light.id }
            .all { near(it.readiness, 0.35) && it.answered == 0 })
        val next = ExamBlueprint.studyNext(standings, limit = 3)
        check("study next: a heavy uncovered area first", next.firstOrNull()?.area?.weight == small[0].weight && next.size == 3)
        check("study next: a well-known light area is not in it", next.none { it.area.id == light.id })
        val predicted = ExamBlueprint.predictedScore(standings)
        check("predicted score is a weighted readiness", predicted > 0.35 && predicted < 0.5, "$predicted")
        check("blueprint coverage is weighted by share", near(ExamBlueprint.weightedCoverage(standings), 0.75 * light.percent / 100, 0.001))
        done()
    }

    @Test fun domainOfText() {
        // what a piece of text is about
        check("a question on asthma is respiratory", ExamBlueprint.domain("A child with wheeze uses a salbutamol inhaler for asthma") == ExamDomain.resp)
        check("atrial fibrillation is cardiovascular", ExamBlueprint.domain("Atrial fibrillation with a fast ventricular rate: rate control") == ExamDomain.cardio)
        check("within a blueprint only", ExamBlueprint.domain("asthma and wheeze", within = setOf(ExamDomain.cardio, ExamDomain.gi)) == null)
        check("nothing matches, nothing returned", ExamBlueprint.domain("the quick brown fox") == null)
        done()
    }

    // MARK: - Papers and pacing

    @Test fun papersAndPacing() {
        val three = MockFormat.papers(step1, blocks = 3)
        check("Step 1: three blocks of 40 in an hour", three.size == 1 && three[0].sections.size == 3 && three[0].questionCount == 120 && three[0].minutes == 180)
        check("never more blocks than the exam", MockFormat.papers(step1, blocks = 99)[0].sections.size == 7)
        check("MRCP: two papers sat apart", MockFormat.papers(ExamCatalog.mrcp1).map { it.questionCount } == listOf(100, 100))
        val neetPaper = MockFormat.papers(ExamCatalog.neetpg)
        check("NEET-PG: one paper, 200 in 210 minutes", neetPaper.size == 1 && neetPaper[0].questionCount == 200 && neetPaper[0].minutes == 210)
        check("Step 3's blocks are named for the day", MockFormat.papers(ExamCatalog.step3, blocks = 2)[0].title.contains("fip block"))
        check("exam-day kit: a Step 2 CK block", ExamWeekPlanner.paper(ck).questions == 40 && ExamWeekPlanner.paper(ck).minutes == 60)
        check("exam-day kit: all of NEET-PG", ExamWeekPlanner.paper(ExamCatalog.neetpg).questions == 200)
        check("exam-day kit: an unconfirmed format is not called published", !ExamWeekPlanner.paper(ExamCatalog.emle).published)
        check("pass mark: the exam's, else the track's", near(PassMark.typical(ExamCatalog.fmge, ExamTrack.general), 0.5)
            && near(PassMark.typical(null, ExamTrack.mrcs), PassMark.typical(ExamTrack.mrcs)))
        done()
    }

    // a mock in the blueprint's proportions
    private class Seeded(var state: ULong) : MockRandom {
        override fun next(): ULong {
            state = state * 6364136223846793005uL + 1442695040888963407uL
            return state
        }
    }

    @Test fun mockInProportion() {
        val rng = Seeded(42uL)
        val mockPool = ArrayList<ExamMockEntry>()
        repeat(100) { mockPool.add(ExamMockEntry(MockCandidate(UUID.randomUUID().toString(), "Surgery"), ExamDomain.surgery)) }
        repeat(100) { mockPool.add(ExamMockEntry(MockCandidate(UUID.randomUUID().toString(), "Paeds"), ExamDomain.peds)) }
        repeat(3) { mockPool.add(ExamMockEntry(MockCandidate(UUID.randomUUID().toString(), "Psych"), ExamDomain.psychiatry)) }
        repeat(50) { mockPool.add(ExamMockEntry(MockCandidate(UUID.randomUUID().toString(), "Misc"), null)) }
        val ifomPlan = ExamBlueprint.plan(ExamCatalog.ifom)
        val drawn = ExamMock.select(mockPool, wanted = 40, plan = ifomPlan, rng = rng)
        val surgeryDrawn = drawn.count { it.subject == "Surgery" }
        val paedsDrawn = drawn.count { it.subject == "Paeds" }
        check("the mock is the size asked", drawn.size == 40 && drawn.map { it.id }.toSet().size == 40)
        check("areas short of questions give their places away", drawn.count { it.subject == "Psych" } == 3)
        check("surgery and paediatrics share the rest evenly", abs(surgeryDrawn - paedsDrawn) <= 1 && surgeryDrawn + paedsDrawn == 37,
            "$surgeryDrawn $paedsDrawn")
        val rng2 = Seeded(7uL)
        val small5 = ExamMock.select(mockPool.take(5), wanted = 40, plan = ifomPlan, rng = rng2)
        check("a small library gives what it has", small5.size == 5)
        done()
    }
}
