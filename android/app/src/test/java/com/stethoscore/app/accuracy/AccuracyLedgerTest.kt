package com.stethoscore.app.accuracy

import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.exam.ExamCatalog
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.exam.MemoryExamDefaults
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

// The accuracy ledger: the cases of ios/RedPen/Tests/AccuracyTests.swift
// "MARK: the ledger" (lines 248-390) and "MARK: the vignette route" (V1-V7,
// V10), case for case, each test naming the iOS line it ports; the server's
// reply as the device reads it; and the ledger's own file. Times are epoch
// milliseconds, so the iOS intervals (seconds) are written * 1000.
class AccuracyLedgerTest {

    @get:Rule val folder = TemporaryFolder()

    private fun secs(n: Long) = n * 1000L

    private fun vote(model: String, risk: Int = 1, answer: String = "A", evidence: String = "supports", blind: Boolean? = true, issues: List<String> = emptyList()) =
        AccuracyVote(model = model, risk = risk, answer = answer, evidence = evidence, issues = issues, blind = blind)

    // :228-251
    private val question = MCQQuestion(
        stem = "A 60-year-old man has crushing chest pain. Which drug reduces mortality first?",
        options = listOf("Aspirin", "Morphine", "Oxygen", "Nitrates", "Furosemide"), correctIndex = 0,
        explanation = "Aspirin reduces mortality in acute coronary syndrome.")
    private val item0 = AccuracyItem.mcq(question)
    private val hash0 = item0.contentHash
    private val fullProof = AccuracyProof(v = 2, claims = 1, proven = 1)
    private val evidence = listOf(AccuracyEvidence("S1", "MedlinePlus", "t", "https://medlineplus.gov"))

    // :259
    private val provenJson = ""","proof":{"v":2,"claims":1,"proven":1,"quotes":[{"claim":"c","quote":"q","source":"MedlinePlus","title":"t","url":"https://medlineplus.gov/x.html"}]}"""
    private val lookupJson = ""","proof":{"v":2,"claims":1,"proven":0,"why":"lookup"}"""
    private val checkedJson = ""","vignette":{"ok":true,"tier":"checked","why":null,"rules":["cdc-tst-5mm"]}"""

    /** :260-268 - the server's reply for one item, as it sends it. */
    private fun gateReply(claims: String, proof: String = provenJson): AccuracyCheckReply? {
        val json = """
            {"items":[{"id":"q","hash":"x","p":0.97,"verdict":"check","modelVersion":"v","features":{"source_match":0.8,"no_source":0},
              "rules":[],"votes":[{"model":"a","risk":1,"answer":"A","evidence":"supports","cites":[],"issues":[],"fix":null,"blind":true},
                                  {"model":"b","risk":1,"answer":"A","evidence":"supports","cites":[],"issues":[],"fix":null,"blind":true},
                                  {"model":"c","risk":1,"answer":"A","evidence":"supports","cites":[],"issues":[],"fix":null,"blind":true}],
              "evidence":[{"id":"S1","source":"MedlinePlus","title":"t","url":"https://medlineplus.gov"}],"fix":null$claims$proof}]}
        """
        return AccuracyCheckReply.parse(JSONObject(json))
    }

    private val gateTime = secs(3_000_000)

    private fun threeBlind() = listOf(vote("a"), vote("b"), vote("c"))

    // MARK: the ledger

    // :252
    @Test fun anUncheckedItemWithNoRuleHitsIsNotCheckedYet() = assertEquals(AccuracyGrade.unchecked, AccuracyLedger().assess(item0).grade)

    // :253-256
    @Test fun threeFamiliesBlindSolvesProvenByAnOfficialSourceMakeItVerified() {
        val ledger = AccuracyLedger()
        ledger.add(threeBlind(), hash0, evidence = evidence, sourceMatch = 0.8, proof = fullProof)
        assertEquals(AccuracyGrade.verified, ledger.assess(item0).grade)
        assertTrue(ledger.isChecked(hash0, question = true))
    }

    // :257-262
    @Test fun aCheckThatReachedOnlyTwoFamiliesIsCheckThisAndAskedAgainOnceADayHasPassed() {
        val checkTime = secs(2_000_000)
        val ledger = AccuracyLedger()
        ledger.add(listOf(vote("a"), vote("b")), hash0, sourceMatch = 0.8, now = checkTime)
        assertEquals(AccuracyGrade.check, ledger.assess(item0).grade)
        assertTrue(ledger.isChecked(hash0, question = true, now = checkTime + secs(3600)))
        assertFalse(ledger.isChecked(hash0, question = true, now = checkTime + secs(90_000)))
    }

    // :263-266
    @Test fun aQuestionCheckedBeforeBlindSolvingIsAskedAboutAgain() {
        val ledger = AccuracyLedger()
        ledger.add(listOf(vote("a", blind = null), vote("b", blind = null)), hash0, sourceMatch = 0.8)
        assertFalse(ledger.isChecked(hash0, question = true))
        assertTrue(ledger.isChecked(hash0))
        assertEquals(AccuracyGrade.check, ledger.assess(item0).grade)
    }

    // :267-269 (continuing the first ledger of :253)
    @Test fun aModelsNewVoteReplacesItsOldOneAndItsConcernIsAReason() {
        val ledger = AccuracyLedger()
        ledger.add(threeBlind(), hash0, evidence = evidence, sourceMatch = 0.8, proof = fullProof)
        ledger.add(listOf(AccuracyVote(model = "a", risk = 4, answer = "B", evidence = "contradicts", issues = listOf("Wrong"))), hash0)
        assertEquals(3, ledger.records[hash0]?.votes?.size)
        assertTrue(ledger.assess(item0).grade != AccuracyGrade.verified)
        assertTrue(ledger.assess(item0).reasons.contains("a: Wrong"))
    }

    // :270-273
    @Test fun aReportedItemIsNeverShownAsVerifiedAgain() {
        val ledger = AccuracyLedger()
        ledger.add(listOf(vote("a"), vote("b")), hash0, sourceMatch = 0.8, proof = fullProof)
        ledger.markReported(hash0)
        assertEquals(AccuracyGrade.check, ledger.assess(item0).grade)
        assertTrue(ledger.records[hash0]?.reported == true)
    }

    // the same, for the three-family Verified item (the iOS test reports a two-family one, which is Check this either way)
    @Test fun aReportedVerifiedItemFallsToCheckThis() {
        val ledger = AccuracyLedger()
        ledger.record(gateReply(""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.verified, ledger.assess(item0).grade)
        ledger.markReported(hash0)
        assertEquals(AccuracyGrade.check, ledger.assess(item0).grade)
    }

    // :274-298 the claim gate
    @Test fun aReplyTheGateFoundNothingInIsVerifiedOnTheVotesAsBefore() {
        val gated = AccuracyLedger()
        gated.record(gateReply(""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.verified, gated.assess(item0).grade)
        assertNull(gated.records[hash0]?.claimHolds)
    }

    @Test fun anItemThatContradictsItsOwnLectureIsNeverVerifiedWhateverTheVotes() {
        val gated = AccuracyLedger()
        gated.record(gateReply(""), listOf(hash0), gateTime)
        gated.record(gateReply(""","claims":{"hard":[{"code":"frequency","claim":"every 4 hours","source":"every 6 hours"}],"soft":[]}"""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, gated.assess(item0).grade)
        assertEquals(listOf("frequency"), gated.records[hash0]?.claimHolds)
        assertTrue(gated.isChecked(hash0))
        assertTrue(gated.assess(item0).reasons.contains("Gives a different dosing frequency from its own lecture."))
    }

    @Test fun aSentenceTurnedAroundHasWordsOfItsOwn() {
        val gated = AccuracyLedger()
        gated.record(gateReply(""","claims":{"hard":[{"code":"direction","claim":"raises the potassium","source":"lowers the potassium"}],"soft":[]}"""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, gated.assess(item0).grade)
        assertTrue(gated.assess(item0).reasons.contains("Says the other way from its own lecture."))
    }

    @Test fun aProvenanceHoldFromTheServerHoldsItTooInItsOwnWords() {
        val gated = AccuracyLedger()
        gated.record(gateReply(""","claims":{"hard":[{"code":"dabt","claim":"Give 1.0 mg","source":"number: 1 mg against 10 mg"}],"soft":[]}"""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, gated.assess(item0).grade)
        assertTrue(gated.assess(item0).reasons.any { it.startsWith("It doesn't copy its source faithfully") })
    }

    @Test fun everyProvenanceHoldHasWordsOfItsOwn() {
        val other = AccuracyAssessment.holdReason("anything else")
        for (code in listOf("retracted", "conflict", "dabt", "shadh", "tafarrud", "naskh")) {
            assertTrue(code, AccuracyAssessment.holdReason(code) != other)
        }
        assertEquals("Differs from its own lecture.", other)
    }

    @Test fun everyClaimGateCodeHasItsWords() {
        assertEquals("Says the opposite of its own lecture.", AccuracyAssessment.holdReason("negation"))
        assertEquals("Gives a different dose from its own lecture.", AccuracyAssessment.holdReason("dose"))
        assertEquals("Gives a different dosing frequency from its own lecture.", AccuracyAssessment.holdReason("frequency"))
        assertEquals("Gives a different percentage from its own lecture.", AccuracyAssessment.holdReason("percentage"))
        assertEquals("Says the other way from its own lecture.", AccuracyAssessment.holdReason("direction"))
        assertEquals("Couldn't be compared with its lecture yet; it will be checked again.", AccuracyAssessment.holdReason(AccuracyCheckReply.gateFailed))
    }

    // :299
    @Test fun aLaterRepliesFindingsReplaceTheEarlierOnes() {
        val gated = AccuracyLedger()
        gated.record(gateReply(""","claims":{"hard":[{"code":"negation","claim":"x","source":"y"}],"soft":[]}"""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, gated.assess(item0).grade)
        gated.record(gateReply(""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.verified, gated.assess(item0).grade)
    }

    // :300-302
    @Test fun aVoteFromElsewhereWithNoGateLeavesTheFindingsAsTheyWere() {
        val gated = AccuracyLedger()
        gated.record(gateReply(""), listOf(hash0), gateTime)
        gated.add(listOf(vote("c", blind = null)), hash0, holds = listOf("negation"))
        gated.add(listOf(vote("d", blind = null)), hash0)
        assertEquals(listOf("negation"), gated.records[hash0]?.claimHolds)
        assertEquals(AccuracyGrade.check, gated.assess(item0).grade)
    }

    // :303-310 a gate that failed
    @Test fun aGateThatFailedHoldsTheItemAtCheckThisWithItsVotesKeptAndAsksAgainLaterNotAtOnce() {
        val broken = AccuracyLedger()
        broken.record(gateReply(""","claims":{"hard":[{"code":"gate_failed","claim":"","source":""}],"soft":[]}"""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, broken.assess(item0).grade)
        assertEquals(3, broken.records[hash0]?.votes?.size)
        assertFalse(broken.isChecked(hash0))
        assertFalse(broken.mayRetry(hash0, now = gateTime + secs(60)))
        assertTrue(broken.mayRetry(hash0, now = gateTime + secs(7 * 3600)))
        broken.record(gateReply(""), listOf(hash0), gateTime + secs(7 * 3600))
        assertTrue(broken.isChecked(hash0, question = true, now = gateTime + secs(7 * 3600)))
        assertEquals(AccuracyGrade.verified, broken.assess(item0).grade)
    }

    // :311-312
    @Test fun aFindingWithoutACodeStillHoldsTheItem() {
        val unread = AccuracyLedger()
        unread.record(gateReply(""","claims":{"hard":[{"claim":"x"}],"soft":[],"partial":true}"""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, unread.assess(item0).grade)
        assertEquals(listOf(AccuracyCheckReply.gateFailed), unread.records[hash0]?.claimHolds)
    }

    // :313-316
    @Test fun noVoteIsFailedUnlessTheDaysChecksRanOut() {
        val unanswered = AccuracyLedger()
        unanswered.record(AccuracyCheckReply(items = emptyList(), limit = "day", message = null), listOf(hash0), gateTime)
        unanswered.record(null, listOf("other"), gateTime)
        assertNull(unanswered.failed[hash0])
        assertEquals(gateTime, unanswered.failed["other"])
        assertTrue(unanswered.records.isEmpty())
    }

    // :317-318 and :380-381
    @Test fun aRecordSavedBeforeTheGateOrTheProofStillLoadsWithNoFindings() {
        val older = AccuracyRecord.fromJson(JSONObject("""{"hash":"h","votes":[],"evidence":[],"checkedAt":0,"reported":false}"""))
        assertNotNull(older)
        assertNull(older?.claimHolds)
        assertNull(older?.proof)
        assertNull(older?.proofTries)
        assertNull(older?.vignette)
    }

    // :319-321
    @Test fun aSetsSummary() {
        val reported = AccuracyLedger()
        reported.add(listOf(vote("a"), vote("b")), hash0, sourceMatch = 0.8, proof = fullProof)
        reported.markReported(hash0)
        val summary = reported.summary(listOf(item0, AccuracyItem("z", AccuracyKind.card, text = "Give paracetamol 10 g now")))
        assertEquals(1, summary.check)
        assertEquals(1, summary.flagged)
        assertEquals(AccuracyGrade.flagged, summary.grade)
        assertEquals("1 to check · 1 flagged", summary.line)
    }

    // :322
    @Test fun nothingCheckedNoSummaryLine() = assertNull(AccuracySummary().line)

    // :323-329
    @Test fun aFailedCheckWaitsBeforeItIsTriedAgainAndRecordsOfEditedItemsArePruned() {
        val failing = AccuracyLedger()
        val t0 = secs(1_000_000)
        failing.failed["h"] = t0
        assertFalse(failing.mayRetry("h", now = t0 + secs(60)))
        assertTrue(failing.mayRetry("h", now = t0 + secs(7 * 3600)))
        failing.records["old"] = AccuracyRecord(hash = "old")
        failing.prune(setOf("h"))
        assertTrue(failing.records.isEmpty())
        assertNotNull(failing.failed["h"])
    }

    // V10 (:480-481)
    @Test fun aSetOfVerifiedAndCheckedIsCheckedOverallSaidPlainly() {
        val mixed = AccuracySummary()
        mixed.add(AccuracyGrade.verified)
        mixed.add(AccuracyGrade.checked)
        assertEquals(AccuracyGrade.checked, mixed.grade)
        assertEquals(1, mixed.passed)
        assertEquals(2, mixed.checked)
        assertEquals("1 verified · 1 checked, not fully proven", mixed.line)
    }

    @Test fun aSummarysBadgeIsFlaggedFirstThenCheckThenCheckedThenVerifiedAndNotWhileAnythingIsUnchecked() {
        assertEquals(AccuracyGrade.flagged, AccuracySummary(verified = 3, check = 1, flagged = 1).grade)
        assertEquals(AccuracyGrade.check, AccuracySummary(verified = 3, passed = 1, check = 1).grade)
        assertEquals(AccuracyGrade.verified, AccuracySummary(verified = 3).grade)
        assertEquals(AccuracyGrade.unchecked, AccuracySummary(verified = 3, unchecked = 1).grade)
        assertEquals(AccuracyGrade.unchecked, AccuracySummary().grade)
        assertEquals("2 verified · 1 not yet checked", AccuracySummary(verified = 2, unchecked = 1).line)
    }

    // MARK: the source proof (:333-390)

    // :335-338
    @Test fun threeFamiliesWithNoProofInTheReplyAreCheckThisWithTheReason() {
        val proofs = AccuracyLedger()
        proofs.record(gateReply("", proof = ""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, proofs.assess(item0).grade)
        assertNull(proofs.records[hash0]?.proof)
        assertTrue(proofs.assess(item0).reasons.contains("No official source states it word for word yet."))
    }

    // :339-340
    @Test fun theServersProofDecodesQuotesAndAll() {
        val proof = gateReply("")?.items?.firstOrNull()?.proof
        assertTrue(proof?.isFull == true)
        assertEquals("https://medlineplus.gov/x.html", proof?.quotes?.firstOrNull()?.url)
        assertEquals("MedlinePlus", proof?.quotes?.firstOrNull()?.source)
    }

    // :341-344
    @Test fun aProofIsFullOnlyWhenEveryClaimIsProvenByThisVersionWithNothingCutShort() {
        assertTrue(fullProof.isFull)
        assertFalse(AccuracyProof(v = 2, claims = 2, proven = 1).isFull)
        assertFalse(AccuracyProof(v = 2, claims = 0, proven = 0).isFull)
        assertFalse(AccuracyProof(v = 1, claims = 1, proven = 1).isFull)
        assertFalse(AccuracyProof(v = 2, claims = 1, proven = 1, why = "budget").isFull)
        assertFalse(AccuracyProof(v = 2, claims = 1, proven = 1, why = "stem").isFull)
    }

    // :345-348
    @Test fun dueAgainWhenCutShortOrOlderNotWhenItSimplyCouldNotBeProven() {
        assertTrue(AccuracyProof(v = 2, why = "lookup").due)
        assertTrue(AccuracyProof(v = 2, why = "budget").due)
        assertTrue(AccuracyProof(v = 2, why = "timeout").due)
        assertTrue(AccuracyProof(v = 2, why = "error").due)
        assertTrue(AccuracyProof(v = 0).due)
        assertFalse(AccuracyProof(v = 2, claims = 1, proven = 0, why = "unproven").due)
        assertFalse(AccuracyProof(v = 2, why = "stem").due)
        assertFalse(fullProof.due)
    }

    // :349-358
    @Test fun aSourceThatCouldNotBeReadIsCheckThisSayingItWillBeCheckedAgainAndAskedAgainAfterAFewHours() {
        val proofs = AccuracyLedger()
        proofs.record(gateReply("", proof = ""), listOf(hash0), gateTime)
        proofs.record(gateReply("", proof = lookupJson), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, proofs.assess(item0).grade)
        assertEquals(2, proofs.records[hash0]?.proofTries)
        assertTrue(proofs.assess(item0).reasons.contains("An official source could not be read this time; it will be checked again."))
        assertTrue(proofs.isChecked(hash0, question = true, now = gateTime + secs(3600)))
        assertFalse(proofs.isChecked(hash0, question = true, now = gateTime + secs(7 * 3600)))
    }

    // :359-361
    @Test fun thenLeftAtCheckThisAfterAFewTries() {
        val proofs = AccuracyLedger()
        proofs.record(gateReply("", proof = ""), listOf(hash0), gateTime)
        repeat(3) { proofs.record(gateReply("", proof = lookupJson), listOf(hash0), gateTime) }
        assertEquals(AccuracyLedger.proofTries, proofs.records[hash0]?.proofTries)
        assertTrue(proofs.isChecked(hash0, question = true, now = gateTime + secs(30 * 86400)))
    }

    // :362-367
    @Test fun provenOnALaterCheckIsVerifiedTheTriesClearedAndALaterCutShortCheckDoesNotTakeTheProofAway() {
        val proofs = AccuracyLedger()
        proofs.record(gateReply("", proof = lookupJson), listOf(hash0), gateTime)
        proofs.record(gateReply(""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.verified, proofs.assess(item0).grade)
        assertNull(proofs.records[hash0]?.proofTries)
        assertTrue(proofs.assess(item0).reasons.isEmpty())
        proofs.record(gateReply("", proof = lookupJson), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.verified, proofs.assess(item0).grade)
        assertTrue(proofs.records[hash0]?.proof?.isFull == true)
    }

    // :368-370
    @Test fun sourcesTooLongForTheBatchSaidSo() {
        val budgeted = AccuracyLedger()
        budgeted.record(gateReply("", proof = ""","proof":{"v":2,"claims":1,"proven":0,"why":"budget"}"""), listOf(hash0), gateTime)
        assertTrue(budgeted.assess(item0).reasons.contains("Its official sources were too long to read in this batch; it will be checked again on its own."))
    }

    // :371-377
    @Test fun aKeyStatedWordForWordWithAnotherOptionASourceMayStateTooSaidSoAndNotThatNoSourceStatesIt() {
        val twoAnswers = AccuracyLedger()
        twoAnswers.record(gateReply("", proof = ""","proof":{"v":2,"claims":1,"proven":1,"why":"distractor"}"""), listOf(hash0), gateTime)
        val reasons = twoAnswers.assess(item0).reasons
        assertTrue(twoAnswers.assess(item0).grade != AccuracyGrade.verified)
        assertTrue(reasons.contains("An official source may also state another of its options."))
        assertFalse(reasons.any { it.contains("word for word") })
        assertEquals(listOf("One of its other options could not be read for certain."),
            AccuracyAssessment.proofReasons(AccuracyProof(v = 2, claims = 1, proven = 1, why = "options"), oath = true))
    }

    // :378-379
    @Test fun neitherIsCheckedAgainTheSourcesWillNotChangeTheirWords() {
        assertFalse(AccuracyProof(v = 2, claims = 1, proven = 1, why = "distractor").due)
        assertFalse(AccuracyProof(v = 2, claims = 1, proven = 1, why = "options").due)
    }

    // :380-382
    @Test fun anOathItemGetsTheOathsWords() {
        assertEquals(listOf("A dose, diagnosis or treatment no official source states word for word yet."), AccuracyAssessment.proofReasons(null, oath = true))
        assertEquals(listOf("No official source states it word for word yet."), AccuracyAssessment.proofReasons(null, oath = false))
        assertTrue(AccuracyAssessment.proofReasons(fullProof, oath = true).isEmpty())
    }

    // :383-385
    @Test fun anItemNoWordingCouldBeFormedForIsNotAskedAgain() {
        val unprovable = AccuracyLedger()
        unprovable.record(gateReply("", proof = ""","proof":{"v":2,"claims":0,"proven":0,"why":"stem"}"""), listOf(hash0), gateTime)
        assertTrue(unprovable.isChecked(hash0, question = true, now = gateTime + secs(30 * 86400)))
    }

    // MARK: the vignette route (:451-481)

    // V1-V2
    @Test fun aVignetteProofOnlyCheckedWithThreeBlindFamiliesAndNoSourceProofIsCheckedAndSaysWhatThatMeans() {
        val vignettes = AccuracyLedger()
        vignettes.record(gateReply(checkedJson, proof = ""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.checked, vignettes.assess(item0).grade)
        assertTrue(vignettes.assess(item0).reasons.contains(AccuracyGrade.checked.meaning ?: "-"))
    }

    // V3-V5
    @Test fun aProofWhoseRulesTheOwnerSignedOffIsVerifiedARefusedOneIsCheckThisAndAReplyWithoutItClearsIt() {
        val vignettes = AccuracyLedger()
        vignettes.record(gateReply(checkedJson, proof = ""), listOf(hash0), gateTime)
        vignettes.record(gateReply(""","vignette":{"ok":true,"tier":"proven","why":null,"rules":["cdc-tst-5mm"]}""", proof = ""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.verified, vignettes.assess(item0).grade)
        vignettes.record(gateReply(""","vignette":{"ok":false,"tier":null,"why":"stale","rules":[]}""", proof = ""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, vignettes.assess(item0).grade)
        vignettes.record(gateReply(checkedJson, proof = ""), listOf(hash0), gateTime)
        vignettes.record(gateReply("", proof = ""), listOf(hash0), gateTime)
        assertNull(vignettes.records[hash0]?.vignette)
        assertEquals(AccuracyGrade.check, vignettes.assess(item0).grade)
    }

    // V6
    @Test fun aHoldDropsCheckedToCheckThisInItsOwnWords() {
        val heldChecked = AccuracyLedger()
        heldChecked.record(gateReply(""","claims":{"hard":[{"code":"naskh","claim":"x","source":"y"}],"soft":[]}""" + checkedJson, proof = ""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.check, heldChecked.assess(item0).grade)
        assertTrue(heldChecked.assess(item0).reasons.contains("A published rule its proof rests on has been replaced by a newer one."))
    }

    // V7
    @Test fun reportedByTheStudentNeverCheckedToThemAgain() {
        val reportedChecked = AccuracyLedger()
        reportedChecked.record(gateReply(checkedJson, proof = ""), listOf(hash0), gateTime)
        assertEquals(AccuracyGrade.checked, reportedChecked.assess(item0).grade)
        reportedChecked.markReported(hash0)
        assertEquals(AccuracyGrade.check, reportedChecked.assess(item0).grade)
    }

    // MARK: Android-only: what the ledger does with the chosen exam, and its bookkeeping

    @Test fun theChosenExamsStrictnessReachesTheLedgersGrade() {
        val management = MCQQuestion(stem = "What is the next best step in management?", options = listOf("a", "b", "c", "d"), correctIndex = 0, explanation = "e")
        val item = AccuracyItem.mcq(management)
        val ledger = AccuracyLedger()
        ledger.add(threeBlind(), item.contentHash, evidence = evidence, sourceMatch = 0.8, proof = fullProof)
        // the bundled weights put this item above 0.99, where a stricter cut-off cannot reach it: soften them so its score has room
        val soft = AccuracyModel.bundled.copy(weights = AccuracyModel.bundled.weights.map { it * 0.3 })
        val p = AccuracyLedger.assess(item, ledger.records[item.contentHash], soft).probability
        assertTrue("$p", p < 0.95 && p > 0.5)
        val weights = soft.copy(thresholds = AccuracyWeights.Thresholds(p - 0.001, 0.4))
        val defaults = MemoryExamDefaults()
        ExamChoice.choose(ExamCatalog.step2ck, null, defaults)
        assertEquals(AccuracyGrade.verified, ledger.assess(item, weights).grade)
        assertEquals(AccuracyGrade.verified, ledger.assess(item, weights, defaults = null).grade)
        assertEquals(AccuracyGrade.check, ledger.assess(item, weights, defaults).grade)
        assertEquals(AccuracyGrade.check, ledger.summary(listOf(item), weights, defaults).grade)
    }

    @Test fun addingAVoteClearsItsFailureAndAnEmptyBatchLeavesTheOldRecordsAlone() {
        val ledger = AccuracyLedger()
        ledger.failed[hash0] = gateTime
        ledger.add(listOf(vote("a")), hash0)
        assertNull(ledger.failed[hash0])
        ledger.add(emptyList(), hash0)
        assertEquals(1, ledger.records[hash0]?.votes?.size)
    }

    @Test fun anItemWithoutALedgerRecordUsesTheRulesAndTheSourceMatchAlone() {
        val dosed = AccuracyItem("z", AccuracyKind.card, text = "Give paracetamol 10 g now")
        assertEquals(AccuracyGrade.flagged, AccuracyLedger().assess(dosed).grade)
        assertTrue(AccuracyLedger().assess(dosed).reasons.isNotEmpty())
    }

    @Test fun copyingALedgerSharesNothing() {
        val ledger = AccuracyLedger()
        ledger.add(listOf(vote("a")), hash0)
        val copy = ledger.copy()
        copy.markReported(hash0)
        copy.failed["x"] = 1L
        assertFalse(ledger.records[hash0]?.reported == true)
        assertTrue(ledger.failed.isEmpty())
    }

    // MARK: the server's reply, as the device reads it

    @Test fun theReplyIsReadWithEveryFieldTheDeviceKeeps() {
        val reply = gateReply(""","claims":{"hard":[{"code":"dose"}],"partial":true}""" + """,
            "vignette":{"ok":true,"tier":"proven","why":null,"rules":["r"]}""".trim())
        assertNotNull(reply)
        val item = reply!!.items!!.single()
        assertEquals("q", item.id)
        assertEquals(3, item.votes?.size)
        assertEquals(listOf("a", "b", "c"), item.votes?.map { it.model })
        assertEquals(true, item.votes?.first()?.blind)
        assertEquals("S1", item.evidence?.single()?.id)
        assertEquals(0.8, item.features?.get("source_match") ?: -1.0, 0.0)
        assertEquals(listOf("dose"), item.claims?.hard?.map { it.code })
        assertEquals(true, item.claims?.partial)
        assertTrue(item.proof?.isFull == true)
        assertTrue(item.vignette?.isProven == true)
        assertEquals(listOf("r"), item.vignette?.rules)
        assertNull(item.fix)
    }

    @Test fun aReplyThatSaysTheDayRanOutOrTheCheckersWereBusyKeepsItsWords() {
        val reply = AccuracyCheckReply.parse(JSONObject("""{"items":[],"limit":"day","message":"Back tomorrow.","busy":true}"""))
        assertEquals("day", reply?.limit)
        assertEquals("Back tomorrow.", reply?.message)
        assertEquals(true, reply?.busy)
        assertEquals(emptyList<AccuracyCheckReply.Item>(), reply?.items)
    }

    @Test fun anOlderOrNewerRepliesMissingAndExtraFieldsStillDecode() {
        val reply = AccuracyCheckReply.parse(JSONObject("""{"unknown":[1,2],"items":[{"surprise":true}]}"""))
        assertNotNull(reply)
        assertEquals(AccuracyCheckReply.Item(), reply?.items?.single())
        val empty = AccuracyCheckReply.parse(JSONObject("{}"))
        assertEquals(AccuracyCheckReply(), empty)
    }

    @Test fun aReplyThatCannotBeReadIsNothing() {
        assertNull(AccuracyCheckReply.parse(null))
        // a vote with no integer risk
        assertNull(AccuracyCheckReply.parse(JSONObject("""{"items":[{"votes":[{"model":"a","risk":"high"}]}]}""")))
        assertNull(AccuracyCheckReply.parse(JSONObject("""{"items":[{"votes":[{"model":"a"}]}]}""")))
        // an item that is not an object
        assertNull(AccuracyCheckReply.parse(JSONObject("""{"items":["x"]}""")))
    }

    @Test fun aReplyThatCannotBeReadMarksTheBatchFailedNotRecorded() {
        val ledger = AccuracyLedger()
        ledger.record(AccuracyCheckReply.parse(JSONObject("""{"items":["x"]}""")), listOf(hash0), gateTime)
        assertEquals(gateTime, ledger.failed[hash0])
        assertTrue(ledger.records.isEmpty())
    }

    @Test fun aReplyWithFewerItemsThanWereSentFailsTheRest() {
        val ledger = AccuracyLedger()
        ledger.record(gateReply(""), listOf(hash0, "second"), gateTime)
        assertNotNull(ledger.records[hash0])
        assertEquals(gateTime, ledger.failed["second"])
    }

    @Test fun noSourceInTheRepliesFeaturesMeansNoSourceMatch() {
        val json = """{"items":[{"votes":[{"model":"a","risk":1}],"features":{"source_match":0.9,"no_source":1}}]}"""
        val ledger = AccuracyLedger()
        ledger.record(AccuracyCheckReply.parse(JSONObject(json)), listOf(hash0), gateTime)
        assertNull(ledger.records[hash0]?.sourceMatch)
        val withSource = """{"items":[{"votes":[{"model":"a","risk":1}],"features":{"source_match":0.9,"no_source":0}}]}"""
        ledger.record(AccuracyCheckReply.parse(JSONObject(withSource)), listOf(hash0), gateTime)
        assertEquals(0.9, ledger.records[hash0]?.sourceMatch ?: -1.0, 0.0)
    }

    // MARK: JSON and the ledger's own file

    private fun fullRecord() = AccuracyRecord(
        hash = "h1", votes = listOf(vote("a"), AccuracyVote(model = "b", risk = 3, answer = "C", evidence = "contradicts", cites = listOf("S1"), issues = listOf("x"),
            fix = AccuracySuggestion("key", "C", listOf("b")))),
        evidence = evidence, sourceMatch = 0.5, fix = AccuracySuggestion("explanation", "Better."), checkedAt = 123_456L, reported = true,
        claimHolds = listOf("dose", "negation"), proof = AccuracyProof(2, 2, 1, "budget", listOf(AccuracyProof.Quote("c", "q", "s", "t", "u"))),
        proofTries = 2, vignette = AccuracyVignette(true, "checked", null, listOf("r")))

    @Test fun aRecordSurvivesItsJson() {
        val record = fullRecord()
        assertEquals(record, AccuracyRecord.fromJson(JSONObject(record.toJson().toString())))
        val bare = AccuracyRecord(hash = "h2", checkedAt = 5L)
        assertEquals(bare, AccuracyRecord.fromJson(JSONObject(bare.toJson().toString())))
    }

    @Test fun aRecordWithoutAHashCannotBeRead() = assertNull(AccuracyRecord.fromJson(JSONObject("""{"votes":[]}""")))

    @Test fun aLedgerSurvivesItsJsonAndALedgerRecordThatCannotBeReadIsLeftOutNotTheRest() {
        val ledger = AccuracyLedger()
        ledger.records["h1"] = fullRecord()
        ledger.failed["h3"] = 77L
        val back = AccuracyLedger.fromJson(JSONObject(ledger.toJson().toString()))
        assertEquals(ledger.records, back.records)
        assertEquals(ledger.failed, back.failed)

        val damaged = JSONObject(ledger.toJson().toString())
        damaged.getJSONObject("records").put("broken", JSONObject("""{"votes":[]}""")).put("worse", "text")
        val kept = AccuracyLedger.fromJson(damaged)
        assertEquals(setOf("h1"), kept.records.keys)
        assertEquals(mapOf("h3" to 77L), kept.failed)
    }

    @Test fun theLedgerLivesInItsOwnFileUnderTheFilesDirectory() {
        val dir = folder.newFolder("files")
        val file = AccuracyLedgerFile.inDirectory(dir)
        assertEquals(File(dir, "accuracy-ledger.json"), file.file)
        assertEquals("accuracy-ledger.json", AccuracyLedgerFile.NAME)
    }

    @Test fun aSavedLedgerLoadsBackAndLeavesNoTemporaryFile() {
        val dir = folder.newFolder("files")
        val file = AccuracyLedgerFile.inDirectory(dir)
        val ledger = AccuracyLedger()
        ledger.records["h1"] = fullRecord()
        ledger.failed["h3"] = 77L
        assertTrue(file.save(ledger))
        val back = file.load()
        assertEquals(ledger.records, back.records)
        assertEquals(ledger.failed, back.failed)
        assertEquals(listOf("accuracy-ledger.json"), dir.list()!!.toList())
    }

    @Test fun savingAgainReplacesTheOldFileWhole() {
        val file = AccuracyLedgerFile.inDirectory(folder.newFolder("files"))
        val first = AccuracyLedger()
        first.records["h1"] = fullRecord()
        file.save(first)
        val second = AccuracyLedger()
        second.records["h2"] = AccuracyRecord(hash = "h2", checkedAt = 1L)
        assertTrue(file.save(second))
        assertEquals(setOf("h2"), file.load().records.keys)
    }

    @Test fun aMissingFileIsAnEmptyLedger() {
        val loaded = AccuracyLedgerFile(File(folder.root, "none/accuracy-ledger.json")).load()
        assertTrue(loaded.records.isEmpty())
        assertTrue(loaded.failed.isEmpty())
    }

    @Test fun anUnreadableFileIsAnEmptyLedgerAndIsWrittenOverOnTheNextSave() {
        val file = AccuracyLedgerFile(folder.newFile("accuracy-ledger.json"))
        file.file.writeText("{ not json", Charsets.UTF_8)
        assertTrue(file.load().records.isEmpty())
        val ledger = AccuracyLedger()
        ledger.records["h1"] = AccuracyRecord(hash = "h1", checkedAt = 1L)
        assertTrue(file.save(ledger))
        assertEquals(setOf("h1"), file.load().records.keys)
    }

    @Test fun aFileThatCannotBeWrittenSaysSoAndKeepsTheOldOne() {
        val blocker = folder.newFile("blocker")
        assertFalse(AccuracyLedgerFile(File(blocker, "accuracy-ledger.json")).save(AccuracyLedger()))
        assertTrue(blocker.isFile)
    }

    // MARK: what the study screens read while the app runs

    @Test fun theSeenRecordsAreOneProcessWideMapTheSheetAlsoReads() {
        AccuracySeen.records.clear()
        try {
            AccuracySeen.records["h"] = AccuracyRecord(hash = "h", checkedAt = 1L)
            assertEquals("h", com.stethoscore.app.ui.AccuracySeen.records["h"]?.hash)
            assertSame(AccuracySeen.records, com.stethoscore.app.ui.AccuracySeen.records)
        } finally {
            AccuracySeen.records.clear()
        }
    }
}
