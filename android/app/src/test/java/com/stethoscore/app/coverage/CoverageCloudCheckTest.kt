package com.stethoscore.app.coverage

import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMError
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.reading.BookPages
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException

/**
 * The AI check's engine (ios/RedPen/Shared/Coverage/CoverageCloudCheck.swift): what it
 * asks, how it reads the answer, how it matches a verdict to a subtopic, and
 * what it keeps. iOS has no test of these - its CoverageTests are MCQCoverage's,
 * already ported - so the expectations here are worked out by hand from the
 * Swift source, line by line, and the iOS line each one rests on is named.
 */
class CoverageCloudCheckTest {
    @get:Rule val folder = TemporaryFolder()

    // fixtures

    private fun sub(area: String, name: String, evidence: Int = 0, practice: Int = 0, answered: Int = 0, correct: Int = 0, samples: List<String> = emptyList()) =
        SubtopicCoverage(area, SyllabusSubtopic(name, listOf(name.lowercase())), evidence, practice, answered, correct, samples,
            CoverageEngine.status(evidence, practice, answered, correct))

    private fun area(name: String, vararg subs: SubtopicCoverage) = AreaCoverage(SyllabusArea(name, subs.map { it.subtopic }), subs.toList())

    private fun set(name: String, subject: String = "Cardiology", sources: List<SourceDoc> = emptyList(), book: String = "") =
        StudySet(name = name, subject = subject, kind = StudySetKind.MCQ, sources = sources, bookMarkdown = book,
            questions = listOf(MCQQuestion(stem = "q", options = listOf("a", "b"), correctIndex = 0)))

    private val cardiology = area("Cardiology",
        sub("Cardiology", "Heart failure", 6, 4, 10, 7, listOf("Which drug lowers mortality in HFrEF? Ramipril", "Furosemide for oedema")),
        sub("Cardiology", "Arrhythmias"))

    // the prompt

    @Test fun thePromptIsIosWordForWord() {
        // iOS prompt(for:), :87-145, worked out by hand. The digest's first line is blank, so it
        // joins the subtopic list with one newline, not two (head + body, :142-144).
        val expected = listOf(
            "You are checking how well a medical student's revision library covers the General revision syllabus, area \"Cardiology\".",
            "For each subtopic below, judge from the digest whether the library covers it: \"covered\" (enough material, including questions or cards, to revise it for the exam), \"thin\" (mentioned, but too little or reading only), or \"missing\" (nothing on it).",
            "Judge meaning, not keywords: a question on warfarin reversal covers anticoagulation even if the word is not used, and a passing mention is not coverage.",
            "Reply with ONLY this JSON and nothing else:",
            "{\"subtopics\":[{\"id\":\"s1\",\"status\":\"covered\"|\"thin\"|\"missing\",\"evidence\":\"<under 15 words: what in the library shows it>\",\"suggestion\":\"<under 20 words: what to add>\"}]}",
            "",
            "SUBTOPICS (id: name - what a keyword search found)",
            "s1: Heart failure - 6 items, 4 of them questions/cards, 70% of 10 answers right",
            "s2: Arrhythmias - nothing",
            "ITEMS THAT MATCHED (tagged with the subtopic that found them)",
            "[s1] Which drug lowers mortality in HFrEF? Ramipril",
            "[s1] Furosemide for oedema",
            "",
            "THE LIBRARY'S SETS (name - subject - kind, size)",
            "Cardio MCQs - Cardiology - MCQ, 1 questions",
            "",
            "LECTURE AND TEXTBOOK PAGES (first line of each)",
            "(none)",
        ).joinToString("\n")
        assertEquals(expected, CoverageCloudCheck.prompt(cardiology, ExamTrack.general, listOf(set("Cardio MCQs"))))
    }

    @Test fun theExamIsNamedByItsTitle() {
        val text = CoverageCloudCheck.prompt(cardiology, ExamTrack.plab, emptyList())
        assertTrue(text.startsWith("You are checking how well a medical student's revision library covers the PLAB 1 & 2 syllabus, area \"Cardiology\"."))
    }

    @Test fun aSubtopicWithNothingSaysNothingAndOneWithAnswersSaysHowTheyWent() {
        // :96-105: "nothing"; else "<n> items, <m> of them questions/cards" (always "items"); then the answers
        val text = CoverageCloudCheck.prompt(area("A",
            sub("A", "One", 1, 0),
            sub("A", "None"),
            sub("A", "Rounded", 3, 1, 3, 1)), ExamTrack.general, emptyList())
        assertTrue(text, text.contains("\ns1: One - 1 items, 0 of them questions/cards\n"))
        assertTrue(text, text.contains("\ns2: None - nothing\n"))
        // 1 of 3 right is 33%
        assertTrue(text, text.contains("\ns3: Rounded - 3 items, 1 of them questions/cards, 33% of 3 answers right\n"))
    }

    @Test fun samplesAreFourASubtopicFortyInAllAndEachOnce() {
        // :108-120: prefix(4) per subtopic, at most 40 shown, a sample the AI has seen is not listed again
        val many = (1..12).map { n -> sub("A", "Sub $n", 5, 3, samples = (1..5).map { "item $n.$it" }) }
        val text = CoverageCloudCheck.prompt(area("A", *many.toTypedArray()), ExamTrack.general, emptyList())
        val matched = text.lines().filter { Regex("^\\[s\\d+] ").containsMatchIn(it) }
        assertEquals(40, matched.size)
        assertEquals("[s1] item 1.1", matched.first())
        assertEquals("[s10] item 10.4", matched.last())
        assertFalse("a fifth sample is left out", text.contains("item 1.5"))
        assertFalse("past forty nothing more", text.contains("[s11]"))

        val shared = CoverageCloudCheck.prompt(area("A",
            sub("A", "One", 2, 1, samples = listOf("same", "only one")),
            sub("A", "Two", 2, 1, samples = listOf("same", "only two"))), ExamTrack.general, emptyList())
        assertEquals(listOf("[s1] same", "[s1] only one", "[s2] only two"), shared.lines().filter { it.startsWith("[s") })
    }

    @Test fun withNoMatchesTheDigestSaysSo() {
        val text = CoverageCloudCheck.prompt(area("A", sub("A", "One")), ExamTrack.general, emptyList())
        assertTrue(text, text.contains("ITEMS THAT MATCHED (tagged with the subtopic that found them)\n(none)\n"))
    }

    @Test fun onlyTheFirstEightySetsAreListed() {
        val sets = (1..100).map { set("Set number $it") }
        val text = CoverageCloudCheck.prompt(cardiology, ExamTrack.general, sets)
        assertTrue(text.contains("Set number 80 - Cardiology - MCQ, 1 questions"))
        assertFalse(text.contains("Set number 81 "))
    }

    @Test fun lectureHeadingsAndBookTitlesAreListedOncePerSource() {
        val lecture = SourceDoc(id = "lec", name = "Lecture 1", pages = listOf(
            SourcePage(1, "  Heart failure\nmore on the page"), SourcePage(2, "\n \n"), SourcePage(3, "Arrhythmias")))
        val book = "# Cardiology\ntext\n## Valves\nmore"
        val text = CoverageCloudCheck.prompt(cardiology, ExamTrack.general,
            listOf(set("First", sources = listOf(lecture)), set("Second", sources = listOf(lecture), book = book)))
        val titles = BookPages.split(book).map { it.title }
        assertTrue(titles.isNotEmpty())
        val tail = text.substringAfter("LECTURE AND TEXTBOOK PAGES (first line of each)\n").lines()
        // the lecture kept by two sets is read once (:130-135); a blank page has no heading (:133)
        assertEquals(listOf("Lecture 1: Heart failure | Arrhythmias", "Second: " + titles.joinToString(" | ")), tail)
    }

    @Test fun aPagesHeadingIsItsFirstLineWithAnythingOnIt_EightyCharactersAtMost() {
        // SourceDoc.swift:69-75
        assertEquals("Heart failure", CoverageCloudCheck.heading("\n \t Heart failure \nsecond"))
        assertEquals("", CoverageCloudCheck.heading(" \n\t\n"))
        assertEquals("x".repeat(80), CoverageCloudCheck.heading("x".repeat(100)))
    }

    @Test fun aRequestNeverPassesThirtyThousandCharactersAndTheInstructionsAreKept() {
        // :142-144: the digest is cut, never the instructions
        val sets = (1..100).map { set("S$it " + "long name ".repeat(40)) }
        val text = CoverageCloudCheck.prompt(cardiology, ExamTrack.general, sets)
        assertEquals(CoverageCloudCheck.requestLimit, text.length)
        assertTrue(text.contains("Reply with ONLY this JSON and nothing else:"))
        assertTrue(text.contains("s2: Arrhythmias - nothing"))
        // a short one is not padded or cut
        assertTrue(CoverageCloudCheck.prompt(cardiology, ExamTrack.general, emptyList()).length < 3_000)
    }

    @Test fun theLimitCountsCharactersTheWayASwiftStringDoes() {
        // String.count and prefix go by user-perceived characters: a letter with its accent, or an emoji, is one
        assertEquals(2, CoverageCloudCheck.characterCount("e\u0301x"))
        assertEquals(1, CoverageCloudCheck.characterCount("\uD83D\uDE00"))
        assertEquals("ab", CoverageCloudCheck.characterPrefix("abc", 2))
        assertEquals("e\u0301a", CoverageCloudCheck.characterPrefix("e\u0301ab", 2))
        assertEquals("\uD83D\uDE00a", CoverageCloudCheck.characterPrefix("\uD83D\uDE00ab", 2))
        assertEquals("", CoverageCloudCheck.characterPrefix("abc", 0))
        assertEquals("abc", CoverageCloudCheck.characterPrefix("abc", 10))
    }

    // reading a reply and matching it to the subtopics

    private val area3 = area("Cardiology", sub("Cardiology", "Heart failure"), sub("Cardiology", "Arrhythmias"), sub("Cardiology", "Valves"))

    private fun reply(vararg entries: String) = "{\"subtopics\":[${entries.joinToString(",")}]}"

    private fun entry(id: String, status: String, evidence: String = "e", suggestion: String = "s") =
        "{\"id\":\"$id\",\"status\":\"$status\",\"evidence\":\"$evidence\",\"suggestion\":\"$suggestion\"}"

    @Test fun aVerdictIsMatchedToItsSubtopicByNumberAndKeyedByAreaAndName() {
        val found = CoverageCloudCheck.parse(reply(entry("s1", "covered", "Ten questions", "Add cards"), entry("s3", "missing")), area3)
        assertEquals(setOf("Cardiology/Heart failure", "Cardiology/Valves"), found.keys)
        assertEquals(CoverageVerdict(CoverageVerdict.Status.covered, "Ten questions", "Add cards"), found["Cardiology/Heart failure"])
        assertEquals(CoverageStatus.notCovered, found["Cardiology/Valves"]!!.status.coverage)
        // the key is what the screen looks a row up by
        assertEquals(area3.subtopics[0].id, "Cardiology/Heart failure")
    }

    @Test fun theIdIsReadTheWayIosReadsIt() {
        // :207: the id lowercased, every "s" removed, read as an integer; :208: it must name a subtopic
        val found = CoverageCloudCheck.parse(reply(entry("S2", "thin"), entry("s0", "thin"), entry("s4", "thin"), entry("s-1", "thin"),
            entry("sx", "thin"), entry("", "thin"), entry("s 1", "thin"), entry("ss3", "covered")), area3)
        assertEquals(setOf("Cardiology/Arrhythmias", "Cardiology/Valves"), found.keys)
        assertEquals(CoverageVerdict.Status.thin, found["Cardiology/Arrhythmias"]!!.status)
        assertEquals(CoverageVerdict.Status.covered, found["Cardiology/Valves"]!!.status)
        // a plus sign is an integer's sign too
        assertEquals(setOf("Cardiology/Heart failure"), CoverageCloudCheck.parse(reply(entry("+1", "covered")), area3).keys)
    }

    @Test fun anIdThatIsNotATextIsSkipped() {
        val found = CoverageCloudCheck.parse(
            reply("{\"id\":1,\"status\":\"covered\"}", "{\"status\":\"covered\"}", entry("s2", "covered")), area3)
        assertEquals(setOf("Cardiology/Arrhythmias"), found.keys)
    }

    @Test fun aStatusIsReadInAnyCaseSpacingAndPunctuation() {
        // Status.read, :11-22
        for (word in listOf("covered", "Covered", "WELL COVERED", "well_covered", "fully-covered", " covered. ", "\"covered\"")) {
            assertEquals(word, CoverageVerdict.Status.covered, CoverageVerdict.Status.read(word))
        }
        for (word in listOf("thin", "Partial", "partly covered", "partially_covered", "Thin!")) {
            assertEquals(word, CoverageVerdict.Status.thin, CoverageVerdict.Status.read(word))
        }
        for (word in listOf("missing", "Not covered", "not_covered", "not-covered", "notcovered", "UNCOVERED", "absent", "none", "(missing)")) {
            assertEquals(word, CoverageVerdict.Status.missing, CoverageVerdict.Status.read(word))
        }
    }

    @Test fun aStatusItDoesNotKnowIsNeverGuessedAsCovered() {
        for (word in listOf("", "ok", "good", "mostly covered", "covered and thin", "yes", "not")) {
            assertNull(word, CoverageVerdict.Status.read(word))
        }
        val found = CoverageCloudCheck.parse(reply(entry("s1", "adequate"), "{\"id\":\"s2\",\"status\":3}", "{\"id\":\"s3\"}"), area3)
        assertTrue(found.isEmpty())
    }

    @Test fun theStatusesMeetTheKeywordEnginesScale() {
        assertEquals(CoverageStatus.covered, CoverageVerdict.Status.covered.coverage)
        assertEquals(CoverageStatus.thin, CoverageVerdict.Status.thin.coverage)
        assertEquals(CoverageStatus.notCovered, CoverageVerdict.Status.missing.coverage)
    }

    @Test fun evidenceAndSuggestionAreOptional() {
        val found = CoverageCloudCheck.parse(reply("{\"id\":\"s1\",\"status\":\"thin\"}", "{\"id\":\"s2\",\"status\":\"thin\",\"evidence\":null,\"suggestion\":4}"), area3)
        assertEquals(CoverageVerdict(CoverageVerdict.Status.thin, "", ""), found["Cardiology/Heart failure"])
        assertEquals(CoverageVerdict(CoverageVerdict.Status.thin, "", ""), found["Cardiology/Arrhythmias"])
    }

    @Test fun aReplyInACodeFenceOrWithWordsAroundItIsRead() {
        val json = reply(entry("s1", "covered"))
        assertEquals(1, CoverageCloudCheck.parse("```json\n$json\n```", area3).size)
        assertEquals(1, CoverageCloudCheck.parse("Here you go: $json Hope that helps.", area3).size)
    }

    @Test fun aReplyThatCannotBeReadGivesNothingRatherThanAGuess() {
        for (text in listOf("", "no json at all", "{", "}{", "{\"subtopics\":", "{\"other\":[]}", "{\"subtopics\":\"covered\"}", "[1,2]")) {
            assertTrue(text, CoverageCloudCheck.parse(text, area3).isEmpty())
        }
    }

    @Test fun aListWithAnythingInItThatIsNotAnObjectIsNoListAtAll() {
        // iOS casts the list to [[String: Any]] in one go (:203), so one stray item loses the lot
        assertTrue(CoverageCloudCheck.parse("{\"subtopics\":[${entry("s1", "covered")},\"s2\"]}", area3).isEmpty())
        assertTrue(CoverageCloudCheck.parse("{\"subtopics\":[${entry("s1", "covered")},null]}", area3).isEmpty())
        assertEquals(1, CoverageCloudCheck.parse("{\"subtopics\":[${entry("s1", "covered")},{}]}", area3).size)
    }

    @Test fun theLaterOfTwoVerdictsForOneSubtopicStands() {
        val found = CoverageCloudCheck.parse(reply(entry("s1", "missing"), entry("s1", "covered")), area3)
        assertEquals(CoverageVerdict.Status.covered, found["Cardiology/Heart failure"]!!.status)
    }

    // asking

    private val owner = FakeServer.standInKey()

    @Test fun oneRequestIsTheWritersRouteWithThePreferredModelAsked() = runBlocking {
        val server = FakeServer { FakeServer.chat("{\"subtopics\":[]}") }
        val sent = CoverageCloudCheck.send(server.client(owner), "the prompt")
        assertEquals("{\"subtopics\":[]}", sent.content)
        val request = server.requests.single()
        assertEquals("/v1/chat/completions", request.path)
        assertEquals(owner, request.bearer)
        val body = request.body!!
        // :161-167
        assertEquals("cramdown-writer", body.getString("model"))
        assertEquals(CoverageCloudCheck.preferredModel, body.getString("prefer"))
        assertEquals(4000, body.getInt("max_tokens"))
        assertEquals(0.2, body.getDouble("temperature"), 0.0)
        val message = body.getJSONArray("messages").getJSONObject(0)
        assertEquals(1, body.getJSONArray("messages").length())
        assertEquals("user", message.getString("role"))
        assertEquals("the prompt", message.getString("content"))
    }

    @Test fun theModelThatAnsweredIsTheSourceThenTheModelThenNothing() = runBlocking {
        fun answer(extra: JSONObject.() -> Unit) = FakeServer {
            FakeServer.ok(JSONObject().put("choices", JSONArray().put(JSONObject().put("message", JSONObject().put("content", "x")))).apply(extra))
        }
        assertEquals("a", CoverageCloudCheck.send(answer { put("source", "a").put("model", "b") }.client(owner), "p").source)
        assertEquals("b", CoverageCloudCheck.send(answer { put("model", "b") }.client(owner), "p").source)
        assertEquals("", CoverageCloudCheck.send(answer { }.client(owner), "p").source)
    }

    @Test fun aReplyWithNoTextIsSaidSoInTheCloudChecksWords() = runBlocking {
        for (body in listOf(JSONObject(), JSONObject().put("choices", JSONArray()),
            JSONObject().put("choices", JSONArray().put(JSONObject().put("message", JSONObject().put("content", ""))))))
            try {
                CoverageCloudCheck.send(FakeServer { FakeServer.ok(body) }.client(owner), "p")
                fail("a reply with no text is a failure")
            } catch (e: CoverageCloudCheck.Failure) {
                assertEquals("The cloud check sent back nothing.", e.message)
            }
    }

    private fun refused(status: Int, body: String): String = runBlocking {
        try {
            CoverageCloudCheck.send(FakeServer { BackendClient.Reply(status, body) }.client(owner), "p")
            "no failure"
        } catch (e: CoverageCloudCheck.Failure) { e.message!! }
    }

    @Test fun aRefusalIsReadAsEveryOtherCallToTheWorkerReadsIt() {
        // AuthAPI.failure with the cloud check's two fallbacks (:179-181)
        assertEquals("The cloud check is part of Pro.", refused(402, "{}"))
        assertEquals("Pro only, sorry.", refused(402, "{\"message\":\"Pro only, sorry.\"}"))
        assertEquals("Please sign in again.", refused(401, "{}"))
        assertEquals("Cloud AI needs your permission first.", refused(428, "{\"code\":\"ai_consent_required\"}"))
        assertEquals("Too many requests just now. Try again in a moment.", refused(429, "{}"))
        assertEquals("The cloud check did not answer.", refused(500, "{}"))
        assertEquals("The model is resting.", refused(503, "{\"error\":\"The model is resting.\"}"))
        assertEquals("That group is full.", refused(409, "{\"code\":\"full\",\"message\":\"That group is full.\"}"))
        assertEquals("That has ended or is no longer available.", refused(410, "{}"))
        assertEquals("Sign-in isn't set up in this build yet.", refused(404, "{\"message\":\"No such endpoint.\"}"))
    }

    @Test fun noConnectionIsSaidAsIosSaysIt() = runBlocking {
        val offline = BackendClient.Transport { _, _, _, _, _ -> throw IOException("down") }
        try {
            CoverageCloudCheck.send(BackendClient(FakeServer.BASE, { owner }, offline), "p")
            fail("offline is a failure")
        } catch (e: CoverageCloudCheck.Failure) {
            assertEquals("No connection. Signing in needs one — studying does not.", e.message)
        }
    }

    @Test fun theOwnerKeyIsStoppedAtItsCapBeforeAnythingIsSent() = runBlocking {
        val server = FakeServer { FakeServer.chat("{}") }
        val meter = OwnerSpend(OwnerSpend.MemoryStore(OwnerSpend.CAP_MICROS))
        try {
            CoverageCloudCheck.send(server.client(owner), "p", meter)
            fail("past the cap nothing is sent")
        } catch (e: LLMError.NotReady) {
            assertEquals(OwnerSpend.CAP_REACHED, e.message)
        }
        assertTrue(server.requests.isEmpty())
    }

    @Test fun eachReplyIsCountedAgainstTheCapAtItsWorstCase() = runBlocking {
        val meter = OwnerSpend(OwnerSpend.MemoryStore())
        CoverageCloudCheck.send(FakeServer { FakeServer.chat("{}") }.client(owner), "twelve chars", meter)
        assertEquals(OwnerSpend.estimateMicros("twelve chars".length, CoverageCloudCheck.maxTokens), meter.spentMicros)
        // a request that failed cost nothing
        val before = meter.spentMicros
        refusedWith(meter)
        assertEquals(before, meter.spentMicros)
    }

    private fun refusedWith(meter: OwnerSpend) = runBlocking {
        try { CoverageCloudCheck.send(FakeServer { BackendClient.Reply(500, "{}") }.client(owner), "p", meter) } catch (_: CoverageCloudCheck.Failure) { }
    }

    @Test fun theModelsGetFriendlyNames() {
        assertEquals("Gemini 3.1 Pro", CoverageCloudCheck.displayName(CoverageCloudCheck.preferredModel))
        assertEquals("the cloud model", CoverageCloudCheck.displayName(""))
        assertEquals("some-other-model", CoverageCloudCheck.displayName("some-other-model"))
    }

    @Test fun aCheckKnowsWhetherThePreferredModelAnswered() {
        fun check(vararg sources: String) = CoverageCheck("general", 0, sources.toList(), emptyMap())
        assertTrue(check(CoverageCloudCheck.preferredModel).byPreferredModel)
        assertFalse(check().byPreferredModel)
        assertFalse(check(CoverageCloudCheck.preferredModel, "other").byPreferredModel)
        assertEquals("other", check("other", CoverageCloudCheck.preferredModel).source)
        assertEquals("", check().source)
    }

    // kept checks

    private val made = CoverageCheck("general", 1_700_000_000_000, listOf("a", "b"),
        mapOf("Cardiology/Heart failure" to CoverageVerdict(CoverageVerdict.Status.thin, "Two questions", "Add cards")), listOf("Renal"))

    @Test fun aCheckIsKeptAndComesBack() {
        val dir = folder.newFolder("kept")
        CoverageCloudCheck.save(dir, made, ExamTrack.general)
        assertEquals(made, CoverageCloudCheck.load(dir, ExamTrack.general))
    }

    @Test fun eachExamHasItsOwnCheck() {
        val dir = folder.newFolder("exams")
        CoverageCloudCheck.save(dir, made, ExamTrack.general)
        CoverageCloudCheck.save(dir, made.copy(track = "plab", failedAreas = emptyList()), ExamTrack.plab, "neetpg+")
        assertEquals(made, CoverageCloudCheck.load(dir, ExamTrack.general))
        assertNull(CoverageCloudCheck.load(dir, ExamTrack.plab))
        assertEquals("plab", CoverageCloudCheck.load(dir, ExamTrack.plab, "neetpg+")!!.track)
        assertNull(CoverageCloudCheck.load(dir, ExamTrack.plab, "fmge+"))
    }

    @Test fun anExampleIsNeverKeptAndNothingKeptIsNothing() {
        val dir = folder.newFolder("example")
        CoverageCloudCheck.save(dir, made.copy(isExample = true), ExamTrack.general)
        assertNull(CoverageCloudCheck.load(dir, ExamTrack.general))
        assertNull(CoverageCloudCheck.load(java.io.File(dir, "missing"), ExamTrack.general))
    }

    @Test fun aKeptFileThatCannotBeReadIsNoCheck() {
        val dir = folder.newFolder("broken")
        java.io.File(dir, "check-general.json").writeText("{ not json")
        assertNull(CoverageCloudCheck.load(dir, ExamTrack.general))
        java.io.File(dir, "check-general.json").writeText("{\"track\":\"general\"}")
        assertNull(CoverageCloudCheck.load(dir, ExamTrack.general))
    }

    @Test fun aNewerCheckReplacesTheOlder() {
        val dir = folder.newFolder("replaced")
        CoverageCloudCheck.save(dir, made, ExamTrack.general)
        CoverageCloudCheck.save(dir, made.copy(date = 5, sources = listOf("c")), ExamTrack.general)
        assertEquals(5L, CoverageCloudCheck.load(dir, ExamTrack.general)!!.date)
        assertEquals(listOf("check-general.json"), dir.list()!!.toList())
    }
}
