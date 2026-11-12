package com.stethoscore.app.data

import com.stethoscore.app.llm.ChatTurn
import com.stethoscore.app.llm.LLMBackend
import com.stethoscore.app.llm.LLMError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * A writer model that answers from a script, one reply (or failure) per call,
 * and keeps every request it was sent.
 */
internal class ScriptedWriter(
    private val replies: List<() -> String>,
    override val isOnDevice: Boolean = false,
) : LLMBackend {
    data class Call(val turns: List<ChatTurn>, val maxTokens: Int, val temperature: Double)

    val calls = mutableListOf<Call>()
    /** Runs inside each call, before it answers, with the call's index. */
    var onCall: suspend (Int) -> Unit = {}
    override val label: String get() = "Scripted"
    override val promptBudgetChars: Int get() = 40_000

    override suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String {
        calls += Call(turns, maxTokens, temperature)
        val index = calls.size - 1
        onCall(index)
        return replies[index]()
    }
}

/** The JSON reply with these lines in it. */
internal fun rulesReply(vararg lines: String): String =
    "{\"rules\": [" + lines.joinToString(", ") { "\"" + it + "\"" } + "]}"

// Ported from the model half of ios/RedPen/Shared/Insight/RuleWriter.swift
// (prompt, parse, batchSize, write): the request for a batch, the reply read
// back, and the ten-at-a-time run that skips a batch which fails.
class RuleWriterTest {
    private fun question(i: Int, explanation: String = "Because of reason $i. More follows.") =
        MCQQuestion(stem = "Stem $i: which one?", options = listOf("wrong $i", "right $i"), correctIndex = 1, explanation = explanation)

    private fun rules(count: Int, explanation: (Int) -> String = { "Because of reason $it. More follows." }): List<StudyRule> =
        (1..count).map { RuleWriter.plainRule(question(it, explanation(it)), "Subject") }

    private fun run(rules: List<StudyRule>, backend: LLMBackend): List<Map<String, String>> {
        val batches = mutableListOf<Map<String, String>>()
        runBlocking { RuleWriter.write(rules, backend) { batches += it } }
        return batches
    }

    private fun questionsIn(call: ScriptedWriter.Call): Int =
        Regex("(?m)^Question \\d+: ").findAll(call.turns.last().text).count()

    // ---- the request

    @Test fun thePromptAsksForOneRulePerQuestionAsJson() {
        val prompt = RuleWriter.prompt(rules(2)).split("\n")
        assertEquals("You are helping a medical student build a rule sheet for their exam.", prompt[0])
        assertTrue(prompt[1].startsWith("For each question below, write ONE precise, exam-style rule line (at most 25 words)"))
        assertTrue(prompt[1].contains("\"Painless jaundice + palpable gallbladder → pancreatic head carcinoma\""))
        assertTrue(prompt[1].endsWith("No preamble, no numbering inside the rule, no hedging."))
        assertEquals("Reply with JSON only, in exactly this shape, with one rule per question in the same order: {\"rules\": [\"...\", \"...\"]}", prompt[2])
        assertEquals("", prompt[3])
        assertEquals(listOf("Question 1: Stem 1: which one?", "Correct answer: right 1", "Explanation: Because of reason 1. More follows.", ""),
            prompt.subList(4, 8))
        assertEquals("Question 2: Stem 2: which one?", prompt[8])
    }

    @Test fun anEmptyExplanationIsLeftOutAndALongOneIsCutAtSixHundred() {
        val none = RuleWriter.prompt(rules(1) { "" })
        assertFalse(none.contains("Explanation:"))
        val long = RuleWriter.prompt(rules(1) { "x".repeat(700) })
        assertEquals("Explanation: " + "x".repeat(600), long.split("\n").first { it.startsWith("Explanation:") })
    }

    // ---- the reply

    @Test fun aReplyIsReadPastItsThinkingAndItsWrapping() {
        assertEquals(listOf("A → B", "C → D"), RuleWriter.parse("<think>{\"rules\":[\"no\"]}</think>Here: {\"rules\": [\" A → B \", \"C → D\"]}"))
        assertEquals(listOf("A → B"), RuleWriter.parse("```json\n{\"rules\": [\"A → B\"]}\n```"))
        assertEquals(listOf("real"), RuleWriter.parse("<think>one</think>draft<think>two</think>{\"rules\": [\"real\"]}"))
        assertEquals(emptyList<String>(), RuleWriter.parse("{\"rules\": []}"))
    }

    @Test fun aReplyCutOffInsideItsThinkingIsNothing() {
        // stripThinking: nothing after an unclosed <think> is an answer
        assertNull(RuleWriter.parse("<think>maybe {\"rules\": [\"A → B\"]}"))
    }

    @Test fun aReplyThatIsNotTheJsonAskedForIsNothing() {
        assertNull(RuleWriter.parse("Sorry, I can't."))
        assertNull(RuleWriter.parse("{\"other\": [\"A\"]}"))
        assertNull(RuleWriter.parse("{\"rules\": \"A\"}"))
        assertNull(RuleWriter.parse("{\"rules\": [\"A\""))
    }

    @Test fun oneEntryThatIsNotAStringSpoilsTheWholeReply() {
        // iOS decodes {"rules": [String]}: a number or a null in it fails the decode
        assertNull(RuleWriter.parse("{\"rules\": [\"A\", 5]}"))
        assertNull(RuleWriter.parse("{\"rules\": [\"A\", null]}"))
        assertNull(RuleWriter.parse("{\"rules\": [\"A\", [\"B\"]]}"))
    }

    // ---- the run

    @Test fun twentyFiveRulesGoTenAtATime() {
        val all = rules(25)
        val model = ScriptedWriter(listOf(
            { rulesReply(*Array(10) { "a$it" }) }, { rulesReply(*Array(10) { "b$it" }) }, { rulesReply(*Array(5) { "c$it" }) }))
        val batches = run(all, model)
        assertEquals(10, RuleWriter.batchSize)
        assertEquals(listOf(10, 10, 5), model.calls.map { questionsIn(it) })
        assertEquals(listOf(1400, 1400, 800), model.calls.map { it.maxTokens })
        assertEquals(listOf(0.3, 0.3, 0.3), model.calls.map { it.temperature })
        assertEquals(listOf(RuleWriter.prompt(all.subList(0, 10)), RuleWriter.prompt(all.subList(10, 20)), RuleWriter.prompt(all.subList(20, 25))),
            model.calls.map { it.turns.single().text })
        assertTrue(model.calls.all { it.turns.single().role == ChatTurn.Role.user })
        assertEquals(listOf(10, 10, 5), batches.map { it.size })
        // each line lands on the rule at its place, by id
        assertEquals("a0", batches[0][all[0].id])
        assertEquals("a9", batches[0][all[9].id])
        assertEquals("b0", batches[1][all[10].id])
        assertEquals("c4", batches[2][all[24].id])
    }

    @Test fun aBatchThatFailsIsSkippedAndTheRestGoOn() {
        val all = rules(25)
        val model = ScriptedWriter(listOf(
            { rulesReply(*Array(10) { "a$it" }) }, { throw LLMError.Http(500, "boom") }, { rulesReply(*Array(5) { "c$it" }) }))
        val batches = run(all, model)
        assertEquals(3, model.calls.size)
        assertEquals(2, batches.size)
        val written = batches.flatMap { it.keys }.toSet()
        assertEquals((all.subList(0, 10) + all.subList(20, 25)).map { it.id }.toSet(), written)
        assertTrue(all.subList(10, 20).none { it.id in written })
    }

    @Test fun aReplyThatIsNotUsableIsSkippedToo() {
        val model = ScriptedWriter(listOf({ "Sorry, I can't." }, { rulesReply("c0") }))
        val batches = run(rules(11), model)
        assertEquals(2, model.calls.size)
        assertEquals(1, batches.size)
        assertEquals(1, batches[0].size)
    }

    @Test fun emptyAndTooLongLinesAreLeftOut() {
        val all = rules(4)
        val model = ScriptedWriter(listOf({ rulesReply("kept", "", "x".repeat(301), "y".repeat(300)) }))
        val batch = run(all, model).single()
        assertEquals(mapOf(all[0].id to "kept", all[3].id to "y".repeat(300)), batch)
    }

    @Test fun fewerLinesThanQuestionsFillOnlyTheFirstRules() {
        val all = rules(3)
        val batch = run(all, ScriptedWriter(listOf({ rulesReply("only one") }))).single()
        assertEquals(mapOf(all[0].id to "only one"), batch)
    }

    @Test fun whenNothingComesBackNoBatchIsReported() {
        val model = ScriptedWriter(listOf({ throw LLMError.EmptyReply() }, { rulesReply("", "") }))
        assertTrue(run(rules(12), model).isEmpty())
        assertEquals(2, model.calls.size)
    }

    @Test fun noRulesMeansNoCall() {
        val model = ScriptedWriter(emptyList())
        assertTrue(run(emptyList(), model).isEmpty())
        assertTrue(model.calls.isEmpty())
    }

    @Test fun aModelOnThePhoneIsToldNotToThink() {
        val onDevice = ScriptedWriter(listOf({ rulesReply("a") }), isOnDevice = true)
        run(rules(1), onDevice)
        assertEquals(RuleWriter.prompt(rules(1)) + "\n/no_think", onDevice.calls.single().turns.last().text)
        val hosted = ScriptedWriter(listOf({ rulesReply("a") }))
        run(rules(1), hosted)
        assertFalse(hosted.calls.single().turns.last().text.contains("/no_think"))
    }

    @Test fun aCancelledRunMakesNoFurtherCall() {
        val model = ScriptedWriter(listOf({ rulesReply(*Array(10) { "a$it" }) }, { rulesReply("b0") }))
        runBlocking {
            val job = launch { RuleWriter.write(rules(12), model) {} }
            model.onCall = { if (it == 0) job.cancel() }
            job.join()
        }
        assertEquals(1, model.calls.size)
    }

    @Test fun cancellationInsideACallIsNotSwallowedAsAFailedBatch() {
        val model = ScriptedWriter(listOf({ throw CancellationException("stopped") }, { rulesReply("b0") }))
        try {
            runBlocking { RuleWriter.write(rules(12), model) {} }
            fail("the cancellation should reach the caller")
        } catch (e: CancellationException) {
            assertEquals(1, model.calls.size)
        }
    }
}
