package com.stethoscore.app.llm

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyKind
import com.stethoscore.app.accuracy.AccuracyRules
import com.stethoscore.app.data.MCQQuestion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T0234: MCQRepair, ported from iOS Shared/MCQRepair.swift, case for case from
 * ios/RedPen/Tests/MCQRepairTests.swift. One Kotlin test per iOS check; the
 * iOS line it comes from is in the comment above each (lines are in
 * MCQRepairTests.swift). Where a check reads several values, so does its test.
 *
 * An explanation that names an option by its place is rewritten to name it by
 * its words, since the options are shown shuffled. Every reference form a
 * model writes is caught and resolves to the option it meant; clinical
 * English that only looks like a reference is left alone; and an explanation
 * that contradicts the key is left for the accuracy rules to flag.
 */
class MCQRepairTest {

    private val options = listOf("Aspirin", "Morphine", "Oxygen", "Nitrates", "Furosemide")

    /** The explanation rewritten for a question keyed on Aspirin. */
    private fun fixed(text: String, key: Int = 0, opts: List<String> = options): MCQRepair.Result =
        MCQRepair.rewrite(text, opts, key)

    private fun expect(text: String, want: String, count: Int = 1, key: Int = 0) {
        val got = fixed(text, key)
        assertEquals(want, got.text)
        assertEquals(count, got.rewritten)
    }

    private fun untouched(text: String) {
        val got = fixed(text)
        assertEquals(text, got.text)
        assertEquals(0, got.rewritten)
    }

    // MARK: every reference form, and the option it meant

    // :34 option C is Oxygen
    @Test fun optionCIsOxygen() =
        expect("Option C is wrong because it does not reduce mortality.", "\"Oxygen\" is wrong because it does not reduce mortality.")

    // :38 choice B is B, not the c of choice
    @Test fun choiceBIsBNotTheCOfChoice() = expect("Choice B relieves pain only.", "\"Morphine\" relieves pain only.")

    // :39 the option B is B, not the e of the
    @Test fun theOptionBIsBNotTheEOfThe() = expect("The option B relieves pain only.", "\"Morphine\" relieves pain only.")

    // :40 answer B is B, not the a of answer
    @Test fun answerBIsBNotTheAOfAnswer() = expect("Answer B is tempting.", "\"Morphine\" is tempting.")

    // :41 the correct answer is A keeps its words
    @Test fun theCorrectAnswerIsAKeepsItsWords() =
        expect("The correct answer is A because it reduces mortality.", "The correct answer is \"Aspirin\" because it reduces mortality.")

    // :43 Answer: (A)
    @Test fun answerColonParenA() = expect("Answer: (A). Aspirin reduces mortality.", "Answer: \"Aspirin\". Aspirin reduces mortality.")

    // :44 the answer is option A
    @Test fun theAnswerIsOptionA() = expect("The answer is option A.", "The answer is \"Aspirin\".")

    // :45 options B and C
    @Test fun optionsBAndC() =
        expect("Options B and C relieve symptoms only.", "\"Morphine\" and \"Oxygen\" relieve symptoms only.", count = 2)

    // :47 options B, C or D
    @Test fun optionsBCOrD() =
        expect("options B, C or D are symptomatic.", "\"Morphine\", \"Oxygen\" or \"Nitrates\" are symptomatic.", count = 3)

    // :49 option 2 counts from 1
    @Test fun option2CountsFrom1() = expect("Option 2 is symptomatic.", "\"Morphine\" is symptomatic.")

    // :50 option 3 before a comma
    @Test fun option3BeforeAComma() = expect("Unlike option 3, aspirin reduces mortality.", "Unlike \"Oxygen\", aspirin reduces mortality.")

    // :51 the second option
    @Test fun theSecondOption() = expect("The second option is symptomatic.", "\"Morphine\" is symptomatic.")

    // :52 the last option
    @Test fun theLastOption() = expect("The last option is a diuretic.", "\"Furosemide\" is a diuretic.")

    // :53 several in one explanation
    @Test fun severalInOneExplanation() = expect(
        "Option A reduces mortality; option B and the third option do not.",
        "\"Aspirin\" reduces mortality; \"Morphine\" and \"Oxygen\" do not.", count = 3)

    // MARK: what only looks like a reference

    // :58 the drug of choice a decade ago
    @Test fun theDrugOfChoiceADecadeAgo() = untouched("It was the drug of choice a decade ago.")

    // :59 option 0 is not the last option
    @Test fun option0IsNotTheLastOption() = untouched("Option 0 is wrong.")

    // :60 the answer 2 hours later
    @Test fun theAnswer2HoursLater() = untouched("Give the answer 2 hours later.")

    // :61 the drug of choice 2 weeks after
    @Test fun theDrugOfChoice2WeeksAfter() = untouched("Drug of choice 2 weeks after the event.")

    // :62 the second choice after metformin
    @Test fun theSecondChoiceAfterMetformin() = untouched("The second choice after metformin is a sulfonylurea.")

    // :63 the first option for hypertension
    @Test fun theFirstOptionForHypertension() = untouched("The first option for hypertension is a thiazide.")

    // :64 the first choice drug
    @Test fun theFirstChoiceDrug() = untouched("The first choice drug is aspirin.")

    // :65 a letter the question does not have
    @Test fun aLetterTheQuestionDoesNotHave() = untouched("Option F is not here.")

    // :66 a list with a letter the question does not have
    @Test fun aListWithALetterTheQuestionDoesNotHave() = untouched("Options B and F are wrong.")

    // :67 C. difficile is not option C
    @Test fun cDifficileIsNotOptionC() = untouched("The antibiotic of choice C. difficile needs is vancomycin.")

    // :68 vitamin B12 and hepatitis B
    @Test fun vitaminB12AndHepatitisB() = untouched("Vitamin B12 is unrelated; hepatitis B too.")

    // :69 a hyphenated word after option
    @Test fun aHyphenatedWordAfterOption() = untouched("Option B-blockers are unrelated.")

    // :70 a decimal after option
    @Test fun aDecimalAfterOption() = untouched("Option 2.5 mg is a dose.")

    // :71 an explanation already by content
    @Test fun anExplanationAlreadyByContent() = untouched("Aspirin reduces mortality; morphine only relieves pain.")

    // :72 a four-option question has no option E
    @Test fun aFourOptionQuestionHasNoOptionE() =
        assertEquals(0, fixed("Option E is wrong.", opts = options.take(4)).rewritten)

    // MARK: the names it writes

    // :77 a clause is cut off the name
    @Test fun aClauseIsCutOffTheName() =
        assertEquals("Metformin", MCQRepair.shortName("Metformin, which lowers hepatic glucose output"))

    // :78 with as a word, not inside withdrawal
    @Test fun withAsAWordNotInsideWithdrawal() =
        assertEquals("Alcohol withdrawal delirium", MCQRepair.shortName("Alcohol withdrawal delirium"))

    // :81 never ends on a dangling word
    @Test fun neverEndsOnADanglingWord() =
        assertEquals("The malar rash is chronic", MCQRepair.shortName("The malar rash is chronic and spreads across the face"))

    // :84 a full stop is not part of the name
    @Test fun aFullStopIsNotPartOfTheName() = assertEquals("Aspirin", MCQRepair.shortName("Aspirin."))

    private val lookalikes = listOf("Hyperkalaemia with peaked T waves", "Hyperkalaemia with flattened T waves", "Hyponatraemia", "Hypocalcaemia")

    // :87 look-alike options keep their whole words
    @Test fun lookAlikeOptionsKeepTheirWholeWords() = assertEquals(lookalikes, MCQRepair.shortNames(lookalikes))

    // :90 so a reference to one is not a reference to both
    @Test fun soAReferenceToOneIsNotAReferenceToBoth() {
        val alike = MCQRepair.rewrite("Option B is wrong: the T waves flatten.", lookalikes, 0)
        assertEquals("\"Hyperkalaemia with flattened T waves\" is wrong: the T waves flatten.", alike.text)
    }

    // MARK: a key the explanation contradicts stays visible

    private val wrongKey = "Option C is correct because oxygen helps."

    // :96 an explanation naming another answer is left as written
    @Test fun anExplanationNamingAnotherAnswerIsLeftAsWritten() {
        val got = fixed(wrongKey, key = 1)
        assertEquals(wrongKey, got.text)
        assertEquals(0, got.rewritten)
    }

    // :99 and the accuracy rules still flag it
    @Test fun andTheAccuracyRulesStillFlagIt() {
        val stored = MCQRepair.repaired(MCQQuestion(stem = "Which drug reduces mortality first?", options = options, correctIndex = 1, explanation = wrongKey))
        val item = AccuracyItem("q", AccuracyKind.mcq, stem = stored.stem, options = stored.options, key = 1, explanation = stored.explanation)
        assertTrue(AccuracyRules.hits(item).map { it.rule }.toString(), AccuracyRules.hits(item).any { it.rule == "key-explanation-conflict" })
    }

    // :106 an explanation agreeing with the key is rewritten
    @Test fun anExplanationAgreeingWithTheKeyIsRewritten() =
        expect("Option B is correct; option C does not help.", "\"Morphine\" is correct; \"Oxygen\" does not help.", count = 2, key = 1)

    // MARK: the question as stored

    // :111 a repaired question keeps everything but the explanation
    @Test fun aRepairedQuestionKeepsEverythingButTheExplanation() {
        val question = MCQQuestion(stem = "Which drug reduces mortality first?", options = options, correctIndex = 0,
            explanation = "Option A reduces mortality.", tags = listOf("cardiology"), rawJson = "{\"differential\":{}}")
        val repaired = MCQRepair.repaired(question)
        assertEquals(question.id, repaired.id)
        assertEquals(question.options, repaired.options)
        assertEquals(0, repaired.correctIndex)
        assertEquals("\"Aspirin\" reduces mortality.", repaired.explanation)
        assertEquals(question.copy(explanation = repaired.explanation), repaired)
    }

    // :117 an empty explanation stays empty
    @Test fun anEmptyExplanationStaysEmpty() {
        assertEquals("", fixed("").text)
        assertEquals(0, fixed("").rewritten)
    }
}
