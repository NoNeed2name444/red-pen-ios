package com.stethoscore.app.llm

import com.stethoscore.app.llm.GenerationRules.Admission
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

// A port of ios/RedPen/Tests/GenerationRulesTests.swift, check for check: a
// new generation never stops the one running, it is refused with words that
// say what is running and how to stop it; closing a screen stops only what
// that screen started (audit #94); a late end leaves a newer run alone (#68).
class GenerationRulesTest {
    private fun refusal(a: Admission): String? = (a as? Admission.Refuse)?.why

    @Test fun withNothingRunningAGenerationStarts() {
        assertEquals(Admission.Start, GenerationRules.admit(null))
    }

    @Test fun withOneRunningANewOneIsRefusedInWords() {
        val questions = GenerationRules.admit("Writing 40 questions")
        assertNotEquals(Admission.Start, questions)
        val said = refusal(questions) ?: ""
        assertTrue(said, said.contains("Still writing 40 questions"))
        assertTrue("and how to stop it", said.contains("Cancel"))
        assertFalse("the title is not repeated", said.contains("Writing Writing"))
        assertEquals("Still writing 40 questions — wait for it to finish, or tap Cancel on its card, then try again.", said)
        assertEquals("asking twice gives the same answer", questions, GenerationRules.admit("Writing 40 questions"))
    }

    @Test fun everyWritingTitleIsNamed() {
        for (title in listOf("Writing 12 cards", "Writing 1 page", "Writing 3 stations", "Writing 5 duels")) {
            val why = refusal(GenerationRules.admit(title)) ?: ""
            assertTrue("$title: $why", why.startsWith("Still writing " + title.removePrefix("Writing ")))
        }
    }

    @Test fun oddAndEmptyTitlesStillRefuseInPlainWords() {
        val odd = refusal(GenerationRules.admit("Checking 40 questions")) ?: ""
        assertTrue(odd, odd.contains("checking 40 questions"))
        val blank = refusal(GenerationRules.admit("  ")) ?: ""
        assertTrue(blank, blank.isNotEmpty() && blank.contains("Something else is being written"))
        val bare = refusal(GenerationRules.admit("Writing ")) ?: ""
        assertTrue(bare, bare.isNotEmpty() && !bare.contains("Still writing —"))
    }

    @Test fun closingAScreenStopsOnlyWhatItStarted() {
        val mine = UUID.randomUUID()
        val other = UUID.randomUUID()
        assertTrue(GenerationRules.closingStops(mine, mine))
        assertFalse(GenerationRules.closingStops(other, mine))
        assertFalse(GenerationRules.closingStops(null, mine))
    }

    @Test fun aCancelledRunEndingLateLeavesTheNewOneAlone() {
        val cancelled = UUID.randomUUID()
        val now = UUID.randomUUID()
        assertFalse(GenerationRules.endingClears(cancelled, now))
        assertTrue(GenerationRules.endingClears(now, now))
        assertFalse(GenerationRules.endingClears(cancelled, null))
    }
}
