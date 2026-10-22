package com.stethoscore.app.quiz

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// A port of ios/RedPen/Tests/PatientChartTests.swift, case for case.
// A question's stem read as a patient's chart: only what the stem says, the
// flags from the accuracy check's own reference ranges, and a stem with no
// observations left as it was.
class PatientChartTest {
    @Test fun nephrotic() {
        val nephrotic = "A 34-year-old man presents with swelling of his legs and face for 3 weeks. BP 128/82 mmHg, HR 76/min, temperature 36.8 °C, SpO2 98% on air. Investigations show albumin 22 g/L, cholesterol 8.1 mmol/L and creatinine 88 µmol/L. Urinalysis shows 4+ protein and no blood. What is the most likely diagnosis?"
        val chart = PatientChart.read(nephrotic)
        assertEquals("who: age, sex and how long", listOf("34 y", "Male", "3 wk"), chart.chips)
        assertEquals("the vitals, in the stem's order", listOf("BP 128/82", "HR 76", "Temp 36.8 °C", "SpO2 98%"), chart.vitals.map { it.label + " " + it.value })
        assertTrue("normal vitals carry no flag", chart.vitals.all { it.flag == null })
        assertEquals("the results, as written", listOf("Albumin 22 g/L", "Cholesterol 8.1 mmol/L", "Creatinine 88 µmol/L"),
            chart.labs.map { it.name + " " + it.value + " " + it.unit })
        assertEquals("low albumin is L, from the check's own range", PatientChart.Flag.low, chart.labs.firstOrNull()?.flag)
        assertNull("a result the range table does not know is not guessed", chart.labs[1].flag)
        assertNull("normal creatinine carries no flag", chart.labs[2].flag)
        assertEquals("the question is pulled out", "What is the most likely diagnosis?", chart.question)
        assertEquals("the story keeps what the chart does not show, and drops the lists it does",
            "A 34-year-old man presents with swelling of his legs and face for 3 weeks. Urinalysis shows 4+ protein and no blood.", chart.story)
    }

    @Test fun septic() {
        val septic = "A 70-year-old woman is confused. Her blood pressure is 82/50 mmHg, pulse 124 beats per minute, respiratory rate 28/min, temperature 39.2°C and oxygen saturation 89%. Lactate 4.8 mmol/L. Which is the next best step?"
        val s = PatientChart.read(septic)
        assertEquals("abnormal vitals are flagged", listOf("BPL", "HRH", "RRH", "TempH", "SpO2L"), s.vitals.map { it.label + (it.flag?.rawValue ?: "-") })
        assertEquals("a high lactate is H", "Lactate H", s.labs.firstOrNull()?.let { it.name + " " + (it.flag?.rawValue ?: "-") })
        assertEquals("she is Female", listOf("70 y", "Female"), s.chips)
    }

    @Test fun plainAndMixed() {
        val plain = "Which nerve supplies the deltoid muscle?"
        val p = PatientChart.read(plain)
        assertTrue("a recall question has nothing to chart", !p.hasObservations && p.chips.isEmpty())
        assertTrue("and stays the question it was", p.question == plain && p.story.isEmpty())

        val mixed = "On examination his BP is 150/95 mmHg and he has bilateral pitting oedema. What is the next step?"
        val m = PatientChart.read(mixed)
        assertTrue("a sentence with more than numbers stays in the story: ${m.story}", m.story.contains("bilateral pitting oedema"))
        assertEquals("its reading still reaches the grid", "150/95H", m.vitals.firstOrNull()?.let { it.value + (it.flag?.rawValue ?: "") })
    }

    @Test fun edges() {
        val d = PatientChart.read("She was given 0.5 mg adrenaline. Potassium 6.8 mmol/L. What next?")
        assertEquals("a decimal does not split a sentence", "She was given 0.5 mg adrenaline.", d.story)
        assertEquals("high potassium is H", "H", d.labs.firstOrNull()?.let { it.flag?.rawValue ?: "-" })
        assertTrue("a pulseless rhythm is not read as a pulse", PatientChart.read("He is pulseless with a rate of 40. What now?").vitals.isEmpty())
        assertEquals("a child's age in months", listOf("8 mo", "Male"), PatientChart.read("An 8-month-old boy has a fever of 38.9 °C.").chips)
        assertTrue("a pregnant woman says so", PatientChart.read("A 28-year-old pregnant woman, 32 weeks.").chips.contains("Pregnant"))
        assertEquals("a stem with no question and nothing to chart is shown whole", "Nephrotic syndrome.", PatientChart.read("Nephrotic syndrome.").story)
    }
}
