package com.stethoscore.app.data

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyKind
import com.stethoscore.app.accuracy.AccuracyRules
import com.stethoscore.app.data.CaseFile.Obs.Sign
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of iOS Tests/CasesTests.swift, check for check, same cases and
 * numbers: the case file read tolerantly and kept through a StudySet, the
 * structure checks, the H and L flags, the run (steps once, the clock, the
 * ladder copied after every step), the score and its cap, the debrief's
 * turning point and cards, and a writer's JSON read back into a case. The
 * history is a written clerking note: no step ever questions the patient.
 *
 * Each section collects its failures and reports them all, as the Swift
 * suite does.
 */
class CasesTest {

    private val pe: CaseFile = CaseSamples.breathless
    private val gca: CaseFile = CaseSamples.headache

    private class Checks {
        val failures = mutableListOf<String>()
        fun check(label: String, ok: Boolean, detail: String = "") {
            if (!ok) failures += label + if (detail.isEmpty()) "" else "  | $detail"
        }
        fun done() = assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    private fun checks(body: Checks.() -> Unit) = Checks().apply(body).done()

    private fun problems(edit: (CaseFile) -> CaseFile): List<CaseChecks.Problem> = CaseChecks.problems(edit(pe))

    private fun List<CaseStep>.edit(index: Int, change: (CaseStep) -> CaseStep) = mapIndexed { i, s -> if (i == index) change(s) else s }

    /** A run of a case: these steps in order, the ladder set before each, then the decision. */
    private fun play(steps: List<Pair<String, List<String>>>, diagnosis: String, next: Int, file: CaseFile = pe): CaseRun {
        val r = CaseRun(caseID = file.id, started = 0L)
        for ((id, ladder) in steps) {
            r.setLadder(ladder)
            r.take(id, file)
        }
        r.decide(CaseRun.Decision(diagnosis = diagnosis, nextStep = next), file, at = 60_000L)
        return r
    }

    private val ideal get() = play(listOf("s3" to listOf(), "s2" to listOf("Pneumothorax"), "s8" to listOf("Pneumonia"), "s13" to listOf("Pulmonary embolism")),
        diagnosis = "Pulmonary embolism", next = 0)
    private val wrong get() = play(listOf("s2" to listOf(), "s13" to listOf()), diagnosis = "Pneumonia", next = 4)
    private val missedCalf get() = play(listOf("s3" to listOf(), "s8" to listOf(), "s13" to listOf()), diagnosis = "PE", next = 0)
    private val lowYield get() = play(listOf("s5" to listOf(), "s6" to listOf(), "s12" to listOf(), "s2" to listOf()), diagnosis = "PE", next = 0)
    private val slow: CaseRun get() {
        val r = CaseRun(caseID = pe.id)
        for (step in pe.steps) r.take(step.id, pe)
        r.decide(CaseRun.Decision(diagnosis = "PE", nextStep = 0), pe)
        return r
    }

    // MARK: the samples pass their own checks

    @Test fun samplesPassTheirOwnChecks() = checks {
        for (sample in CaseSamples.all) {
            val found = CaseChecks.problems(sample)
            check("sample “${sample.title}” is playable", found.isEmpty(), found.joinToString("; ") { it.said })
            val hits = AccuracyRules.hits(CaseChecks.item(sample))
            check("sample “${sample.title}” has no rule hit at all", hits.isEmpty(), hits.joinToString("; ") { it.detail })
            check("sample “${sample.title}” has three teaching points", sample.teaching.size == 3)
            check("sample “${sample.title}” has a full clerking note", sample.clerking.parts.size == 5)
        }
    }

    // MARK: no questioning the patient

    @Test fun noQuestioningThePatient() = checks {
        check("two groups only: examine and test", CaseStep.Group.entries.toList() == listOf(CaseStep.Group.examine, CaseStep.Group.test))
        check("a history step reads as no group", CaseStep.Group.read("history") == null && CaseStep.Group.read("ask") == null
            && CaseStep.Group.read("Questions") == null)
        check("loose names still read", CaseStep.Group.read("Exam") == CaseStep.Group.examine && CaseStep.Group.read("investigation") == CaseStep.Group.test)
    }

    // MARK: the structure checks

    @Test fun structureChecks() = checks {
        check("too few steps", problems { it.copy(steps = it.steps.take(7)) }.contains(CaseChecks.Problem.StepCount(7)))
        check("too many steps", problems { f ->
            f.copy(steps = f.steps + (1..8).map { CaseStep(id = "x$it", group = CaseStep.Group.examine, label = "Extra $it", finding = "Nothing", minutes = 1, value = CaseStep.Yield.low) })
        }.contains(CaseChecks.Problem.StepCount(21)))
        check("a missing group", problems { f -> f.copy(steps = f.steps.filter { it.group != CaseStep.Group.examine }) }
            .contains(CaseChecks.Problem.MissingGroup(CaseStep.Group.examine)))
        check("no clerking note", problems { it.copy(clerking = CaseFile.Clerking()) }.contains(CaseChecks.Problem.NoClerking))
        check("fewer than two key steps", problems { f ->
            f.copy(steps = f.steps.map { if (it.id != "s2" && it.value == CaseStep.Yield.key) it.copy(value = CaseStep.Yield.useful) else it })
        }.contains(CaseChecks.Problem.FewKeySteps(1)))
        check("the diagnosis must be a differential", problems { it.copy(differentials = it.differentials.drop(1)) }
            .contains(CaseChecks.Problem.DiagnosisNotInDifferentials))
        check("a differential with no support", problems { f ->
            f.copy(differentials = f.differentials.mapIndexed { i, d -> if (i == 1) d.copy(supportedBy = emptyList()) else d })
        }.contains(CaseChecks.Problem.Unsupported("Pneumonia")))
        check("a differential naming a missing step", problems { f ->
            f.copy(differentials = f.differentials.mapIndexed { i, d -> if (i == 1) d.copy(againstBy = d.againstBy + "s99") else d })
        }.contains(CaseChecks.Problem.UnknownStep("s99")))
        check("the turning step must be key", problems { it.copy(turningStep = "s1") }.contains(CaseChecks.Problem.TurningStepNotKey))
        check("the budget covers key steps plus 30%", CaseChecks.budgetNeeded(pe) == 56
            && problems { it.copy(budgetMinutes = 55) }.contains(CaseChecks.Problem.BudgetShort(have = 55, need = 56))
            && problems { it.copy(budgetMinutes = 56) }.none { it is CaseChecks.Problem.BudgetShort })
        check("next step needs four or five options", problems { it.copy(nextStep = it.nextStep.copy(options = it.nextStep.options.take(3))) }
            .contains(CaseChecks.Problem.NextStepOptions))
        check("next step key in range", problems { it.copy(nextStep = it.nextStep.copy(key = 9)) }.contains(CaseChecks.Problem.NextStepOptions))
        check("a key that stands out by length is refused", problems { f ->
            f.copy(nextStep = f.nextStep.copy(options = listOf("Start apixaban, a direct oral anticoagulant, today, with a plan for three months and review") + f.nextStep.options.drop(1)))
        }.contains(CaseChecks.Problem.NextStepUnbalanced))
        check("an impossible result is refused", problems { f ->
            f.copy(steps = f.steps.edit(7) { it.copy(results = it.results + CaseStep.LabResult(name = "Potassium", value = 45.0, unit = "mmol/L")) })
        }.any { it is CaseChecks.Problem.Accuracy })
        check("a dose outside any usual range is refused", problems { f ->
            f.copy(clerking = f.clerking.copy(drugs = "Takes paracetamol 40 g each day."))
        }.any { it is CaseChecks.Problem.Accuracy })
        check("blank complaint", problems { it.copy(complaint = " ") }.contains(CaseChecks.Problem.Blank))
    }

    @Test fun tidyingChangesOnlyTheMechanics() = checks {
        // tidying: no medicine changed, only the mechanics
        val loose = pe.copy(
            steps = pe.steps.edit(0) { it.copy(id = "") }.edit(1) { it.copy(id = "s3") },
            turningStep = "nowhere",
            budgetMinutes = 10,
        )
        val tidy = CaseChecks.tidied(loose)
        check("tidy numbers a blank id and a repeated one", tidy.steps.map { it.id }.toSet().size == tidy.steps.size && tidy.steps[0].id == "s1")
        check("tidy points a lost turning step at the first key step", tidy.turningStep == tidy.keySteps.firstOrNull()?.id)
        check("tidy raises a short budget to cover the key steps", tidy.budgetMinutes == CaseChecks.budgetNeeded(tidy))

        val screened = CaseChecks.screen(listOf(pe, pe.copy(steps = emptyList())))
        check("screen keeps the playable, marked passed", screened.kept.size == 1 && screened.kept[0].verification == CaseFile.Verification.passed)
        check("screen drops the rest with reasons", screened.dropped.size == 1 && screened.dropped[0].why.isNotEmpty())
        check("a held case is kept off the list", CaseChecks.isHeld(pe, flagged = setOf(pe.id))
            && !CaseChecks.isHeld(pe, flagged = emptySet()) && CaseChecks.isHeld(pe.copy(verification = CaseFile.Verification.held), flagged = emptySet()))
    }

    // MARK: the chart's flags

    @Test fun chartFlags() = checks {
        check("tachycardia flagged high", CaseChart.flag(CaseFile.Obs(Sign.hr, 112.0)) == CaseChart.Flag.high)
        check("normal heart rate not flagged", CaseChart.flag(CaseFile.Obs(Sign.hr, 78.0)) == null)
        check("saturation 93 flagged low", CaseChart.flag(CaseFile.Obs(Sign.spo2, 93.0)) == CaseChart.Flag.low)
        check("systolic 86 flagged low", CaseChart.flag(CaseFile.Obs(Sign.bp, 86.0, 50.0)) == CaseChart.Flag.low)
        check("142/84 flagged high, as the question chart flags it", CaseChart.flag(CaseFile.Obs(Sign.bp, 142.0, 84.0)) == CaseChart.Flag.high)
        check("fever flagged high", CaseChart.flag(CaseFile.Obs(Sign.temp, 38.4)) == CaseChart.Flag.high)
        check("PaO2 8.9 kPa low by the accuracy engine's range", CaseChart.flag(CaseStep.LabResult(name = "PaO2", value = 8.9, unit = "kPa")) == CaseChart.Flag.low)
        check("pH 7.47 high", CaseChart.flag(CaseStep.LabResult(name = "pH", value = 7.47)) == CaseChart.Flag.high)
        check("potassium in mmol/L by the table", CaseChart.flag(CaseStep.LabResult(name = "Potassium", value = 6.1, unit = "mmol/L")) == CaseChart.Flag.high)
        check("the table wins over a stated range", CaseChart.flag(CaseStep.LabResult(name = "Sodium", value = 140.0, unit = "mmol/L", low = 141.0, high = 150.0)) == null)
        check("a stated range for a test the table lacks", CaseChart.flag(CaseStep.LabResult(name = "CRP", value = 64.0, unit = "mg/L", low = 0.0, high = 5.0)) == CaseChart.Flag.high)
        check("no range, no flag", CaseChart.flag(CaseStep.LabResult(name = "Troponin", value = 12.0, unit = "ng/L")) == null)
    }

    // MARK: names

    @Test fun names() = checks {
        check("names match across case and punctuation", CaseNames.same("Pulmonary-embolism", "pulmonary embolism"))
        check("an accepted name is the diagnosis", pe.isDiagnosis("PE") && pe.isDiagnosis("pulmonary thromboembolism"))
        check("a runner-up is not", !pe.isDiagnosis("Pneumonia"))
        check("typed names resolve to the case's own", pe.resolve("chest infection") == "Pneumonia" && pe.resolve("pe") == "Pulmonary embolism")
        check("an unknown name does not resolve", pe.resolve("Gout") == null)
        val candidates = pe.candidates
        check("candidates: every differential and distractor once", candidates.size == 7
            && candidates.toSet() == (pe.differentials.map { it.name } + pe.distractors).toSet())
        check("candidates in the same order every time", candidates == pe.candidates)
        check("the diagnosis is not always first", CaseSamples.all.any { it.candidates.firstOrNull() != it.diagnosis.name })
        check("the runner-up is the first non-diagnosis", pe.runnerUp?.name == "Pneumonia" && gca.runnerUp?.name == "Polymyalgia rheumatica")
    }

    /**
     * Not in the Swift suite: the order a phone and an iPad show a case's
     * candidates in is the same. The expected values were printed by Swift's
     * own SplitMix64, next(upperBound:) and shuffle on Linux.
     */
    @Test fun candidateOrderMatchesIos() {
        assertEquals(listOf("Acute asthma", "Aortic dissection", "Pulmonary embolism", "Panic attack", "Pneumonia", "Pericarditis", "Pneumothorax"), pe.candidates)
        assertEquals(listOf("Giant cell arteritis", "Trigeminal neuralgia", "Tension-type headache", "Acute angle-closure glaucoma", "Sinusitis", "Polymyalgia rheumatica"), gca.candidates)
        val g = CaseShuffle(gca.id)
        assertEquals(listOf("2955154125685971485", "7965636852031707873", "2848903241837681296", "11507862183612597957", "9733764871786357523"),
            (1..5).map { g.next().toString() })
        assertEquals(listOf(6, 17, 7, 26, 22, 10, 19, 37, 20, 35, 0, 30, 36, 18, 5, 24, 21, 27, 9, 1, 28, 34, 31, 38, 12, 16, 23, 15, 32, 13, 3, 11, 8, 14, 33, 25, 4, 2, 39, 29),
            CaseShuffle(gca.id).shuffled((0 until 40).toList()))
    }

    // MARK: the run

    @Test fun theRun() = checks {
        val run = CaseRun(caseID = pe.id)
        check("a fresh run is new", run.state == CaseRun.State.New && run.minutesUsed == 0)
        check("a step is taken", run.take("s2", pe) && run.minutesUsed == 3)
        check("not twice", !run.take("s2", pe) && run.taken.size == 1)
        check("not a step the case lacks", !run.take("s99", pe))
        run.add("pneumonia", pe)
        run.add("PE", pe)
        check("ladder names are the case's own", run.ladder == listOf("Pneumonia", "Pulmonary embolism"))
        run.add("Pulmonary embolism", pe)
        check("a rung once", run.ladder.size == 2)
        run.add("Pericarditis", pe)
        run.add("Pneumothorax", pe)
        check("three rungs at most; a newcomer takes the bottom", run.ladder == listOf("Pneumonia", "Pulmonary embolism", "Pneumothorax"))
        run.move("Pulmonary embolism", up = true)
        check("a rung moves up", run.ladder.firstOrNull() == "Pulmonary embolism")
        run.move("Pulmonary embolism", up = true)
        check("the top cannot move higher", run.ladder.firstOrNull() == "Pulmonary embolism")
        run.remove("Pneumothorax")
        check("a rung is removed", run.ladder == listOf("Pulmonary embolism", "Pneumonia"))
        check("a run with steps is seen", run.state == CaseRun.State.Seen)
        check("the ladder is copied once per step", run.ladders.size == run.taken.size && run.ladders[0] == emptyList<String>())
    }

    // MARK: the score

    @Test fun theScore() = checks {
        val ideal = ideal
        val best = ideal.score!!
        check("all key and red flags, right answers, in time: 100", best.total == 100, "$best")
        check("a finished run is discharged with its score", ideal.state == CaseRun.State.Discharged(score = 100))
        check("a finished run takes no more steps", ideal.copy().let { !it.take("s1", pe) })

        val wrong = wrong
        check("wrong diagnosis and next step lose 30 and 20", wrong.score?.diagnosis == 0 && wrong.score?.nextStep == 0)
        check("red flags in proportion (1 of 2 = 8 of 15)", wrong.score?.redFlags == 8, "${wrong.score}")

        val missedCalf = missedCalf
        check("key findings in proportion (2 of 3 = 17 of 25)", missedCalf.score?.keyFindings == 17)
        check("a missed must-not-miss caps the total at 60", missedCalf.score?.capped == true && missedCalf.score?.total == 60, "${missedCalf.score}")

        val lowYield = lowYield
        check("three low-yield steps cost 4 of the time", lowYield.score?.time == 6, "${lowYield.score}")
        check("one low-yield step is free", play(listOf("s2" to listOf(), "s5" to listOf(), "s8" to listOf(), "s13" to listOf()), diagnosis = "PE", next = 0).score?.time == 10)

        val slow = slow
        check("past the budget: allowed, counted", slow.minutesUsed > pe.budgetMinutes && slow.isOver(pe))
        check("over budget with three low-yield steps: 10 - 4 - 5", slow.score?.time == 1, "${slow.score}")
        check("shares round to the nearest, all when nothing to find", CaseScore.share(0, of = 3, points = 25) == 0
            && CaseScore.share(5, of = 0, points = 15) == 15)
    }

    // MARK: the debrief

    @Test fun theDebrief() = checks {
        val lateLead = CaseDebrief(file = pe, run = ideal)
        check("turning point: the ladder led only after a later step",
            lateLead.turning == CaseDebrief.Turning.Late(turning = "Examine the legs", led = "CT pulmonary angiogram"), "${lateLead.turning}")
        val quick = play(listOf("s2" to listOf("Pulmonary embolism"), "s13" to listOf("Pulmonary embolism")), diagnosis = "PE", next = 0)
        check("turning point: in time", CaseDebrief(file = pe, run = quick).turning == CaseDebrief.Turning.OnTime(turning = "Examine the legs", led = "Examine the legs"))
        check("turning point: never led", CaseDebrief(file = pe, run = wrong).turning == CaseDebrief.Turning.Never(turning = "Examine the legs"))
        check("turning point: the step was never taken", CaseDebrief(file = pe, run = missedCalf).turning == CaseDebrief.Turning.MissedStep(turning = "Examine the legs"))
        val lateLadder = CaseRun(caseID = pe.id)
        lateLadder.take("s2", pe)
        lateLadder.setLadder(listOf("Pulmonary embolism"))
        lateLadder.decide(CaseRun.Decision(diagnosis = "PE", nextStep = 0), pe)
        check("turning point: only at the decision", CaseDebrief(file = pe, run = lateLadder).turning == CaseDebrief.Turning.AtDecision(turning = "Examine the legs"))
        check("every turning point is said", CaseDebrief(file = pe, run = missedCalf).turningSaid.isNotEmpty())

        val missedDebrief = CaseDebrief(file = pe, run = missedCalf)
        check("missed red flags, the must-not-miss first", missedDebrief.missedRedFlags.map { it.id } == listOf("s2"))
        check("key findings counted", missedDebrief.keyFound == 2 && missedDebrief.keyFindings.size == 3)
        check("separating findings: the diagnosis's against the runner-up's", lateLead.separating.map { it.step.id } == listOf("s9"))
        check("separating findings in the clinic case", CaseDebrief(file = gca, run = CaseRun(caseID = gca.id)).separating.map { it.step.id } == listOf("s1", "s2", "s11"))
        val lowDebrief = CaseDebrief(file = pe, run = lowYield)
        check("low-yield steps listed with why", lowDebrief.lowYield.map { it.id } == listOf("s5", "s6", "s12") && lowDebrief.lowYield.all { it.note.isNotEmpty() })
        val cards = missedDebrief.cards
        check("one card per missed key finding or red flag", cards.size == 1 && cards[0].bullets.firstOrNull() == pe.step("s2")?.finding)
        check("cards are basic and tagged", cards.all { it.type == AnkiCardType.QA && it.tags.contains("Cases") }
            && cards[0].why.startsWith("Must not miss"))
        check("nothing missed, no cards", CaseDebrief(file = pe, run = slow).cards.isEmpty())
        check("the Ideas note names the diagnosis", lateLead.ideaText.contains("Pulmonary embolism") && lateLead.ideaTitle == "Case: Pulmonary embolism")
    }

    // MARK: saved and read back

    /** A case as the samples hold it: the kept original objects left out, since a read keeps what it read. */
    private fun CaseFile.bare(): CaseFile = copy(
        rawJson = "{}",
        patient = patient.copy(rawJson = "{}"), clerking = clerking.copy(rawJson = "{}"),
        arrival = arrival.map { it.copy(rawJson = "{}") },
        steps = steps.map { s -> s.copy(rawJson = "{}", results = s.results.map { it.copy(rawJson = "{}") }) },
        diagnosis = diagnosis.copy(rawJson = "{}"), differentials = differentials.map { it.copy(rawJson = "{}") },
        nextStep = nextStep.copy(rawJson = "{}"), source = source.copy(rawJson = "{}"),
    )

    @Test fun savedAndReadBack() = checks {
        val set = StudySet(name = "Patients", subject = "Medicine", kind = StudySetKind.CASES, caseFiles = CaseSamples.all)
        val data = StudyJson.encodeSet(set).toString()
        val back = StudyJson.decodeSet(JSONObject(data))
        check("a Cases set round-trips", back.kind == StudySetKind.CASES && back.caseFiles.map { it.bare() } == CaseSamples.all && back.itemCount == 2)
        check("the kind is saved as \"cases\"", data.contains("\"kind\":\"cases\""))
        check("its noun", back.itemNoun == "patient" && StudySetKind.CASES.label == "Cases")
        check("\"qa\" is still retired, \"cases\" is not", StudySetKind.from("qa") == null && StudySetKind.from("cases") == StudySetKind.CASES)
        val thin = StudyJson.case(JSONObject("""{"complaint":"I feel faint","clerking":{"presenting":"Faint"},"steps":[{"label":"Look","finding":"Pale","group":"exam"}],"setting":"A&E"}"""))
        check("a case missing most fields still reads", thin.complaint == "I feel faint" && thin.steps.firstOrNull()?.group == CaseStep.Group.examine
            && thin.setting == CaseFile.Setting.emergency && thin.budgetMinutes == 20 && thin.clerking.presenting == "Faint" && thin.clerking.history.isEmpty())
        val copy = set.duplicate()
        check("a copy's cases get new ids", copy.caseFiles.map { it.id }.toSet().intersect(set.caseFiles.map { it.id }.toSet()).isEmpty())
        check("the set's item ids include its cases", set.itemIds.containsAll(CaseSamples.all.map { it.id }))
        val items = AccuracyItem.items(set)
        check("each case is one accuracy item of kind case", items.size == 2 && items.all { it.kind == AccuracyKind.case })
        check("what it asserts: the clerking and the key, not the wrong options", !items[0].text.contains("alteplase")
            && items[0].text.contains("apixaban") && items[0].text.contains("Flew home from Sydney"))
    }

    // MARK: a writer's JSON

    private val reply = """
Here is the patient:
```json
{"cases":[{"title":"Thirsty and vomiting","specialty":"Endocrinology","setting":"ED",
 "patient":{"name":"Sam Okafor","age":"19","sex":"M","about":"student"},
 "complaint":"\"I can't stop being sick and I'm so thirsty\"",
 "clerking":{"presenting":"Vomiting and abdominal pain, 1 day","history":"A week of thirst and polyuria.","pmh":"Nil","drugs":"None","social":"Student"},
 "vitals":{"hr":118,"sbp":104,"dbp":66,"rr":"28","spo2":99,"temp":36.9},"budget":40,
 "steps":[{"id":"s0","group":"history","label":"Ask about thirst","finding":"Thirsty for a week","minutes":2,"value":"key"},
          {"id":"s1","group":"exam","label":"Smell the breath","finding":"Ketotic breath","minutes":1,"value":"KEY","mustNotMiss":"true"},
          {"id":"s2","group":"investigation","label":"Venous gas","finding":"Acidosis","minutes":10,"value":"key","results":[{"name":"pH","value":7.12},{"name":"Bicarbonate","value":"9","unit":"mmol/L"},{"name":"Ketones","value":5.2,"unit":"mmol/L","low":0,"high":0.6}]}],
 "diagnosis":{"name":"Diabetic ketoacidosis","accepted":["DKA"]},
 "differentials":[{"name":"Diabetic ketoacidosis","for":["s1","s2"],"against":[]},{"name":"Gastroenteritis","for":["s1"],"against":["s2"]}],
 "distractors":["Appendicitis"],"turningStep":"s2",
 "nextStep":{"options":["Fixed-rate insulin infusion","Subcutaneous insulin","Oral rehydration","Antiemetic only","Observe"],"answer":"A","why":"..."},
 "teaching":["One","Two","Three"],"pages":"4-6"}]}
```
""".trimStart('\n')

    @Test fun aWritersJson() = checks {
        val parsed = CaseWriting.parse(reply, lecture = "Endocrine emergencies")
        check("a fenced reply is read", parsed.size == 1)
        parsed.firstOrNull()?.let { w ->
            check("patient read, numbers as strings too", w.patient.age == 19 && w.patient.initials == "SO" && w.setting == CaseFile.Setting.emergency)
            check("the complaint loses the writer's quotation marks", w.complaint == "I can't stop being sick and I'm so thirsty")
            check("the clerking note is read, short keys too", w.clerking.presenting.startsWith("Vomiting") && w.clerking.past == "Nil"
                && w.clerking.drugs == "None")
                check("vitals in the chart's order", w.arrival.map { it.sign } == listOf(Sign.hr, Sign.bp, Sign.rr, Sign.spo2, Sign.temp) && w.arrival[1].shown == "104/66")
            check("a step that questions the patient is dropped", w.steps.map { it.id } == listOf("s1", "s2")
                && w.steps.map { it.group } == listOf(CaseStep.Group.examine, CaseStep.Group.test))
            check("loose values read", w.steps[0].value == CaseStep.Yield.key && w.steps[0].mustNotMiss)
            check("results read, ranges kept only when given", w.steps[1].results.size == 3 && w.steps[1].results[1].value == 9.0
                && w.steps[1].results[2].high == 0.6 && w.steps[1].results[0].low == null)
            check("the answer letter read as an index", w.nextStep.key == 0)
            check("the source names the lecture and pages", w.source.cited == "Endocrine emergencies, pp. 4-6")
        }
        check("a reply with no JSON gives nothing", CaseWriting.parse("Sorry, I cannot help with that.").isEmpty())
        check("one case on its own is read too", CaseWriting.parse("""{"complaint":"Ow","steps":[{"label":"Look","finding":"Red","group":"examine"}]}""").size == 1)
        check("a thinking block is skipped", CaseWriting.parse("<think>{\"x\":1}</think>" + """{"complaint":"Ow","steps":[{"label":"L","finding":"F"}]}""").size == 1)
        check("a case whose only steps question the patient is no case",
            CaseWriting.parse("""{"complaint":"Ow","steps":[{"label":"Ask","finding":"Yes","group":"history"}]}""").isEmpty())
        check("a cloud job's replies are collected up to the count", CaseWriting.collect(listOf(reply, reply, reply), count = 2).size == 2)
    }

    // MARK: the instructions

    @Test fun theInstructions() = checks {
        val rules = CaseWriting.instructions(source = "LECTURE TEXT", subject = "Cardiology",
            brief = CaseWriting.Brief(diagnosis = "Aortic stenosis", unlike = "72 M, clinic", setting = CaseFile.Setting.ward,
                avoid = listOf("Heart failure")), json = true)
        check("the instructions carry the lecture last", rules.endsWith("LECTURE TEXT"))
        check("and the brief", rules.contains("must be Aortic stenosis") && rules.contains("72 M, clinic")
            && rules.contains("ward") && rules.contains("Heart failure") && rules.contains("Cardiology"))
        check("they ask for a clerking note and no questions to the patient", rules.contains("clerking note")
            && rules.contains("never a question to the patient") && !rules.contains("\"ask\""))
        check("and the JSON shape when asked", rules.contains("\"turningStep\"") && rules.contains("\"clerking\"")
            && !CaseWriting.instructions(source = "x", subject = "", brief = CaseWriting.Brief(), json = false).contains("\"turningStep\""))
        check("settings turn over case by case", (0 until 4).map(CaseWriting::setting)
            == listOf(CaseFile.Setting.emergency, CaseFile.Setting.ward, CaseFile.Setting.clinic, CaseFile.Setting.community))
    }

    // MARK: the run kept on the device (Android's store; iOS keeps it in its own file)

    @Test fun aRunSurvivesTheStore() {
        val folder = kotlin.io.path.createTempDirectory("cases").toFile()
        try {
            val runs = CaseRunStore(StudyStore(folder))
            val r = ideal
            runs.save(r)
            val back = CaseRunStore(StudyStore(folder)).run(pe)
            assertEquals(r, back)
            assertEquals(CaseRun.State.Discharged(100), CaseRunStore(StudyStore(folder)).state(pe))
            runs.reset(pe)
            assertEquals(CaseRun.State.New, CaseRunStore(StudyStore(folder)).state(pe))
        } finally {
            folder.deleteRecursively()
        }
    }
}
