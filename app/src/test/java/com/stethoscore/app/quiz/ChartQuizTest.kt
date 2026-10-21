package com.stethoscore.app.quiz

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.stethoscore.app.quiz.ChartQuiz.Mark as M

// A port of upstream/ios/RedPen/Tests/ChartQuizTests.swift, case for case.
// The question screen as a patient chart: what the header says, which parts
// of a stem the chart card shows (and a stem with nothing to chart left as
// it was), the highlighter's marks across story and question, how options
// are marked - never right or wrong in a timed paper - and the bar's words.
class ChartQuizTest {
    private val nephrotic = "A 34-year-old man presents with swelling of his legs and face for 3 weeks. BP 128/82 mmHg, HR 76/min, temperature 36.8 °C, SpO2 98% on air. Investigations show albumin 22 g/L, cholesterol 8.1 mmol/L and creatinine 88 µmol/L. Urinalysis shows 4+ protein and no blood. What is the most likely diagnosis?"
    private val full = ChartQuiz.layout(nephrotic)

    @Test fun header() {
        assertEquals("the title is the set's subject", "Nephrology", ChartQuiz.title("Nephrology", "Renal 1"))
        assertEquals("no subject: the set's name", "Renal 1", ChartQuiz.title("  ", "Renal 1"))
        assertEquals("neither: Questions", "Questions", ChartQuiz.title("", ""))
        assertEquals("a question is a patient", "Patient 7 of 20", ChartQuiz.status(6, 20))
        assertEquals("a timed paper says only how many are answered", "3 answered", ChartQuiz.detail(examMode = true, resuming = false, correct = 2, checked = 3))
        assertEquals("a saved place asks first", "Pick up where you left off?", ChartQuiz.detail(examMode = false, resuming = true, correct = 0, checked = 0))
        assertEquals("before the first answer, a nudge", "Tap the answer you think is right", ChartQuiz.detail(examMode = false, resuming = false, correct = 0, checked = 0))
        assertEquals("then the running score", "2 of 3 right so far", ChartQuiz.detail(examMode = false, resuming = false, correct = 2, checked = 3))
        assertTrue("the strip starts empty and fills with the paper", ChartQuiz.fraction(0, 20) == 0.0 && ChartQuiz.fraction(10, 20) == 0.5)
        assertTrue("the chip says best answer, or second try on a re-test", ChartQuiz.kindChip(false) == "Best answer" && ChartQuiz.kindChip(true) == "Second try")
        assertEquals("the clock in minutes", "12:30", ChartQuiz.clock(750))
        assertEquals("and in hours for a long paper", "1:05:00", ChartQuiz.clock(3900))
        assertEquals("TalkBack hears minutes and seconds", "2 minutes 5 seconds left", ChartQuiz.spokenClock(125))
    }

    @Test fun chartCard() {
        assertTrue("a stem with observations is charted", !full.plain)
        assertEquals("chips for who the patient is", listOf("34 y", "Male", "3 wk"), full.chips)
        assertTrue("the vitals grid and the results table: ${full.vitals} ${full.labs}",
            full.vitals.map { it.label } == listOf("BP", "HR", "Temp", "SpO2") && full.labs.size == 3)
        assertEquals("the story, without the lines the chart shows",
            "A 34-year-old man presents with swelling of his legs and face for 3 weeks. Urinalysis shows 4+ protein and no blood.", full.story)
        assertEquals("the question on its own", "What is the most likely diagnosis?", full.question)

        val recall = "Which nerve supplies the deltoid muscle?"
        val plain = ChartQuiz.layout(recall)
        assertTrue("a stem with nothing to chart is plain text, whole", plain.plain && plain.story == recall && plain.question.isEmpty())
        assertTrue("with no chips, grid or table", plain.chips.isEmpty() && plain.vitals.isEmpty() && plain.labs.isEmpty())
        val told = "A 34-year-old man has central chest pain for 2 hours. What is the most likely diagnosis?"
        val toldLayout = ChartQuiz.layout(told)
        assertTrue("who the patient is alone is not a chart", toldLayout.plain && toldLayout.chips.isEmpty() && toldLayout.story == told)

        val labsOnly = "A 34-year-old Black man presents with frothy urine, periorbital oedema and 6 g/day proteinuria. Serum albumin is 22 g/L. Which finding on light microscopy is most consistent with the most common primary cause of nephrotic syndrome in this patient?"
        val results = ChartQuiz.layout(labsOnly)
        assertTrue("results alone: a table and no empty grid: ${results.labs}",
            !results.plain && results.vitals.isEmpty() && results.labs.map { it.name } == listOf("Albumin"))
        val vitalsOnly = ChartQuiz.layout("A 70-year-old woman is confused. Her pulse is 124 beats per minute and temperature 39.2 °C. What is the next step?")
        assertTrue("vitals alone: a grid and no empty table: ${vitalsOnly.vitals}",
            !vitalsOnly.plain && vitalsOnly.labs.isEmpty() && vitalsOnly.vitals.size == 2)
    }

    @Test fun highlighterMarks() {
        val marked = setOf(0, 2, ChartQuiz.questionMarks + 1)
        assertEquals("the story's marks", setOf(0, 2), ChartQuiz.marks(marked, question = false))
        assertEquals("the question's marks, from 0", setOf(1), ChartQuiz.marks(marked, question = true))
        assertEquals("marking the question leaves the story's",
            setOf(0, 2, ChartQuiz.questionMarks + 1, ChartQuiz.questionMarks + 3), ChartQuiz.merging(setOf(1, 3), question = true, into = marked))
        assertEquals("clearing the story leaves the question's",
            setOf(ChartQuiz.questionMarks + 1), ChartQuiz.merging(emptySet(), question = false, into = marked))
        assertEquals("a plain stem's marks are the story's", setOf(0, 4), ChartQuiz.marks(setOf(0, 4), question = false))
    }

    private fun mark(slot: Int, selected: Int?, checked: Boolean, exam: Boolean = false) =
        ChartQuiz.mark(slot, selected, correct = 1, checked = checked, examMode = exam)

    @Test fun options() {
        assertTrue("before checking: chosen and idle", mark(2, 2, false) == M.chosen && mark(1, 2, false) == M.idle)
        assertTrue("nothing chosen: nothing blue", (0 until 4).all { mark(it, null, false) == M.idle })
        assertTrue("checked: the right one marked, the wrong pick faded, the rest past",
            mark(1, 2, true) == M.right && mark(2, 2, true) == M.wrong && mark(0, 2, true) == M.past)
        assertTrue("a right pick is right, not wrong", mark(1, 1, true) == M.right)
        assertTrue("a timed paper never shows right or wrong",
            mark(1, 2, true, exam = true) == M.idle && mark(2, 2, true, exam = true) == M.chosen)
        assertTrue("a question with no key paints no option right",
            (0 until 4).all { ChartQuiz.mark(it, 2, correct = -1, checked = true, examMode = false) != M.right })
        assertTrue("a crossed-out option lies low", ChartQuiz.liesLow(true, M.past) && ChartQuiz.liesLow(true, M.idle))
        assertTrue("except the right answer once shown", !ChartQuiz.liesLow(true, M.right))
        assertTrue("once checked, an option neither picked nor right lies low", ChartQuiz.liesLow(false, M.past))
        assertTrue("and nothing else does",
            !ChartQuiz.liesLow(false, M.wrong) && !ChartQuiz.liesLow(false, M.idle)
                && !ChartQuiz.liesLow(false, M.chosen) && !ChartQuiz.liesLow(false, M.right))
        assertEquals("TalkBack hears right, not only colour", "Correct answer", ChartQuiz.spoken(M.right))
        assertEquals("and wrong", "Your answer, wrong", ChartQuiz.spoken(M.wrong))
        assertNull("and nothing for a choice", ChartQuiz.spoken(M.chosen))
    }

    private fun title(checked: Boolean = false, picked: Boolean = true, holding: Boolean = false, exam: Boolean = false, last: Boolean = false) =
        ChartQuiz.primaryTitle(checked, picked, holding, exam, last)

    @Test fun bar() {
        assertEquals("nothing picked says so", "Pick an answer", title(picked = false))
        assertEquals("the slow reading drill holds", "Keep reading", title(holding = true))
        assertEquals("then Check answer", "Check answer", title())
        assertEquals("checked: Next patient", "Next patient", title(checked = true))
        assertEquals("and See results on the last", "See results", title(checked = true, last = true))
        assertTrue("a paper answers and moves on", title(exam = true) == "Next patient" && title(exam = true, last = true) == "Finish paper")
        assertTrue("a paper's question can be skipped",
            title(picked = false, exam = true) == "Skip for now" && title(picked = false, exam = true, last = true) == "Finish paper")
        assertTrue("Explain once checked", ChartQuiz.explains(checked = true, examMode = false))
        assertTrue("not before, nor in a paper",
            !ChartQuiz.explains(checked = false, examMode = false) && !ChartQuiz.explains(checked = true, examMode = true))
    }

    @Test fun readings() {
        assertTrue("a flagged reading is drawn as danger",
            ChartQuiz.tone(PatientChart.Flag.high) == ChartQuiz.Tone.danger && ChartQuiz.tone(PatientChart.Flag.low) == ChartQuiz.Tone.danger
                && ChartQuiz.tone(null) == ChartQuiz.Tone.ink)
        val septic = ChartQuiz.layout("A 70-year-old woman is confused. Her blood pressure is 82/50 mmHg and oxygen saturation 89%. Lactate 4.8 mmol/L. Which is the next best step?")
        assertEquals("a vital sign is read out in words", "Blood pressure 82 over 50, low", septic.vitals.firstOrNull()?.let(ChartQuiz::spoken))
        assertEquals("saturation by name", "Oxygen saturation 89%, low", septic.vitals.lastOrNull()?.let(ChartQuiz::spoken))
        assertEquals("a result with its unit and flag", "Albumin 22 g/L, low", full.labs.firstOrNull()?.let(ChartQuiz::spoken))
        assertEquals("a normal reading has no flag word", "Blood pressure 128 over 82", full.vitals.firstOrNull()?.let(ChartQuiz::spoken))
    }
}
