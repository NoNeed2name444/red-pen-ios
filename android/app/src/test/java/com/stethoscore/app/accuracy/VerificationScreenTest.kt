package com.stethoscore.app.accuracy

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// ios/RedPen/Tests/VerificationScreenTests.swift, check for check: the
// verification layer's first stage on generated material. A broken item is
// removed with its reason, a red flag is kept and held, and the status line
// says what happened and that the checkers are on the rest. The last four
// tests are not in the iOS file: they pin the two tables and the empty case
// of VerificationScreen.swift itself.
class VerificationScreenTest {

    private val good = MCQQuestion(stem = "First-line drug for absence seizures?", options = listOf("Ethosuximide", "Phenytoin", "Carbamazepine", "Gabapentin"),
        correctIndex = 0, explanation = "Ethosuximide is first line for absence seizures.")
    private val noKey = MCQQuestion(stem = "Which nerve supplies deltoid?", options = listOf("Axillary", "Radial", "Ulnar", "Median"), correctIndex = 7, explanation = "")
    private val contradicted = MCQQuestion(stem = "Which tissue?", options = listOf("w", "x", "y", "z"), correctIndex = 0, explanation = "Ans-b. The second.")
    private val copiedKey = MCQQuestion(stem = "Which infection?", options = listOf("Measles", "Rubella", "Measles", "Mumps"), correctIndex = 0, explanation = "")
    private val outdated = MCQQuestion(stem = "The monitor shows asystole. CPR is started. Which drug should be given next?",
        options = listOf("Adrenaline 1 mg IV", "Atropine 3 mg IV", "Amiodarone 300 mg IV", "Lidocaine"), correctIndex = 1, explanation = "")

    private val outcome = VerificationScreen.questions(listOf(good, noKey, contradicted, copiedKey, outdated))

    @Test fun aSoundQuestionIsKept() {
        assertTrue("a sound question is kept", outcome.kept.any { it.id == good.id })
    }

    @Test fun aQuestionWithNoKeyIsRemoved() {
        assertFalse("a question with no key is removed", outcome.kept.any { it.id == noKey.id })
    }

    @Test fun oneItsExplanationContradictsIsRemoved() {
        assertFalse("one its explanation contradicts is removed", outcome.kept.any { it.id == contradicted.id })
    }

    @Test fun oneWhoseKeyIsCopiedIntoADistractorIsRemoved() {
        assertFalse("one whose key is copied into a distractor is removed", outcome.kept.any { it.id == copiedKey.id })
    }

    @Test fun aRetiredPracticeKeyIsKeptButHeldForTheCheckers() {
        assertTrue("a retired-practice key is kept but held for the checkers", outcome.kept.any { it.id == outdated.id } && outcome.held == 1)
    }

    @Test fun removalsAreCountedByReason() {
        assertEquals(3, outcome.removedCount)
        assertEquals("removals are counted by reason, in the order first met",
            listOf("no answer key", "key contradicted by its explanation", "two identical correct options"), outcome.removed.map { it.reason })
        assertEquals(listOf(1, 1, 1), outcome.removed.map { it.count })
        assertEquals("kept, in the order they came", listOf(good.id, outdated.id), outcome.kept.map { it.id })
    }

    @Test fun theNoteSaysWhatHappenedAndWhatComesNext() {
        assertEquals("the note says what happened and what comes next",
            " On-device checks: 3 removed (1 no answer key, 1 key contradicted by its explanation, 1 two identical correct options); 1 held for a red flag. The independent checkers are verifying the rest now.",
            VerificationScreen.note(outcome))
    }

    @Test fun aCleanSetSaysItPassed() {
        assertEquals("a clean set says it passed", " On-device checks passed. The independent checkers are verifying the rest now.",
            VerificationScreen.note(VerificationScreen.questions(listOf(good))))
    }

    @Test fun nothingMadeNothingSaid() {
        assertEquals("nothing made, nothing said", "", VerificationScreen.note(VerificationScreen.questions(emptyList())))
    }

    @Test fun aStationIsNeverRemovedOnlyHeld() {
        val station = OsceChecklist(title = "Cardiac arrest", steps = listOf("Start CPR", "Give atropine 3 mg for asystole", "Attach the defibrillator"))
        val stations = VerificationScreen.stations(listOf(station))
        assertTrue("a station is never removed, only held", stations.kept.size == 1 && stations.held == 1)
    }

    @Test fun aSoundCardIsKept() {
        val card = AnkiCard(type = AnkiCardType.QA, front = "Antidote to heparin?", bullets = listOf("Protamine sulfate"))
        val cards = VerificationScreen.cards(listOf(card))
        assertTrue("a sound card is kept", cards.kept.size == 1 && cards.held == 0)
    }

    // MARK: not in the iOS file

    @Test fun onlyTheBrokenRulesRemoveAnItem() {
        fun hit(rule: String, severity: String) = AccuracyRules.Hit(rule, severity, "")
        for (rule in listOf("no-key", "key-explanation-conflict", "key-called-wrong", "all-above-contradiction")) {
            assertTrue("$rule breaks an item", VerificationScreen.breaks(hit(rule, "severe")))
        }
        assertTrue("a duplicate that is the key breaks it", VerificationScreen.breaks(hit("duplicate-option", "severe")))
        assertFalse("a duplicate between distractors does not", VerificationScreen.breaks(hit("duplicate-option", "minor")))
        for (rule in listOf("dose-range", "look-alike-drug", "outdated-practice", "lab-implausible", "reference-range", "non-answer-position")) {
            assertFalse("$rule only holds an item, it never removes one", VerificationScreen.breaks(hit(rule, "severe")))
        }
    }

    @Test fun eachReasonIsPutInWords() {
        assertEquals("no answer key", VerificationScreen.reason("no-key"))
        assertEquals("key contradicted by its explanation", VerificationScreen.reason("key-explanation-conflict"))
        assertEquals("key contradicted by its explanation", VerificationScreen.reason("key-called-wrong"))
        assertEquals("two identical correct options", VerificationScreen.reason("duplicate-option"))
        assertEquals("contradictory “of the above” options", VerificationScreen.reason("all-above-contradiction"))
        assertEquals("a rule with no wording is named as it is", "some-other-rule", VerificationScreen.reason("some-other-rule"))
    }

    @Test fun anAllOfTheAboveKeyBesideNoneOfTheAboveIsRemovedWithItsOwnReason() {
        val both = MCQQuestion(stem = "Which are causes of hypoglycaemia?", options = listOf("Insulin", "Sulfonylureas", "All of the above", "None of the above"),
            correctIndex = 2, explanation = "")
        val screened = VerificationScreen.questions(listOf(both))
        assertTrue(screened.kept.isEmpty())
        assertEquals(listOf("contradictory “of the above” options"), screened.removed.map { it.reason })
    }

    @Test fun aCardWithNothingToCheckIsKept() {
        // an image-occlusion card with no words gives no AccuracyItem: nothing to check, so it stays
        val picture = AnkiCard(type = AnkiCardType.OCCLUSION, front = "")
        val screened = VerificationScreen.cards(listOf(picture))
        assertEquals(1, screened.kept.size)
        assertEquals(0, screened.held)
        assertEquals("", VerificationScreen.note(VerificationScreen.Outcome<AnkiCard>()))
    }
}
