package com.stethoscore.app.data

import com.stethoscore.app.quiz.ExamTrack
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of iOS Tests/OsceTests.swift, check for check: tidying generated
 * stations, the round trip through the text format, the prompt, a card
 * file's question and cloze lines, and a run through a station in order.
 * Each part collects its failures and reports them all, as the Swift suite does.
 */
class OsceTest {
    private class Checks {
        val failures = mutableListOf<String>()
        fun ok(condition: Boolean, what: String) { if (!condition) failures += what }
        fun done() = assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    private fun checks(body: Checks.() -> Unit) = Checks().apply(body).done()

    private fun station(title: String, steps: List<String>) = OsceChecklist(title = title, steps = steps)
    private val three = listOf("Introduce yourself", "Gain consent", "Wash your hands")

    @Test fun numberingComesOff() = checks {
        ok(OsceStations.stripLeadingMarker("1. Wash your hands") == "Wash your hands", "a leading number is not part of the step")
        ok(OsceStations.stripLeadingMarker("2) Introduce yourself") == "Introduce yourself", "however it is punctuated")
        ok(OsceStations.stripLeadingMarker("- Gain consent") == "Gain consent", "a dash is a bullet, not a word")
        ok(OsceStations.stripLeadingMarker("Step 3: Expose the chest") == "Expose the chest", "and neither is 'Step 3:'")
        ok(OsceStations.stripLeadingMarker("10 mL of saline") == "10 mL of saline", "but a step that simply starts with a number keeps it")
        // real clinical numbers are not list numbering
        for (kept in listOf("12-lead ECG interpretation", "0.9% saline flush", "5-10 mL lidocaine to the skin",
            "3.5 mmol/L is the lower limit", "2.5 cm incision")) {
            ok(OsceStations.stripLeadingMarker(kept) == kept, "\"$kept\" keeps its number")
        }
        ok(OsceStations.stripLeadingMarker("3.Palpate the abdomen") == "Palpate the abdomen", "\"3.Palpate\" is numbering")
        ok(OsceStations.stripLeadingMarker("4: Auscultate the heart") == "Auscultate the heart", "\"4: \" is numbering")
        ok(OsceStations.stripLeadingMarker("1. 12-lead ECG") == "12-lead ECG", "numbering before a clinical number goes, the number stays")
        ok(OsceStations.tidy(listOf(OsceChecklist(title = "12-lead ECG interpretation",
            steps = listOf("Introduce yourself", "12-lead ECG to look for ischaemia", "Check rate and rhythm"))))
            .firstOrNull()?.let { it.title == "12-lead ECG interpretation" && it.steps[1] == "12-lead ECG to look for ischaemia" } == true,
            "a station about a 12-lead ECG keeps its title and steps whole")
    }

    @Test fun cleaning() = checks {
        val messy = listOf(
            "  1. Wash your hands  ",
            "Wash your hands",          // the same step again
            "WASH YOUR HANDS",          // and again, shouting
            "",                         // nothing
            "ok",                       // too short to be a step
            "x".repeat(300),            // a paragraph, not a step
            "Introduce\nyourself to the patient",
        )
        ok(OsceStations.clean(messy) == listOf("Wash your hands", "Introduce yourself to the patient"),
            "cleaning strips numbering, drops repeats, blanks, stubs and paragraphs")
        ok(OsceStations.clean(listOf("Wash your hands", "Introduce yourself", "Examine the abdomen", "Wash your hands"))
            == listOf("Wash your hands", "Introduce yourself", "Examine the abdomen", "Wash your hands"),
            "the closing hand wash stays: it is a mark of its own")
        ok(OsceStations.clean(listOf("Wash hands", "Palpate", "Thank the patient", "Wash hands", "Palpate", "Thank the patient"))
            == listOf("Wash hands", "Palpate", "Thank the patient"),
            "a station sent twice is still kept once")

        val finished = OsceRun(2).gotIt().gotIt()
        ok(finished.resumePoint(0, 3)?.let { listOf(it.station, it.step) } == listOf(1, 0),
            "a station finished is picked back up at the next station's first step, not its own last")
        ok(finished.resumePoint(2, 3) == null, "the last station finished leaves nothing to resume")
        val partWay = OsceRun(4).gotIt().startOver().gotIt()
        ok(partWay.resumePoint(1, 3)?.let { listOf(it.station, it.step) + it.misses } == listOf(1, 1, 1),
            "part way through, it is picked up where it was, misses and all")

        ok(OsceStations.clean(List(5) { "" }).isEmpty(), "a station of nothing cleans to nothing")
        val many = (1..50).map { "Step number $it of the examination" }
        ok(OsceStations.clean(many).size == OsceStations.maxSteps, "an unreasonably long station is capped")
    }

    private val tidied by lazy {
        OsceStations.tidy(listOf(
            station("  1. Respiratory examination ", listOf("1. Introduce yourself", "Gain consent", "Wash hands", "Wash hands")),
            station("Respiratory Examination", three),       // the same station, differently cased
            station("Too short", listOf("a", "b")),          // not a station
            station("Abdominal examination", three),
        ))
    }

    @Test fun whatCountsAsAStation() = checks {
        ok(OsceStations.isUsable(station("Cardiovascular examination", three)), "a titled station with enough steps is usable")
        ok(!OsceStations.isUsable(station("", three)), "one with no title is not")
        ok(!OsceStations.isUsable(station("Something", listOf("Only this", "And this"))),
            "and neither is one with two steps, which is not a station")
        ok(tidied.size == 2, "tidying drops repeats and the unusable")
        ok(tidied[0].title == "Respiratory examination", "and cleans the title too")
        ok(tidied[0].steps == listOf("Introduce yourself", "Gain consent", "Wash hands"), "and the steps inside it")
        ok(tidied[1].title == "Abdominal examination", "keeping the order they arrived in")
    }

    // Generated stations are handed to the student as text to edit before
    // saving, so what comes out has to be exactly what the new-set screen reads back in.
    @Test fun theTextFormatRoundTrips() = checks {
        val formatted = OsceStations.format(tidied)
        val reparsed = OsceText.parseOsce(formatted)
        ok(reparsed.size == tidied.size, "every station survives the round trip")
        ok(reparsed.map { it.title } == tidied.map { it.title }, "with its title")
        ok(reparsed.map { it.steps } == tidied.map { it.steps }, "and every step, in order")
        ok(formatted.startsWith("## "), "and it is written in the format the screen documents")
    }

    @Test fun thePromptCarriesWhatItHasTo() = checks {
        val asked = OsceStations.prompt("A lecture about the abdomen.", 2, "Surgery", listOf("Respiratory examination"))
        ok(asked.contains("Surgery"), "the prompt names the subject")
        ok(asked.contains("A lecture about the abdomen."), "and carries the source")
        ok(asked.contains("Respiratory examination"), "and says what has already been written, so the next call does not repeat it")
        ok(asked.contains("Do not number the steps"), "and asks for unnumbered steps, since the order is the number")
        val plab = OsceStations.prompt("Chest pain.", 1, "", emptyList(), exam = ExamTrack.plab)
        ok(plab.contains("PLAB 2") && plab.contains("8 minutes"), "a PLAB student gets PLAB 2 stations")
        ok(!OsceStations.prompt("x", 1, "", emptyList(), exam = ExamTrack.general).contains("PACES"), "and general revision gets no exam format")
    }

    // Cards: question lines and cloze lines both import
    @Test fun cardLines() = checks {
        val mixedCards = OsceText.parseAnkiQA("""
            First-line drug for all SLE patients? | **hydroxychloroquine** | protects against flares
            Anti-{{c1::dsDNA}} antibodies rise with lupus nephritis activity. | used to monitor
            The malar rash spares the {{c1::nasolabial folds}}.
        """.trimIndent())
        ok(mixedCards.size == 3, "question and cloze lines both become cards")
        ok(mixedCards.count { it.type == AnkiCardType.CLOZE } == 2 && mixedCards[1].why == "used to monitor",
            "a cloze line keeps its hidden part, and its reason when it has one")
    }

    @Test fun aRunThroughAStationGoesInOrder() = checks {
        var run = OsceRun(3)
        ok(run.stepIndex == 0 && !run.complete && run.restarts == 0, "a run starts at step 1")
        run = run.gotIt()
        ok(run.stepIndex == 1, "I got it moves on to the next step")
        run = run.startOver()
        ok(run.stepIndex == 0 && run.misses == listOf(1) && !run.complete, "Start over goes back to step 1 and keeps the miss")
        run = run.gotIt().gotIt().startOver()
        ok(run.misses == listOf(1, 2) && run.restarts == 2, "every start over is kept, at the step it happened")
        run = run.gotIt().gotIt().startOver()
        ok(run.weakSteps.map { it.step } == listOf(2, 1) && run.weakSteps.firstOrNull()?.times == 2, "the step missed most comes first")
        run = run.gotIt().gotIt().gotIt()
        ok(run.complete && run.stepIndex == 2, "getting the last step finishes the station")
        run = run.startOver().gotIt()
        ok(run.complete && run.restarts == 3, "and a finished run is left alone")
        ok(OsceRun(0).complete, "a station with no steps is already done")
        val restored = OsceRun(3, stepIndex = 9, misses = listOf(0, 7))
        ok(restored.stepIndex == 2 && restored.misses == listOf(0), "a saved position is fitted to the station")
        val clean = OsceRun(2).gotIt().gotIt()
        ok(clean.complete && clean.weakSteps.isEmpty(), "a clean run has no weak steps")
    }
}
