package com.stethoscore.app.llm

import android.content.Context
import com.stethoscore.app.data.CaseChecks
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.network.BackendClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Jobs the server finished while the app was closed become sets in the
 * library, the next time the app is opened. Port of iOS
 * Shared/CloudJobCollector.swift (collect, collectOne, asText, screen).
 *
 * Not ported yet (T0115b): the notification that says a set is ready
 * ([Announce] is where it goes; Android has no channel for it yet), the
 * background check while the app is away, the collection every minute while
 * the app is open, the evidence the server's check cites (CloudChecks) and
 * the on-device screen of questions, stations and cards (VerificationScreen).
 */
object CloudJobCollector {

    /** The library the sets go into. */
    fun interface Library {
        /** Adds the set; true only once it is on disk. A set that is not on disk is not left in the library. */
        fun add(set: StudySet): Boolean
    }

    /** Where "[name] is ready" goes (iOS AppNotifications.generationFinished). */
    fun interface Announce {
        fun ready(title: String, body: String, setId: String)
    }

    private val collecting = AtomicBoolean(false)

    /**
     * At app start: the jobs are kept on disk from now on, and every job an
     * earlier run of the app started is collected (iOS RedPenApp's
     * `.task { await CloudJobCollector.collect(into: store) }`).
     */
    fun start(context: Context, library: StudyStore, scope: CoroutineScope) {
        val app = context.applicationContext
        CloudJobs.store = CloudJobs.FileStore(File(app.filesDir, "cloud-jobs"))
        val llm = LLMService.from(app)
        scope.launch {
            collect(CloudJobs.store, { set -> runCatching { library.addSet(set) }.isSuccess }, llm::cloudBearer, llm::client)
        }
    }

    /**
     * Picks up every job started by an earlier run of the app (this run's
     * jobs are being watched by the screens that started them). Returns the
     * sets it made. Its file and network work runs on [CloudJobs.io].
     */
    suspend fun collect(
        store: CloudJobs.PendingStore, library: Library,
        /** The bearer to ask about a job made under this identity, or null (LLMService.cloudBearer). */
        bearer: (String?) -> String?,
        client: (String) -> BackendClient,
        announce: Announce? = null,
        launch: String = CloudJobs.launch,
        now: () -> Long = System::currentTimeMillis,
    ): List<StudySet> {
        if (!collecting.compareAndSet(false, true)) return emptyList()
        try {
            return withContext(CloudJobs.io) {
                val made = mutableListOf<StudySet>()
                for (pending in store.all().filter { it.launch != launch }) {
                    // Asked about only as the identity it was made under: asking
                    // as anyone else finds nothing - which is not the job being gone.
                    val token = bearer(pending.identity)
                    // A generation the app was closed on carries its replies with
                    // it: made into its set whoever is signed in now.
                    val kept = pending.delivered == true && pending.outputs != null
                    if (token == null && !kept) {
                        if (CloudJobRules.letGo(pending.started, CloudJobRules.Answer.Unreachable, reachable = false, nowMillis = now())) {
                            store.remove(pending.id)
                        }
                        continue
                    }
                    val endpoint = token?.let { CloudEndpoint(client(it), pending.identity, null) }
                    collectOne(pending, endpoint, store, library, announce, now)?.let { made += it }
                }
                made
            }
        } finally {
            collecting.set(false)
        }
    }

    /** `at` is null only for a job whose replies were kept with it, made under an identity this device cannot ask as now. */
    private suspend fun collectOne(
        pending: CloudJobs.Pending, at: CloudEndpoint?, store: CloudJobs.PendingStore,
        library: Library, announce: Announce?, now: () -> Long,
    ): StudySet? {
        val outputs: List<String>
        var recovered = false
        if (pending.delivered == true && pending.outputs != null) {
            // handed to the screen that asked for it, which never finished
            // with it: the app was closed while it was being checked or saved
            outputs = pending.outputs
            recovered = true
        } else {
            if (at == null) return null
            val status = try {
                CloudJobs.status(pending.id, at)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                // Gone from the server - but only when the server says so. No
                // signal, a server error or a session that ran out leave the
                // job to be asked about again next time.
                val answer = CloudJobRules.answerForFailedStatus((e as? LLMError.Http)?.status)
                if (CloudJobRules.letGo(pending.started, answer, reachable = true, nowMillis = now())) store.remove(pending.id)
                return null
            }
            when (status.status) {
                "done" -> outputs = try {
                    CloudJobs.result(pending.id, at)
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    return null
                }
                "failed" -> {
                    store.remove(pending.id)
                    CloudJobs.forget(pending.id, at)
                    return null
                }
                else -> return null
            }
        }
        val recipe = CloudRecipe.of(pending.recipe)
        var made: StudySet? = null
        var body = if (recovered) "Written in the cloud; the app was closed before it was saved."
            else "Written in the cloud while the app was closed."
        val set = recipe?.set(outputs, pending.extra)
        if (recipe != null && set != null) {
            val (screened, note) = screen(set)
            body += note
            made = screened
        } else {
            asText(outputs, pending, recipe)?.let { text ->
                // The replies could not be made into a set (or its recipe could
                // not be read): kept as text rather than thrown away with the
                // generation that paid for them.
                val meant = recipe?.kind?.cloudNoun ?: "a set"
                body = "Kept as text — it could not be turned into $meant."
                made = text
            }
        }
        made?.let { set ->
            // on disk before the server's copy is forgotten below: this is the
            // only copy; not on disk, the job stays to be collected again
            if (!library.add(set)) return null
            announce?.ready("${set.name} is ready", body, set.id)
        }
        store.remove(pending.id)
        // the server's copy, where this device can still reach it; otherwise it expires there on its own
        if (at != null) CloudJobs.forget(pending.id, at)
        return made
    }

    /** What the cloud wrote, as a textbook of its own, for replies that could not be made into the set they were for. */
    internal fun asText(outputs: List<String>, pending: CloudJobs.Pending, recipe: CloudRecipe?): StudySet? {
        val text = outputs.map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n\n")
        if (text.isEmpty()) return null
        val title = recipe?.name?.trim().orEmpty()
        val subject = recipe?.subject.orEmpty()
        return StudySet(
            name = title.ifEmpty { pending.title } + " (as written)", subject = subject.ifEmpty { "General" },
            kind = StudySetKind.BOOK, bookMarkdown = text, sources = listOfNotNull(recipe?.source),
        )
    }

    /**
     * The verification layer's first stage on what a cloud job wrote, as the
     * screens run it: cases through their structure checks; the rest is
     * checked by the layer once saved. Returns the set and the note of what it did.
     */
    private fun screen(set: StudySet): Pair<StudySet, String> = when (set.kind) {
        StudySetKind.CASES -> {
            val screened = CaseChecks.screen(set.caseFiles)
            set.copy(caseFiles = screened.kept) to CaseChecks.note(screened.kept.size, screened.dropped.size)
        }
        else -> set to " The verification layer checks it once the set is saved."
    }
}
