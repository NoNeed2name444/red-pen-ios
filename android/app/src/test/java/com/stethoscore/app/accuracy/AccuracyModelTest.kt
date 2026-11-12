package com.stethoscore.app.accuracy

import com.stethoscore.app.exam.ExamCatalog
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.exam.MemoryExamDefaults
import com.stethoscore.app.quiz.ExamTrack
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.exp

// The accuracy model: the cases of ios/RedPen/Tests/AccuracyTests.swift
// "MARK: the model" (lines 68-210) and the vignette route's grade cases
// (V8, V9, V11, V12), ExamCatalogTests.swift's "stricter for management
// questions" (274-298) and AccuracyFix's canApply cases (436-437), case for
// case; the weights' JSON; and a check that the numbers kept in the app are the
// server's (server/accuracy-model.js). Each test names the iOS line it ports.
class AccuracyModelTest {

    private fun solve(model: String, answer: String, evidence: String = "supports") =
        AccuracyVote(model = model, risk = 1, answer = answer, evidence = evidence, blind = true)

    private val gModel = "gemini-3.5-flash-lite"
    private val gmModel = "gemma-4-31b-it"
    private val oModel = "@cf/openai/gpt-oss-120b"
    private val nModel = "@cf/nvidia/nemotron-3-120b-a12b"

    private fun mcqVotes(votes: List<AccuracyVote>, rules: List<AccuracyRules.Hit> = emptyList()) =
        AccuracyModel.featureValues(AccuracyKind.mcq, rules, votes, 3, 0.7, "A")

    private fun gradeOf(f: Map<String, Double>) = AccuracyModel.grade(AccuracyModel.probability(f), f)

    private val three = listOf(solve(gModel, "A"), solve(oModel, "A"), solve(nModel, "A"))
    private val pass = AccuracyModel.featureValues(AccuracyKind.mcq, emptyList(), three, 3, 0.7, "A", sourceProof = true)
    private val p1 = AccuracyModel.probability(pass)

    // :70
    @Test fun verifiedNeedsThreeModelFamilies() = assertEquals(3, AccuracyModel.minVerifyVoters)

    // :78
    @Test fun threeBlindSolvesFromThreeFamiliesProvenByAnOfficialSourceAreVerified() {
        assertTrue("$p1", p1 > 0.95 && AccuracyModel.grade(p1, pass) == AccuracyGrade.verified)
    }

    // :81-83
    @Test fun theSameVotesWithNoOfficialSourceAreCheckThisAndTheScoreIsUnchanged() {
        val unproven = AccuracyModel.featureValues(AccuracyKind.mcq, emptyList(), three, 3, 0.7, "A")
        assertTrue(unproven["source_proof"] == 0.0 && pass["source_proof"] == 1.0)
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(p1, unproven))
        assertEquals(p1, AccuracyModel.probability(unproven), 0.0)
    }

    // :88-89
    @Test fun twoBlindFamiliesOnTheKeyAreNoLongerEnough() = assertEquals(AccuracyGrade.check, gradeOf(mcqVotes(listOf(solve(gModel, "A"), solve(oModel, "A")))))

    // :90-92
    @Test fun aFamilyWhoseBlindSolveWentElsewhereKeepsItFromVerified() {
        val f = mcqVotes(listOf(solve(gModel, "A"), solve(gmModel, "C"), solve(oModel, "A"), solve(nModel, "A")))
        assertTrue(f["blind_agree"] == 3.0 && f["blind_dissent"] == 1.0)
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, f))
    }

    // :93-94
    @Test fun aConcernFromAnyCheckerKeepsItFromVerified() {
        val f = mcqVotes(three + AccuracyVote(model = oModel, risk = 3, answer = "A", evidence = "none"))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, f))
    }

    // :95-96
    @Test fun literatureReadAgainstItKeepsItFromVerified() {
        val f = mcqVotes(listOf(solve(gModel, "A", evidence = "contradicts"), solve(oModel, "A"), solve(nModel, "A")))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, f))
    }

    // :97-100
    @Test fun votesThatSawTheKeyDoNotVerifyAQuestion() {
        val f = mcqVotes(listOf(gModel, oModel, nModel).map { AccuracyVote(model = it, risk = 1, answer = "A", evidence = "supports") })
        assertEquals(AccuracyGrade.check, gradeOf(f))
    }

    // :101-104
    @Test fun threeFamiliesSolvingItBlindOnAnotherAnswerAndNoneOnTheKeyFlagIt() {
        val f = mcqVotes(listOf(solve(gModel, "C", "none"), solve(oModel, "C", "none"), solve(nModel, "C", "none"),
            AccuracyVote(model = gmModel, risk = 1, answer = "A", evidence = "supports")))
        assertTrue(f["blind_against"] == 3.0)
        assertEquals(AccuracyGrade.flagged, gradeOf(f))
    }

    // :105-106
    @Test fun twoFamiliesOnAnotherAnswerAreNotProofEnoughToFlag() =
        assertEquals(AccuracyGrade.check, gradeOf(mcqVotes(listOf(solve(gModel, "C", "none"), solve(oModel, "C", "none")))))

    // :107-108
    @Test fun twoFamiliesOnAnotherAnswerAndOneOnTheKeyAreCheckThis() =
        assertEquals(AccuracyGrade.check, gradeOf(mcqVotes(listOf(solve(gModel, "C", "none"), solve(oModel, "C", "none"), solve(nModel, "A")))))

    // :109-111
    @Test fun twoBlindSolvesFromOneFamilyAreOneWitness() {
        val f = mcqVotes(listOf(solve(gModel, "A"), solve(gmModel, "A")))
        assertTrue(f["blind_agree"] == 1.0)
        assertEquals(AccuracyGrade.check, gradeOf(f))
    }

    private fun cardVotes(risk: Int, evidence: String, vararg models: String) =
        AccuracyModel.featureValues(AccuracyKind.card, emptyList(), models.map { AccuracyVote(model = it, risk = risk, evidence = evidence) }, 0, 0.7, null)

    // :112-116
    @Test fun threeFamiliesJudgingACardWrongFlagIt() {
        val f = cardVotes(4, "contradicts", gModel, oModel, nModel)
        assertTrue(f["flag_families"] == 3.0)
        assertEquals(AccuracyGrade.flagged, gradeOf(f))
    }

    // :117-120
    @Test fun twoFamiliesJudgingItWrongAreCheckThis() = assertEquals(AccuracyGrade.check, gradeOf(cardVotes(4, "contradicts", gModel, oModel)))

    // :121-125
    @Test fun threePassingFamiliesVerifyACardAnOfficialSourceStates() {
        val f = AccuracyModel.featureValues(AccuracyKind.card, emptyList(),
            listOf(gModel, oModel, nModel).map { AccuracyVote(model = it, risk = 1, evidence = "supports") }, 3, 0.9, null, sourceProof = true)
        assertTrue(f["families"] == 3.0)
        assertEquals(AccuracyGrade.verified, AccuracyModel.grade(0.99, f))
    }

    // :126-127
    @Test fun theBlindMarkComesFromTheServersReply() {
        val vote = AccuracyVote.fromJson(JSONObject("""{"model":"m","risk":1,"answer":"A","blind":true}"""))
        assertEquals(true, vote?.blind)
    }

    // :129-133
    @Test fun threePassingVotesFromTwoFamiliesAreCheckThis() {
        val f = AccuracyModel.featureValues(AccuracyKind.card, emptyList(),
            listOf(gModel, gmModel, oModel).map { AccuracyVote(model = it, risk = 1, evidence = "supports") }, 3, 0.9, null)
        assertTrue(f["families"] == 2.0)
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, f))
    }

    // :134-136
    @Test fun aModelIdMapsToItsMakersFamily() {
        assertEquals("google", AccuracyModel.familyOf("gemma-4-31b-it"))
        assertEquals("openai", AccuracyModel.familyOf("@cf/openai/gpt-oss-120b"))
        assertEquals("nvidia", AccuracyModel.familyOf("@cf/nvidia/nemotron-3-120b-a12b"))
        assertEquals("unknown", AccuracyModel.familyOf(""))
        assertEquals("some-new-model", AccuracyModel.familyOf("Some-New-Model"))
    }

    // :137-140
    @Test fun checkersShownTheKeyCallingItWrongWithNoBlindSolveAreCheckThisNotProof() {
        val f = AccuracyModel.featureValues(AccuracyKind.mcq, emptyList(),
            listOf(AccuracyVote(risk = 4, answer = "B", evidence = "contradicts"), AccuracyVote(risk = 4, answer = "B", evidence = "contradicts")), 0, 0.7, "A")
        assertEquals(AccuracyGrade.check, gradeOf(f))
    }

    // :141-143
    @Test fun aSplitVoteIsCheckThis() {
        val f = AccuracyModel.featureValues(AccuracyKind.mcq, emptyList(), listOf(AccuracyVote(risk = 1, answer = "A"), AccuracyVote(risk = 3, answer = "A")), 0, 0.5, "A")
        assertEquals(AccuracyGrade.check, gradeOf(f))
    }

    // :144-145
    @Test fun rulesAloneNeverVerify() =
        assertEquals(AccuracyGrade.unchecked, gradeOf(AccuracyModel.featureValues(AccuracyKind.card, emptyList(), emptyList(), 0, null, null)))

    private val severe = listOf(AccuracyRules.Hit("dose-range", "severe", ""))

    // :146-148
    @Test fun aSevereRuleWithNoModelIsFlagged() =
        assertEquals(AccuracyGrade.flagged, gradeOf(AccuracyModel.featureValues(AccuracyKind.card, severe, emptyList(), 0, null, null)))

    // :149-151
    @Test fun aSevereRuleIsNeverVerified() {
        val f = AccuracyModel.featureValues(AccuracyKind.card, severe, listOf(AccuracyVote(risk = 1, evidence = "supports"), AccuracyVote(risk = 1, evidence = "supports")), 5, 1.0, null)
        assertTrue(gradeOf(f) != AccuracyGrade.verified)
    }

    // :154-156
    @Test fun aSingleVoteHoweverSureIsCheckThisNeverVerified() {
        val f = AccuracyModel.featureValues(AccuracyKind.card, emptyList(), listOf(AccuracyVote(risk = 1, evidence = "supports")), 3, 0.9, null)
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, f))
    }

    private fun cardOf(sourceMatch: Double, evidenceCount: Int, ev: List<String>, proof: Boolean = false) =
        AccuracyModel.featureValues(AccuracyKind.card, emptyList(),
            listOf(gModel, oModel, nModel).zip(ev).map { (m, e) -> AccuracyVote(model = m, risk = 1, evidence = e) }, evidenceCount, sourceMatch, null, sourceProof = proof)

    // :157-161
    @Test fun anyItemPassedByThreeFamiliesWithNoOfficialSourceStatingItStaysCheckThis() {
        val f = AccuracyModel.featureValues(AccuracyKind.card, emptyList(),
            listOf(gmModel, nModel, oModel).map { AccuracyVote(model = it, risk = 1, evidence = "none") }, 0, 0.2, null)
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, f))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, f, oath = true))
    }

    // :162-170
    @Test fun theLiteratureOrItsOwnLectureBehindItIsNoLongerProof() {
        val literature = cardOf(0.2, 2, listOf("supports", "none", "none"))
        val lecture = cardOf(AccuracyModel.oathSourceMatch, 0, listOf("none", "none", "none"))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, literature, oath = true))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, lecture, oath = true))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.99, literature))
    }

    // :171-174
    @Test fun anOathItemAnOfficialSourceStatesWordForWordCanBeVerified() {
        val proven = cardOf(0.2, 0, listOf("none", "none", "none"), proof = true)
        assertEquals(AccuracyGrade.verified, AccuracyModel.grade(0.99, proven, oath = true))
    }

    // :176-192, server/tests/oath-vectors.mjs text for text
    @Test fun doseVectors() {
        val vectors = listOf(
            "Give amoxicillin 500 mg PO three times a day" to true,
            "Start IV ceftriaxone 2 g once daily" to true,
            "Paracetamol 15 mg/kg every 6 hours" to true,
            "Enoxaparin 1 mg/kg twice daily" to true,
            "Adrenaline IM 0.5 mg" to true,
            "Insulin 10 units at night nocte" to true,
            "Give 1 g stat" to true,
            "Potassium 6.8 mmol/L, glucose 250 mg/dL" to false,
            "A 45-year-old man weighing 80 kg presents" to false,
            "Haemoglobin 9 g/dL with low MCV" to false,
            "What is the most likely diagnosis?" to false,
            "The mechanism of aspirin" to false,
        )
        for ((text, dose) in vectors) assertEquals("dose ${if (dose) "found" else "not found"}: $text", dose, AccuracyModel.hasDose(text))
    }

    // :193-195
    @Test fun aDiagnosisATreatmentOrADoseMakesAnOathItemAMechanismDoesNot() {
        assertTrue(AccuracyModel.isOath("What is the most likely diagnosis?"))
        assertTrue(AccuracyModel.isOath("What is the next best step in management?"))
        assertTrue(AccuracyModel.isOath("Give amoxicillin 500 mg PO three times a day"))
        assertFalse(AccuracyModel.isOath("Which enzyme is deficient in PKU?"))
    }

    // :196-197
    @Test fun keyDisagreementIsAShare() {
        val f = AccuracyModel.featureValues(AccuracyKind.mcq, emptyList(), listOf(AccuracyVote(risk = 1, answer = "C"), AccuracyVote(risk = 1, answer = "A")), 0, null, "A")
        assertEquals(0.5, f["key_disagree"]!!, 0.0)
    }

    // :198-199
    @Test fun theBundledWeightsDecodeAndAreValid() {
        assertEquals("prior-1", AccuracyModel.bundled.version)
        assertTrue(AccuracyModel.bundled.isValid)
        assertEquals(AccuracyModel.features, AccuracyModel.bundled.features)
    }

    // :200-205
    @Test fun inferenceIsTheLogisticOfTheWeightedSum() {
        val logit = 3 + 0.3 * (3.0 / 3.0) + (0.8 + 0.1 * 0.6) + 0.8 * 0.7
        assertTrue("$p1", abs(p1 - 1 / (1 + exp(-logit))) < 1e-12)
    }

    // :206-208
    @Test fun newWeightsReScoreWithoutANewCheck() {
        val trained = AccuracyModel.bundled.copy(thresholds = AccuracyWeights.Thresholds(0.999, 0.4))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(p1, pass, weights = trained))
    }

    // :209-210
    @Test fun weightsWithCrossedCutOffsAreInvalid() {
        assertFalse(AccuracyModel.bundled.copy(thresholds = AccuracyWeights.Thresholds(0.3, 0.5)).isValid)
        assertFalse(AccuracyModel.bundled.copy(thresholds = AccuracyWeights.Thresholds(1.5, 0.5)).isValid)
        assertFalse(AccuracyModel.bundled.copy(weights = AccuracyModel.bundled.weights.drop(1)).isValid)
        assertFalse(AccuracyModel.bundled.copy(features = AccuracyModel.features.dropLast(1) + "unheard_of").isValid)
    }

    // the vignette route's grade cases, :471-477 and :482-485
    private val vf = mapOf("no_models" to 0.0, "kind_mcq" to 1.0, "voters" to 1.0, "families" to 3.0, "blind_agree" to 3.0, "vignette_proof" to 1.0, "vignette_checked" to 1.0)

    @Test fun v8TheRouteOffAVignetteProofBacksNothing() {
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.95, vf))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.95, vf, vignetteRoute = false))
    }

    @Test fun v9OnProvenIsVerifiedCheckedIsCheckedAndNeitherBelowTheCutOff() {
        assertEquals(AccuracyGrade.verified, AccuracyModel.grade(0.95, vf, vignetteRoute = true))
        assertEquals(AccuracyGrade.checked, AccuracyModel.grade(0.95, vf + ("vignette_proof" to 0.0), vignetteRoute = true))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.5, vf + ("vignette_proof" to 0.0), vignetteRoute = true))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.95, vf + mapOf("vignette_proof" to 0.0, "blind_agree" to 2.0), vignetteRoute = true))
    }

    @Test fun v11TheTiersMeanings() {
        assertEquals("Checked", AccuracyGrade.checked.title)
        assertTrue(AccuracyGrade.verified.meaning?.startsWith("Verified means") == true)
        assertNull(AccuracyGrade.check.meaning)
    }

    @Test fun v12TheRouteOffNoNewFeature() {
        val f = AccuracyModel.featureValues(AccuracyKind.mcq, emptyList(), emptyList(), 0, null, "A")
        assertNull(f["vignette_proof"])
        assertNull(f["vignette_checked"])
        val on = AccuracyModel.featureValues(AccuracyKind.mcq, emptyList(), emptyList(), 0, null, "A", vignette = VignetteFlags(proven = true, checked = false))
        assertEquals(1.0, on["vignette_proof"]!!, 0.0)
        assertEquals(0.0, on["vignette_checked"]!!, 0.0)
    }

    // ExamCatalogTests.swift:274-298 - stricter for management questions
    private val base = AccuracyWeights.Thresholds(0.85, 0.4)

    @Test fun halfStrictIs092And045AsTheServer() {
        val half = AccuracyModel.stricter(base, 0.5)
        assertEquals(0.92, half.verified, 0.00001)
        assertEquals(0.45, half.flagged, 0.00001)
    }

    @Test fun fullyStrictIs099WithAGap() {
        val full = AccuracyModel.stricter(base, 1.0)
        assertEquals(0.99, full.verified, 0.00001)
        assertTrue(full.flagged < full.verified)
    }

    @Test fun noStrictnessNoChange() = assertEquals(base, AccuracyModel.stricter(base, 0.0))

    @Test fun managementLeadIns() {
        assertTrue(AccuracyModel.isManagement("What is the most appropriate next step in management?"))
        assertFalse(AccuracyModel.isManagement("Which enzyme is deficient?"))
    }

    @Test fun theChosenExamsStrictnessReachesOnlyManagementQuestionsAndOnlyWhileItsTrackIsChosen() {
        val mgmt = AccuracyItem("m", AccuracyKind.mcq, stem = "What is the next best step in management?", options = listOf("a", "b", "c", "d"), key = 0)
        val mech = AccuracyItem("n", AccuracyKind.mcq, stem = "Which enzyme is deficient?", options = listOf("a", "b", "c", "d"), key = 0)
        val defaults = MemoryExamDefaults()
        ExamChoice.choose(ExamCatalog.step2ck, null, defaults)
        assertEquals(0.5, AccuracyModel.examStrictness(mgmt, defaults), 0.01)
        assertEquals(0.0, AccuracyModel.examStrictness(mech, defaults), 0.0)
        assertEquals("no exam given, no strictness", 0.0, AccuracyModel.examStrictness(mgmt, null), 0.0)
        defaults.set(ExamTrack.storageKey, "plab")
        assertEquals("once the track moves on, the strictness goes", 0.0, AccuracyModel.examStrictness(mgmt, defaults), 0.0)
    }

    @Test fun p09IsVerifiedForStep1AndCheckThisForAStep2CkManagementQuestion() {
        val f = mapOf("no_models" to 0.0, "rule_severe" to 0.0, "voters" to 1.0, "families" to 3.0, "ev_support" to 1.0, "source_proof" to 1.0)
        val plain = AccuracyModel.bundled.copy(thresholds = base)
        val strict = plain.copy(thresholds = AccuracyModel.stricter(base, 0.5))
        assertEquals(AccuracyGrade.verified, AccuracyModel.grade(0.9, f, weights = plain))
        assertEquals(AccuracyGrade.check, AccuracyModel.grade(0.9, f, weights = strict))
    }

    // AccuracyFix.canApply, :436-437 and AccuracySchedule.swift:86-115
    @Test fun aKeyOutsideTheOptionsIsNotOffered() {
        val item = AccuracyItem("q", AccuracyKind.mcq, stem = "S", options = listOf("a", "b", "c", "d", "e"), key = 0, explanation = "x")
        assertFalse(AccuracyFix.canApply(AccuracySuggestion("key", "Q"), item))
        assertTrue(AccuracyFix.canApply(AccuracySuggestion("key", " b "), item))
        assertEquals(1, AccuracyFix.keyIndex(" b ", 5))
        assertNull(AccuracyFix.keyIndex("Z", 5))
        assertNull(AccuracyFix.keyIndex("AB", 5))
        assertNull(AccuracyFix.keyIndex("", 5))
    }

    @Test fun canApplyByKindAndField() {
        val card = AccuracyItem("c", AccuracyKind.card, text = "Q: x\nA: y")
        val station = AccuracyItem("o", AccuracyKind.osce, text = "BLS\n- a\n- b")
        assertTrue(AccuracyFix.canApply(AccuracySuggestion("explanation", "Better."), card))
        assertTrue(AccuracyFix.canApply(AccuracySuggestion("answer", "Vitamin K"), card))
        assertFalse(AccuracyFix.canApply(AccuracySuggestion("key", "A"), card))
        assertTrue(AccuracyFix.canApply(AccuracySuggestion("text", "Check danger\nCheck response\nCall for help"), station))
        assertFalse("a station needs at least two steps", AccuracyFix.canApply(AccuracySuggestion("text", "Check danger"), station))
        assertFalse(AccuracyFix.canApply(AccuracySuggestion("text", "a\nb"), AccuracyItem("p", AccuracyKind.page, text = "p")))
    }

    @Test fun linesAreSplitAtBreaksAndSemicolonsAndTrimmedOfDashesAndBullets() {
        assertEquals(listOf("Vitamin K", "Four-factor PCC"), AccuracyFix.lines("Vitamin K\n- Four-factor PCC"))
        assertEquals(listOf("a", "b", "c"), AccuracyFix.lines(" • a ;b\n\n\t- c\t"))
    }

    // the weights' JSON (iOS AccuracyStore.refreshWeights keeps only weights in the model's shape)
    @Test fun weightsRoundTripThroughJson() {
        val back = AccuracyWeights.fromJson(AccuracyModel.bundled.toJson())
        assertEquals(AccuracyModel.bundled, back)
    }

    @Test fun aReplyWithWeightsInTheModelsShapeIsRead() {
        val reply = JSONObject().put("weights", AccuracyModel.bundled.toJson().put("metrics", JSONObject.NULL))
        assertEquals(AccuracyModel.bundled, AccuracyWeights.fromReply(reply))
    }

    @Test fun aReplyWithWeightsOutOfShapeIsNotUsed() {
        fun reply(edit: (JSONObject) -> Unit) = JSONObject().put("weights", AccuracyModel.bundled.toJson().also(edit))
        assertNull(AccuracyWeights.fromReply(null))
        assertNull(AccuracyWeights.fromReply(JSONObject()))
        assertNull("crossed cut-offs", AccuracyWeights.fromReply(reply { it.put("thresholds", JSONObject().put("verified", 0.3).put("flagged", 0.5)) }))
        assertNull("a feature the model does not have", AccuracyWeights.fromReply(reply { it.put("features", org.json.JSONArray(AccuracyModel.features.dropLast(1) + "unheard_of")) }))
        assertNull("fewer weights than features", AccuracyWeights.fromReply(reply { it.put("weights", org.json.JSONArray(AccuracyModel.bundled.weights.drop(1))) }))
        assertNull("no version", AccuracyWeights.fromReply(reply { it.remove("version") }))
        assertNotNull(AccuracyWeights.fromReply(reply { }))
    }

    // the vote's JSON: a vote with no integer risk is unreadable, the rest take their defaults
    @Test fun aVoteTakesDefaultsForWhatTheServerLeavesOut() {
        val vote = AccuracyVote.fromJson(JSONObject("""{"risk":2}"""))!!
        assertEquals(AccuracyVote(model = "", risk = 2, answer = null, evidence = "none"), vote)
        assertNull(AccuracyVote.fromJson(JSONObject("""{"model":"m"}""")))
        assertNull(AccuracyVote.fromJson(JSONObject("""{"model":"m","risk":"1"}""")))
        val full = AccuracyVote(model = "m", risk = 3, answer = "B", evidence = "contradicts", cites = listOf("S1"), issues = listOf("Wrong"),
            fix = AccuracySuggestion("key", "C", listOf("a")), blind = false)
        assertEquals(full, AccuracyVote.fromJson(full.toJson()))
    }

    // the numbers kept in the app are the server's (server/accuracy-model.js)
    private fun serverSource(): String {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "server/accuracy-model.js").exists()) dir = dir.parentFile
        assertNotNull("server/accuracy-model.js is found from the test's working directory", dir)
        return File(dir, "server/accuracy-model.js").readText(Charsets.UTF_8)
    }

    private fun quoted(list: String): List<String> = Regex("'((?:[^'\\\\]|\\\\.)*)'").findAll(list).map { it.groupValues[1] }.toList()

    private fun listBody(source: String, name: String): String =
        Regex("""$name\s*=\s*\[(.*?)\];""", RegexOption.DOT_MATCHES_ALL).find(source)!!.groupValues[1]

    @Test fun theFeaturesCuesAndVoterCountAreTheServers() {
        val s = serverSource()
        assertEquals(AccuracyModel.features, quoted(listBody(s, "export const FEATURES")))
        assertEquals(AccuracyModel.managementCues, quoted(listBody(s, "export const MANAGEMENT_CUES")))
        assertEquals(AccuracyModel.diagnosisCues, quoted(listBody(s, "export const DIAGNOSIS_CUES")))
        assertEquals(AccuracyModel.minVerifyVoters, Regex("""export const MIN_VERIFY_VOTERS = (\d+);""").find(s)!!.groupValues[1].toInt())
        assertEquals(AccuracyModel.oathSourceMatch, Regex("""export const OATH_SOURCE_MATCH = ([\d.]+);""").find(s)!!.groupValues[1].toDouble(), 0.0)
    }

    @Test fun theBundledWeightsAndCutOffsAreTheServers() {
        val s = serverSource()
        val defaults = s.substring(s.indexOf("export const DEFAULT_WEIGHTS"), s.indexOf("// END DEFAULT WEIGHTS"))
        assertEquals("prior-1", Regex("""version: '([^']+)'""").find(defaults)!!.groupValues[1])
        val weights = Regex("""weights: \[([^\]]*)\]""").find(defaults)!!.groupValues[1].split(",").map { it.trim().toDouble() }
        assertEquals(AccuracyModel.bundled.weights, weights)
        val t = Regex("""thresholds: \{ verified: ([\d.]+), flagged: ([\d.]+) \}""").find(defaults)!!.groupValues
        assertEquals(AccuracyModel.bundled.thresholds, AccuracyWeights.Thresholds(t[1].toDouble(), t[2].toDouble()))
    }

    @Test fun theDosePatternIsTheServersCharacterForCharacter() {
        val s = serverSource()
        val body = s.substring(s.indexOf("export const DOSE_PATTERN ="), s.indexOf("const DOSE = new RegExp"))
        val pattern = quoted(body).joinToString("") { it.replace("\\\\", "\\") }
        assertEquals(pattern, AccuracyModel.dosePattern)
    }

    @Test fun everyFamilyPatternIsTheServersInTheSameOrder() {
        // the server also groups the models of two more makers (13 families against 11 here); iOS and Android do not yet
        val s = serverSource()
        val table = s.substring(s.indexOf("const FAMILIES = ["), s.indexOf("export function familyOf"))
        val server = Regex("""\['(\w+)', /(.+?)/\]""").findAll(table).map { it.groupValues[1] to it.groupValues[2] }.toList()
        assertEquals(AccuracyModel.families, server.take(AccuracyModel.families.size))
    }
}
