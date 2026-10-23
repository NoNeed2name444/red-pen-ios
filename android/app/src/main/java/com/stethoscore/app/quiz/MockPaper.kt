package com.stethoscore.app.quiz

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlin.math.ceil
import kotlin.math.floor

// A port of ios/RedPen/Shared/Exam/MockPaper.swift: an exam-faithful
// mock paper, the real paper's length and clock for the student's exam,
// drawn from their own library, with nothing said about right or wrong until
// the end. With it Features/Mock/MockSittingSave.swift (the sitting kept on
// disk), ExamStore's MockRecord (the past sittings) and InsightModels'
// PassMark. Plain Kotlin, tested on the JVM (ExamToolsTest, MockSittingSaveTest).

/**
 * One timed part of a sitting: a PLAB paper, an MRCP paper, one USMLE block.
 * A section's time is its own: time left over does not carry into the next,
 * and once a section is closed its questions cannot be gone back to.
 */
data class MockSectionSpec(val title: String, val questions: Int, val minutes: Int)

/** A paper as the exam sets it. */
data class MockPaperSpec(val id: String, val title: String, val sections: List<MockSectionSpec>, val note: String) {
    val questionCount: Int get() = sections.sumOf { it.questions }
    val minutes: Int get() = sections.sumOf { it.minutes }
}

/** The papers each exam sits. */
object MockFormat {
    /** USMLE Step 1 sits up to seven 60-minute blocks of up to 40 questions. */
    const val usmleBlockQuestions = 40
    const val usmleBlockMinutes = 60
    const val usmleMaxBlocks = 7
    /** The mock's word for one of those timed parts: "Part 1", "Part 2 of 3". The owner's choice (22 Oct): "Block" is the focus timer's word only. */
    const val partWord = "Part"
    /** "part 2 of 3", inside a sentence. */
    fun partOf(n: Int, count: Int): String = "${partWord.lowercase()} $n of $count"
    /** "between parts", inside a sentence. */
    val betweenParts: String = "between ${partWord.lowercase()}s"
    /** The break's heading: "Part 2 closed". */
    fun partClosed(n: Int): String = "$partWord $n closed"
    /** The break's line about what comes next. */
    fun nextPartLine(questions: Int, time: String): String =
        "Next ${partWord.lowercase()}: $questions questions in $time. Its clock starts when you do."
    /** The clock's spoken label. */
    fun minutesLeft(minutes: Int): String = "$minutes minutes left in this ${partWord.lowercase()}"
    /** Said before a part is closed. */
    val closedForGood: String = "A closed ${partWord.lowercase()} can\u2019t be reopened."
    /** How a sitting runs, as the paper screen lists it. */
    val rules: List<String> = listOf(
        "The clock is strict: when a ${partWord.lowercase()}\u2019s time is up it closes, answered or not.",
        "Flag and jump between questions within a ${partWord.lowercase()}; a closed ${partWord.lowercase()} can\u2019t be reopened.",
        "Cross out options, highlight the stem, and open lab values or the calculator from More.",
        "Your score, by subject, comes at the end with every answer explained.",
    )

    /** The papers a track offers. USMLE's is built from a count of blocks. */
    fun papers(track: ExamTrack, usmleBlocks: Int = 2): List<MockPaperSpec> = when (track) {
        ExamTrack.plab -> listOf(MockPaperSpec("plab1", "PLAB 1 paper", listOf(MockSectionSpec("PLAB 1", 180, 180)),
            "180 single-best-answer questions in 3 hours, as the GMC sets it."))
        ExamTrack.mrcp -> {
            val note = "MRCP(UK) Part 1 is two papers of 100 best-of-five questions, 3 hours each, on one day. Sit one now and the other later."
            listOf(MockPaperSpec("mrcp1", "MRCP Part 1, paper 1", listOf(MockSectionSpec("Paper 1", 100, 180)), note),
                MockPaperSpec("mrcp2", "MRCP Part 1, paper 2", listOf(MockSectionSpec("Paper 2", 100, 180)), note))
        }
        ExamTrack.mrcs -> {
            // the colleges publish the times, not a fixed count: Part A's pace is about a question a minute
            val note = "MRCS Part A is Applied Basic Sciences (3 hours) and Principles of Surgery-in-General (2 hours) on one day. The colleges publish the times rather than a fixed question count, so this keeps Part A's pace of about a question a minute."
            listOf(MockPaperSpec("mrcsa1", "MRCS A, Applied Basic Sciences", listOf(MockSectionSpec("Paper 1", 180, 180)), note),
                MockPaperSpec("mrcsa2", "MRCS A, Principles of Surgery", listOf(MockSectionSpec("Paper 2", 120, 120)), note))
        }
        ExamTrack.usmle -> {
            val count = usmleBlocks.coerceIn(1, usmleMaxBlocks)
            val blocks = (1..count).map { MockSectionSpec("$partWord $it", usmleBlockQuestions, usmleBlockMinutes) }
            val note = "Step 1-style ${partWord.lowercase()}s: up to 40 questions in 60 minutes each. The real exam has up to seven, with break time between them."
            listOf(MockPaperSpec("usmle$count", "USMLE-style, $count ${partWord.lowercase()}" + (if (count == 1) "" else "s"), blocks, note))
        }
        ExamTrack.general -> listOf(MockPaperSpec("general", "Practice paper", listOf(MockSectionSpec("Paper", 100, 125)),
            "100 questions in 2 hours 5 minutes. Pick your exam in Settings for its real paper."))
    }
}

/** A question the paper may use: only what assembly needs. */
data class MockCandidate(val id: String, val subject: String)

/** A paper put together from the library. */
data class MockAssembly(
    /** The sections as they will be sat. Short when the library is short: each keeps the real paper's pace. */
    val sections: List<MockSectionSpec>,
    /** Question ids, section by section. */
    val questionIds: List<List<String>>,
    /** How many the real paper has. */
    val wanted: Int,
    /** Said before starting, when the library cannot fill the paper. */
    val shortfallNote: String?,
) {
    val count: Int get() = questionIds.sumOf { it.size }
    val isShort: Boolean get() = count < wanted
}

/**
 * A source of random numbers drawn the way Swift's RandomNumberGenerator is,
 * so a seeded paper comes out the same as it would on iOS.
 */
interface MockRandom {
    fun next(): ULong

    /** Lemire's nearly divisionless draw below [upperBound], as Swift's next(upperBound:). */
    fun next(upperBound: ULong): ULong {
        var random = next()
        var high = highBits(random, upperBound)
        var low = random * upperBound
        if (low < upperBound) {
            val t = (0uL - upperBound) % upperBound
            while (low < t) {
                random = next()
                high = highBits(random, upperBound)
                low = random * upperBound
            }
        }
        return high
    }

    /** Fisher-Yates from the front, as Swift's MutableCollection.shuffle(using:). */
    fun <T> shuffled(items: List<T>): List<T> {
        val out = items.toMutableList()
        var amount = out.size
        var current = 0
        while (amount > 1) {
            val other = current + next(amount.toULong()).toInt()
            amount -= 1
            val held = out[current]; out[current] = out[other]; out[other] = held
            current += 1
        }
        return out
    }

    companion object {
        /** The system's own randomness, for a paper sat for real. */
        fun system(): MockRandom = object : MockRandom {
            private val source = SecureRandom()
            override fun next(): ULong = source.nextLong().toULong()
        }

        private fun highBits(a: ULong, b: ULong): ULong {
            val mask = 0xFFFFFFFFuL
            val aLo = a and mask; val aHi = a shr 32
            val bLo = b and mask; val bHi = b shr 32
            val loLo = aLo * bLo
            val hiLo = aHi * bLo
            val loHi = aLo * bHi
            val hiHi = aHi * bHi
            val cross = (loLo shr 32) + (hiLo and mask) + loHi
            return hiHi + (hiLo shr 32) + (cross shr 32)
        }
    }
}

/** A small seeded generator for repeatable assembly in tests (xorshift, as iOS's). */
class MockSeededGenerator(seed: ULong) : MockRandom {
    private var state: ULong = if (seed == 0uL) 0x9E3779B97F4A7C15uL else seed
    override fun next(): ULong {
        state = state xor (state shl 13)
        state = state xor (state shr 7)
        state = state xor (state shl 17)
        return state
    }
}

object MockAssembler {
    /** Below this there is no paper worth the name. */
    const val minimumQuestions = 10

    /**
     * Draws a paper from [pool], spreading it across subjects the way a real
     * paper spreads across the syllabus: one question from each subject in
     * turn, so a big deck in one subject cannot fill the paper on its own.
     * Order within the paper is then shuffled. Null when there are fewer than
     * [minimumQuestions].
     */
    fun assemble(spec: MockPaperSpec, pool: List<MockCandidate>, rng: MockRandom = MockRandom.system()): MockAssembly? {
        val unique = dedupe(pool)
        if (unique.size < minimumQuestions) return null
        val wanted = spec.questionCount
        val picked = spread(unique, wanted, rng)
        val order = rng.shuffled(picked)
        val sections = fitted(spec.sections, order.size)
        val ids = ArrayList<List<String>>()
        var at = 0
        for (section in sections) {
            val end = at + section.questions
            ids.add(order.subList(at, end).map { it.id })
            at = end
        }
        val note = if (order.size < wanted) shortfall(order.size, spec, sections) else null
        return MockAssembly(sections, ids, wanted, note)
    }

    /** What is said when the library can't fill the paper. */
    fun shortfall(have: Int, spec: MockPaperSpec, sections: List<MockSectionSpec>): String {
        val minutes = sections.sumOf { it.minutes }
        return "Your library has $have questions; ${spec.title} has ${spec.questionCount}. This mock uses all $have at the real paper's pace ($minutes min), so it is shorter than the exam. Make more question sets to sit the full paper."
    }

    fun dedupe(pool: List<MockCandidate>): List<MockCandidate> {
        val seen = HashSet<String>()
        return pool.filter { seen.add(it.id) }
    }

    /** Round-robin across subjects, each subject's own order shuffled. */
    fun spread(pool: List<MockCandidate>, take: Int, rng: MockRandom): List<MockCandidate> {
        val bySubject = LinkedHashMap<String, MutableList<MockCandidate>>()
        for (c in pool) bySubject.getOrPut(c.subject) { ArrayList() }.add(c)
        val subjects = rng.shuffled(bySubject.keys.sorted())
        val queues = subjects.map { rng.shuffled(bySubject[it] ?: emptyList()) }
        val out = ArrayList<MockCandidate>()
        var round = 0
        while (out.size < take) {
            var any = false
            for (queue in queues) {
                if (round >= queue.size) continue
                any = true
                out.add(queue[round])
                if (out.size == take) break
            }
            if (!any) break
            round += 1
        }
        return out
    }

    /** The sections cut down to [count] questions: whole sections first, the last one short, each at the real paper's pace (at least a minute). */
    fun fitted(sections: List<MockSectionSpec>, count: Int): List<MockSectionSpec> {
        var left = count
        val out = ArrayList<MockSectionSpec>()
        for (s in sections) {
            if (left <= 0) continue
            val n = minOf(s.questions, left)
            var cut = s.copy(questions = n)
            if (n < s.questions) {
                val scaled = s.minutes.toDouble() * n / maxOf(1, s.questions)
                cut = cut.copy(minutes = maxOf(1, ceil(scaled).toInt()))
            }
            out.add(cut)
            left -= n
        }
        return out
    }
}

// MARK: - marking

/** One answer in a sitting, marked after the end. */
data class MockMark(
    val questionId: String,
    val subject: String,
    /** Null when it was left unanswered. */
    val picked: Int?,
    val correct: Boolean,
    val flagged: Boolean = false,
    /** Seconds the question was on screen, in total. */
    val seconds: Double = 0.0,
)

/** One subject's line on the results page. */
data class MockSubjectScore(val subject: String, val total: Int, val answered: Int, val correct: Int) {
    val fraction: Double get() = if (total == 0) 0.0 else correct.toDouble() / total
}

/** The results of a sitting. */
data class MockResult(
    val marks: List<MockMark>,
    val passMark: Double,
    /** What a wrong answer costs, as a share of a right one's marks (NEET-PG 1/4, INI-CET 1/3); 0 where nothing is taken off. */
    val penalty: Double = 0.0,
) {
    val total: Int get() = marks.size
    val correct: Int get() = marks.count { it.correct }
    val unanswered: Int get() = marks.count { it.picked == null }
    val wrong: Int get() = total - correct - unanswered
    /** The score as the exam marks it: right answers less the penalty for wrong ones, never below nothing. */
    val fraction: Double get() {
        if (total <= 0) return 0.0
        val net = correct - penalty * wrong
        return maxOf(0.0, net) / total
    }
    val passed: Boolean get() = fraction >= passMark

    /** By subject, weakest first; ties by name. */
    val bySubject: List<MockSubjectScore> get() {
        val rows = LinkedHashMap<String, MockSubjectScore>()
        for (m in marks) {
            val row = rows[m.subject] ?: MockSubjectScore(m.subject, 0, 0, 0)
            rows[m.subject] = row.copy(total = row.total + 1, answered = row.answered + (if (m.picked != null) 1 else 0),
                correct = row.correct + (if (m.correct) 1 else 0))
        }
        return rows.values.sortedWith(compareBy<MockSubjectScore> { it.fraction }.thenBy { it.subject })
    }

    /** Average seconds per question. */
    val secondsPerQuestion: Double get() = if (total == 0) 0.0 else marks.sumOf { it.seconds } / total
}

/** Negative marking: what the catalog's line means for the score and for whether to guess. */
object MockMarking {
    private val pattern = Regex("""-\s*(\d+(?:\.\d+)?)\s*(?:/\s*(\d+)|of\s*\+?\s*(\d+))?""")

    /** A wrong answer's cost as a share of a right answer's marks: "-1 of +4" is 0.25, "-1/3" is 1/3, nothing readable is 0. */
    fun penalty(marking: String?): Double {
        val match = marking?.let { pattern.find(it) } ?: return 0.0
        fun number(i: Int): Double? = match.groups[i]?.value?.toDoubleOrNull()
        val lost = number(1) ?: return 0.0
        val per = number(2) ?: number(3) ?: 1.0
        return if (per > 0) lost / per else 0.0
    }

    /** What to do with a question the student cannot crack, from the expected marks of a guess. */
    fun guessAdvice(exam: String, marking: String?, options: Int): String {
        val p = penalty(marking)
        if (p <= 0 || marking == null) return "Never leave one blank: an unanswered question scores nothing."
        val n = maxOf(2, options)
        // a guess among k options gains (1 - p(k - 1)) / k on average
        val blind = 1 - p * (n - 1)
        if (blind > 1e-9) return "$exam marks $marking, but even a blind guess among $n gains marks on average: answer every question."
        if (blind > -1e-9) return "$exam marks $marking: a blind guess breaks even, so guess as soon as you can rule out one option and leave it blank only when you have no idea."
        var k = n - 1
        while (k > 2 && 1 - p * (k - 1) < -1e-9) k -= 1
        return "$exam marks $marking: guess when you are down to $k options, leave it blank when you have no idea."
    }
}

/** Where the student should be by now, the checkpoint pacing on the clock: "Q60 by 1:00". */
object MockPacing {
    fun target(elapsed: Double, questions: Int, minutes: Int): Int {
        val whole = maxOf(1, minutes).toDouble() * 60
        val share = minOf(1.0, maxOf(0.0, elapsed / whole))
        return floor(share * questions).toInt()
    }
}

/** The typical pass mark for a track, as a fraction - approximate (iOS PassMark). */
object PassMark {
    fun typical(track: ExamTrack): Double = when (track) {
        ExamTrack.usmle -> 0.60
        ExamTrack.plab -> 0.63
        ExamTrack.mrcp -> 0.60
        ExamTrack.mrcs -> 0.70
        ExamTrack.general -> 0.60
    }
}

// MARK: - the sitting on disk

/**
 * A mock paper part way through, kept on disk after every answer. A sitting
 * can run for three hours, and Android may end an app in the background at
 * any time: this is everything needed to put it back as it was.
 */
data class MockSittingSave(
    val title: String,
    val specs: List<MockSectionSpec>,
    /** The questions of each section, by id, in the order they were drawn. */
    val questionIds: List<List<String>>,
    val wanted: Int,
    /** The exam track, by its raw value. */
    val track: String,
    val passMark: Double?,
    val section: Int,
    val current: Int,
    val selected: Map<String, Int>,
    val orders: Map<String, List<Int>>,
    val flagged: Set<String>,
    val struck: Map<String, Set<Int>>,
    val highlights: Map<String, Set<Int>>,
    /** Seconds left on the open section's clock, or null between sections. The clock waits while the app is closed. */
    val secondsLeft: Double?,
    val onBreak: Boolean,
    val spent: Map<String, Double>,
    /** When the sitting started, in milliseconds since 1970 (kept to the second, as iOS's ISO 8601). */
    val startedAt: Long,
) {
    /** Answers given so far. */
    val answered: Int get() = selected.size
    /** Questions on the paper. */
    val total: Int get() = questionIds.sumOf { it.size }

    fun toJson(): JSONObject = JSONObject()
        .put("title", title)
        .put("specs", JSONArray(specs.map { JSONObject().put("title", it.title).put("questions", it.questions).put("minutes", it.minutes) }))
        .put("questionIds", JSONArray(questionIds.map { JSONArray(it) }))
        .put("wanted", wanted).put("track", track)
        .put("passMark", passMark ?: JSONObject.NULL)
        .put("section", section).put("current", current)
        .put("selected", JSONObject(selected))
        .put("orders", JSONObject().also { o -> orders.forEach { (k, v) -> o.put(k, JSONArray(v)) } })
        .put("flagged", JSONArray(flagged.toList()))
        .put("struck", JSONObject().also { o -> struck.forEach { (k, v) -> o.put(k, JSONArray(v.toList())) } })
        .put("highlights", JSONObject().also { o -> highlights.forEach { (k, v) -> o.put(k, JSONArray(v.toList())) } })
        .put("secondsLeft", secondsLeft ?: JSONObject.NULL)
        .put("onBreak", onBreak)
        .put("spent", JSONObject().also { o -> spent.forEach { (k, v) -> o.put(k, v) } })
        .put("startedAt", DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochSecond(Math.floorDiv(startedAt, 1000L))))

    companion object {
        private fun ints(a: JSONArray): List<Int> = (0 until a.length()).map { a.getInt(it) }
        private fun strings(a: JSONArray): List<String> = (0 until a.length()).map { a.getString(it) }
        private fun <T> map(o: JSONObject, value: (String) -> T): Map<String, T> = o.keys().asSequence().associateWith(value)

        fun fromJson(o: JSONObject): MockSittingSave {
            val specs = o.getJSONArray("specs")
            val ids = o.getJSONArray("questionIds")
            val orders = o.getJSONObject("orders")
            val struck = o.getJSONObject("struck")
            val highlights = o.getJSONObject("highlights")
            val spent = o.getJSONObject("spent")
            val selected = o.getJSONObject("selected")
            return MockSittingSave(
                title = o.getString("title"),
                specs = (0 until specs.length()).map { specs.getJSONObject(it).let { s -> MockSectionSpec(s.getString("title"), s.getInt("questions"), s.getInt("minutes")) } },
                questionIds = (0 until ids.length()).map { strings(ids.getJSONArray(it)) },
                wanted = o.getInt("wanted"),
                track = o.getString("track"),
                passMark = if (o.isNull("passMark")) null else o.getDouble("passMark"),
                section = o.getInt("section"),
                current = o.getInt("current"),
                selected = map(selected) { selected.getInt(it) },
                orders = map(orders) { ints(orders.getJSONArray(it)) },
                flagged = strings(o.getJSONArray("flagged")).toSet(),
                struck = map(struck) { ints(struck.getJSONArray(it)).toSet() },
                highlights = map(highlights) { ints(highlights.getJSONArray(it)).toSet() },
                secondsLeft = if (o.isNull("secondsLeft")) null else o.getDouble("secondsLeft"),
                onBreak = o.getBoolean("onBreak"),
                spent = map(spent) { spent.getDouble(it) },
                startedAt = Instant.parse(o.getString("startedAt")).toEpochMilli(),
            )
        }
    }
}

/** Where the sitting in progress is kept: one at a time, beside the library. */
object MockSittingStore {
    fun defaultFile(directory: File): File = File(directory, "mock-sitting.json")

    /** Written whole, then moved into place: a write cut short leaves the last good one. */
    fun save(sitting: MockSittingSave, file: File) {
        runCatching {
            file.parentFile?.mkdirs()
            val temporary = File(file.parentFile, file.name + ".tmp")
            temporary.writeText(sitting.toJson().toString())
            if (!temporary.renameTo(file)) { file.delete(); temporary.renameTo(file) }
        }
    }

    /** The sitting in progress, or null when there is none (or it cannot be read). */
    fun load(file: File): MockSittingSave? = runCatching { MockSittingSave.fromJson(JSONObject(file.readText())) }.getOrNull()

    /** Finished or left: nothing to resume. */
    fun clear(file: File) { file.delete() }
}

/** One mock sitting, as remembered (iOS ExamStore's MockRecord). */
data class MockRecord(
    val id: String = java.util.UUID.randomUUID().toString(),
    val date: Long = System.currentTimeMillis(),
    val title: String,
    val track: String,
    val correct: Int,
    val total: Int,
    val wanted: Int,
    val passMark: Double,
    val minutesUsed: Int,
    /** The marked score where it differs from the share right (negative marking). */
    val score: Double? = null,
) {
    val fraction: Double get() = score ?: if (total == 0) 0.0 else correct.toDouble() / total
}

/** The past sittings, newest first, at most fifty (iOS ExamStore.mocks). */
object MockRecords {
    const val cap = 50
    fun defaultFile(directory: File): File = File(directory, "exam-mocks.json")

    fun load(file: File): List<MockRecord> = runCatching {
        val a = JSONArray(file.readText())
        (0 until a.length()).map { i ->
            val o = a.getJSONObject(i)
            MockRecord(o.getString("id"), o.getLong("date"), o.getString("title"), o.getString("track"), o.getInt("correct"),
                o.getInt("total"), o.getInt("wanted"), o.getDouble("passMark"), o.getInt("minutesUsed"),
                if (o.isNull("score") || !o.has("score")) null else o.getDouble("score"))
        }
    }.getOrDefault(emptyList())

    fun record(mock: MockRecord, file: File): List<MockRecord> {
        val all = (listOf(mock) + load(file)).take(cap)
        runCatching {
            file.parentFile?.mkdirs()
            val temporary = File(file.parentFile, file.name + ".tmp")
            temporary.writeText(JSONArray(all.map {
                JSONObject().put("id", it.id).put("date", it.date).put("title", it.title).put("track", it.track)
                    .put("correct", it.correct).put("total", it.total).put("wanted", it.wanted).put("passMark", it.passMark)
                    .put("minutesUsed", it.minutesUsed).put("score", it.score ?: JSONObject.NULL)
            }).toString())
            if (!temporary.renameTo(file)) { file.delete(); temporary.renameTo(file) }
        }
        return all
    }
}
