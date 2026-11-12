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
// says what happened and that the checkers are on the rest. The tests after
// the first MARK are not in the iOS file: they pin the two tables, the empty
// case and what its checks leave open (counting by reason, the first breaking
// hit, what holds an item) in VerificationScreen.swift itself.
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

    // MARK: pins from the independent check (attempt 2): what the iOS checks leave open

    private fun q(stem: String, options: List<String>, key: Int, explanation: String = "") =
        MCQQuestion(stem = stem, options = options, correctIndex = key, explanation = explanation)

    // the same reason met twice is one entry with count 2
    @Test fun sameReasonTwiceIsCountedTwice() {
        val a = q("Which nerve supplies deltoid?", listOf("Axillary", "Radial", "Ulnar", "Median"), 7)
        val b = q("Which nerve supplies biceps?", listOf("Musculocutaneous", "Radial", "Ulnar", "Median"), 9)
        val c = q("Which tissue?", listOf("w", "x", "y", "z"), 0, "Ans-b. The second.")
        val d = q("Which gland?", listOf("Thyroid", "Adrenal", "Pituitary", "Pineal"), 0, "Thyroid is not the correct answer.")
        val out = VerificationScreen.questions(listOf(a, c, b, d))
        assertEquals(4, out.removedCount)
        assertEquals(listOf("no answer key", "key contradicted by its explanation"), out.removed.map { it.reason })
        assertEquals(listOf(2, 2), out.removed.map { it.count })
        assertEquals(" On-device checks: 4 removed (2 no answer key, 2 key contradicted by its explanation). The independent checkers are verifying the rest now.",
            VerificationScreen.note(out))
    }

    // the first breaking hit names the reason (duplicate-option is met before key-explanation-conflict)
    @Test fun theFirstBreakingHitNamesTheReason() {
        val both = q("Which infection?", listOf("Measles", "Rubella", "Measles", "Mumps"), 0, "Ans-b. The second.")
        val out = VerificationScreen.questions(listOf(both))
        assertEquals(listOf("two identical correct options"), out.removed.map { it.reason })
    }

    // a minor hit alone does not hold an item
    @Test fun aMinorHitDoesNotHold() {
        val minor = q("Which are causes of hypoglycaemia?", listOf("Insulin", "Sulfonylureas", "All of the above", "None of the above"), 0, "")
        val out = VerificationScreen.questions(listOf(minor))
        assertEquals(1, out.kept.size)
        assertEquals(0, out.held)
        assertEquals(" On-device checks passed. The independent checkers are verifying the rest now.", VerificationScreen.note(out))
    }

    // a card with a red flag is held
    @Test fun aRedFlagCardIsHeld() {
        val card = AnkiCard(type = AnkiCardType.QA, front = "Which drug is given in asystole?", bullets = listOf("Atropine 3 mg IV for asystole"))
        val out = VerificationScreen.cards(listOf(card))
        assertEquals(1, out.kept.size)
        assertEquals(1, out.held)
    }
}
