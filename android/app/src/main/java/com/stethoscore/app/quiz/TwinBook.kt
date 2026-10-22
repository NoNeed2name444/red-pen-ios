package com.stethoscore.app.quiz

import com.stethoscore.app.data.LibraryStats
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.newId
import com.stethoscore.app.llm.ChatTurn
import com.stethoscore.app.llm.CloudJobs
import com.stethoscore.app.llm.LLMBackend
import com.stethoscore.app.llm.MedicalGenerate
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.ZoneId
import kotlin.coroutines.cancellation.CancellationException

// Write a twin on Android (T0133): a port of iOS Shared/Exam/TwinQueue.swift's
// TwinBook and TwinDraft and of ExamStore.swift's ExamStore twins, the Twins
// sets and TwinWriter. The twin question lives in the library (a "Twins ·
// <subject>" question set); its due date and the twins still to be written
// are kept beside the library in twins.json, as iOS keeps them in
// UserDefaults. The writer is the one New set uses (LLMService's backend);
// with none, the quiz says so and nothing is sent.

/** A twin asked for while it could not be written, kept so it is written the next time a quiz opens. */
data class PendingTwin(val parentId: String, val picked: Int? = null, val reason: String? = null,
                       val confident: Boolean = false, val guessed: Boolean = false)

/** What this phone keeps about twins: the queue and the twins still to be written. Plain values, tested on the JVM. */
data class TwinBook(val queue: TwinQueue = TwinQueue(), val pending: List<PendingTwin> = emptyList()) {
    companion object {
        /** The most twins kept waiting to be written. */
        const val pendingLimit = 30

        /** What the Twins tile says while no twin is due (iOS TwinBook.nothingYet). */
        const val nothingYet = "When you miss a question, tap “Write a twin” under it. The twin - the same point in a different patient - waits here for a day or two."

        fun fromJson(text: String?): TwinBook = runCatching {
            val o = JSONObject(text ?: return TwinBook())
            val entries = o.optJSONArray("twins") ?: JSONArray()
            val queue = TwinQueue((0 until entries.length()).mapNotNull { i ->
                val e = entries.optJSONObject(i) ?: return@mapNotNull null
                TwinEntry(e.getString("id"), e.getString("parentId"), e.getLong("createdAt"), e.getLong("dueAt"),
                    if (e.has("answeredAt")) e.getLong("answeredAt") else null,
                    if (e.has("answeredCorrectly")) e.getBoolean("answeredCorrectly") else null)
            })
            val waiting = o.optJSONArray("pending") ?: JSONArray()
            val pending = (0 until waiting.length()).mapNotNull { i ->
                val p = waiting.optJSONObject(i) ?: return@mapNotNull null
                PendingTwin(p.getString("parentId"), if (p.has("picked")) p.getInt("picked") else null,
                    if (p.has("reason")) p.getString("reason") else null, p.optBoolean("confident"), p.optBoolean("guessed"))
            }
            TwinBook(queue, pending)
        }.getOrDefault(TwinBook())
    }

    /** A written twin joins the queue; its request is no longer pending. */
    fun added(id: String, parent: String, confident: Boolean, guessed: Boolean,
              now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): TwinBook =
        TwinBook(queue.add(id, parent, now, confident, guessed, zone), pending.filterNot { it.parentId == parent })

    /** A twin that could not be written now waits, once per question. */
    fun later(request: PendingTwin): TwinBook {
        if (pending.any { it.parentId == request.parentId }) return this
        return copy(pending = (pending + request).takeLast(pendingLimit))
    }

    fun dropPending(parent: String): TwinBook = copy(pending = pending.filterNot { it.parentId == parent })

    fun isOnTheWay(parent: String): Boolean = queue.hasTwin(parent) || pending.any { it.parentId == parent }

    fun toJson(): String = JSONObject()
        .put("twins", JSONArray(queue.entries.map { e ->
            JSONObject().put("id", e.id).put("parentId", e.parentId).put("createdAt", e.createdAt).put("dueAt", e.dueAt)
                .apply { e.answeredAt?.let { put("answeredAt", it) }; e.answeredCorrectly?.let { put("answeredCorrectly", it) } }
        }))
        .put("pending", JSONArray(pending.map { p ->
            JSONObject().put("parentId", p.parentId).put("confident", p.confident).put("guessed", p.guessed)
                .apply { p.picked?.let { put("picked", it) }; p.reason?.let { put("reason", it) } }
        }))
        .toString()
}

/** The twin book kept on disk beside the library (iOS ExamStore's twins and pending). */
class TwinShelf(private val file: File) {
    @Volatile var book: TwinBook = TwinBook.fromJson(runCatching { file.takeIf { it.exists() }?.readText() }.getOrNull())
        private set

    @Synchronized private fun keep(next: TwinBook) {
        book = next
        runCatching { file.parentFile?.mkdirs(); file.writeText(next.toJson()) }
    }

    fun addTwin(id: String, parent: String, confident: Boolean, guessed: Boolean,
                now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()) =
        keep(book.added(id, parent, confident, guessed, now, zone))

    /** A twin answered moves along its own queue; any other question is not a twin and changes nothing. */
    fun answered(id: String, correct: Boolean, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()) {
        if (!book.queue.isTwin(id)) return
        keep(book.copy(queue = book.queue.answered(id, correct, now, zone)))
    }

    fun later(request: PendingTwin) = keep(book.later(request))
    fun dropPending(parent: String) = keep(book.dropPending(parent))
    fun isOnTheWay(parent: String): Boolean = book.isOnTheWay(parent)

    /** Forgets twins whose question has left the library. */
    fun prune(store: StudyStore) {
        val ids = store.library.filter { it.kind == StudySetKind.MCQ }.flatMap { s -> s.questions.map { it.id } }.toSet()
        val next = book.copy(queue = book.queue.prune(ids))
        if (next.queue.entries.size != book.queue.entries.size) keep(next)
    }
}

/** The twin a writer's questions give, or null when none will do (iOS TwinDraft). */
object TwinDraft {
    fun pick(found: List<MCQQuestion>, missed: MCQQuestion, id: String = newId()): MCQQuestion? {
        val twin = found.firstOrNull { !TwinPrompt.isTooClose(it.stem, missed.stem) } ?: return null
        return twin.copy(id = id, source = missed.source?.let { "Twin of a question from $it" } ?: "Twin of a missed question")
    }

    /** What the quiz says under the question once the twin is written. */
    fun madeNote(days: Int): String =
        "Twin written. It comes back ${if (days == 1) "tomorrow" else "in $days days"}, under Questions → Twins."
}

/** What came of asking for a twin. */
sealed class TwinOutcome {
    data class Made(val days: Int) : TwinOutcome()
    /** Nothing can write one on this phone; said once, plainly. */
    data class Unavailable(val why: String) : TwinOutcome()
    /** Couldn't write it now; it waits and is tried again later. */
    data class Later(val why: String) : TwinOutcome()

    /** The line under the question. */
    val note: String get() = when (this) {
        is Made -> TwinDraft.madeNote(days)
        is Unavailable -> why
        is Later -> why
    }
}

/** The library's side of twins (iOS Store.twinsSet, addTwin, twinsQuiz, pick). */
object TwinSets {
    fun name(subject: String) = "Twins · $subject"

    /** Puts a written twin into its subject's Twins set, made when first needed. */
    fun add(store: StudyStore, twin: MCQQuestion, subject: String, now: Long = System.currentTimeMillis()) {
        val found = store.library.firstOrNull { it.kind == StudySetKind.MCQ && it.name == name(subject) }
        val set = found ?: StudySet(name = name(subject), subject = subject, kind = StudySetKind.MCQ, createdAt = now)
        store.addSet(set.copy(questions = set.questions + twin, updatedAt = now))
    }

    /** The twins due now, as a quiz; the longest-waiting first. Empty when none is due. */
    fun quiz(store: StudyStore, now: Long = System.currentTimeMillis(), limit: Int = 20): StudySet {
        store.twinShelf.prune(store)
        val order = store.twinShelf.book.queue.due(now).map { it.id }
        val rank = order.withIndex().associate { it.value to it.index }
        val picks = LibraryStats.mcqPicks(store) { it.question.id in rank }.sortedBy { rank[it.question.id] ?: 0 }
        return LibraryStats.temporaryQuiz("Twin questions", "Twins", picks.take(limit))
    }
}

/** Writes twins with the writer New set uses (iOS TwinWriter). */
object TwinWriter {
    const val noWriter = "Twins are written by a question writer, and none is set up on this phone yet."
    const val later = "Couldn’t write the twin just now. It will be tried again next time you practise."
    const val gone = "This question is no longer in the library."

    /** Writes a twin for [request]'s question and puts it in the queue; [backend] null is no writer. */
    suspend fun write(request: PendingTwin, store: StudyStore, backend: LLMBackend?, style: String,
                      now: () -> Long = System::currentTimeMillis, zone: ZoneId = ZoneId.systemDefault()): TwinOutcome {
        val pick = LibraryStats.mcqPicks(store) { it.question.id == request.parentId }.firstOrNull()
            ?: return TwinOutcome.Unavailable(gone).also { store.twinShelf.dropPending(request.parentId) }
        backend ?: return TwinOutcome.Unavailable(noWriter)
        val q = pick.question
        val input = TwinPrompt.input(q.stem, q.options, q.correctIndex, q.explanation, request.picked, request.reason)
        val system = TwinPrompt.instructions(style)
        val subject = LibraryStats.subjectName(pick.set)
        var found: List<MCQQuestion> = try {
            MedicalGenerate.parseQuestions(backend.complete(listOf(ChatTurn.system(system), ChatTurn.user(input)), 1_400, 0.8))
        } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
        // the cloud writer's own job path, when the direct call gave nothing
        if (found.isEmpty() && CloudJobs.endpoint(backend) != null) {
            found = try { MedicalGenerate.mcq(system + "\n\n" + input, 1, subject, false, backend) }
            catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
        }
        val twin = TwinDraft.pick(found, q) ?: return TwinOutcome.Later(later).also { store.twinShelf.later(request) }
        val at = now()
        TwinSets.add(store, twin, subject, at)
        store.twinShelf.addTwin(twin.id, q.id, request.confident, request.guessed, at, zone)
        return TwinOutcome.Made(TwinQueue.delayDays(request.confident, request.guessed))
    }

    /** Writes the twins asked for while offline, quietly, one at a time. */
    suspend fun retryPending(store: StudyStore, backend: LLMBackend?, style: String) {
        for (request in store.twinShelf.book.pending.take(3)) {
            if (write(request, store, backend, style) !is TwinOutcome.Made) return
        }
    }
}
