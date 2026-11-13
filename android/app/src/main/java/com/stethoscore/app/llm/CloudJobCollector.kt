package com.stethoscore.app.llm

import android.content.Context
import com.stethoscore.app.accuracy.VerificationScreen
import com.stethoscore.app.data.CaseChecks
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.network.BackendClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Jobs the server finished while the app was closed become sets in the
 * library, the next time the app is opened. Port of iOS
 * Shared/CloudJobCollector.swift (collect, collectOne, asText, screen).
 *
 * Every kind a recipe can make is screened as iOS screens it (questions,
 * stations, cards and cases through [VerificationScreen] and the case
 * checks; a textbook is checked by the layer once saved), and "[name] is
 * ready" goes to [Announce] once the set is on disk.
 *
 * Not ported yet (T0115b): the notification channel itself (nothing outside
 * tests sets [announcer], so no screen shows "[name] is ready"), the
 * background check while the app is away, the collection every minute while
 * the app is open (it runs once, at start), and the evidence the server's
 * check cites (CloudChecks). Questions, cards and a textbook are kept on disk
 * with a recipe; a station or case job is kept in memory only, so a closed
 * app leaves nothing of it to collect.
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

    /**
     * Where a set made here is announced when [collect] is not given its own:
     * the app sets it once it has a notification channel, and every
     * collection after that - the one at start included - says so.
     */
    @Volatile var announcer: Announce? = null

    private val collecting = AtomicBoolean(false)

    private val _delivered = MutableStateFlow(0)

    /**
     * How many sets the collector has put in the library while the app has
     * run: the library screens redraw when it moves, as iOS's do on the
     * store's change (StethoscoreApp).
     */
    val delivered: StateFlow<Int> get() = _delivered

    /** The app's own scope, not an activity's: a recreated activity neither cancels a collection nor strands its guard. */
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /**
     * At app start: the jobs are kept on disk from now on, and every job an
     * earlier run of the app started is collected (iOS RedPenApp's
     * `.task { await CloudJobCollector.collect(into: store) }`).
     */
    fun start(context: Context, library: StudyStore, scope: CoroutineScope = appScope) {
        val app = context.applicationContext
        CloudJobs.store = CloudJobs.FileStore(File(app.filesDir, "cloud-jobs"))
        val llm = LLMService.from(app)
        start(library, scope, CloudJobs.store, llm::cloudBearer, llm::client)
    }

    /**
     * The library the app shows now. Every start sets it: an activity made
     * again while a collection runs has a library of its own, and a set put
     * in the old one would be overwritten by the new one's next save.
     */
    @Volatile private var current: StudyStore? = null

    /** [start] without the Context: the library becomes the current one, and a collection begins unless one is running. */
    internal fun start(
        library: StudyStore, scope: CoroutineScope, store: CloudJobs.PendingStore,
        bearer: (String?) -> String?, client: (String) -> BackendClient,
    ): kotlinx.coroutines.Job {
        current = library
        return scope.launch {
            // into whichever library is current when the set is added
            collect(store, { set -> runCatching { (current ?: library).addSet(set) }.isSuccess }, bearer, client)
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
        announce: Announce? = announcer,
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
                val meant = recipe?.kind?.cloudPhrase ?: "a set"
                body = "Saved as text. It couldn't be made into $meant."
                made = text
            }
        }
        made?.let { set ->
            // on disk before the server's copy is forgotten below: this is the
            // only copy; not on disk, the job stays to be collected again
            if (!library.add(set)) return null
            _delivered.value += 1
            // the set is on disk: a notification that fails, by Exception or by Error
            // (an Android call missing on an older device), must not leave the job to be
            // collected, and made, again. A cancelled collection and a failing JVM are not
            // the notification's failure: those are passed on, after the job is removed.
            try {
                announce?.ready("${set.name} is ready", body, set.id)
            } catch (e: Throwable) {
                if (e is kotlinx.coroutines.CancellationException || e is VirtualMachineError) throw e
                // nothing to do: the set is in the library
            } finally {
                // on every way out, a cancelled collection and a failing JVM included:
                // the set is on disk, and a job left here would make it again
                store.remove(pending.id)
            }
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
     * screens run it (VerificationScreen): a broken question, station or card
     * is removed with its reason and a red flag is held; cases go through
     * their structure checks; the independent checkers take the set once it
     * is saved. Returns the set and the note of what it did.
     */
    private fun screen(set: StudySet): Pair<StudySet, String> = when (set.kind) {
        StudySetKind.MCQ -> {
            val screened = VerificationScreen.questions(set.questions)
            set.copy(questions = screened.kept) to VerificationScreen.note(screened)
        }
        StudySetKind.OSCE -> {
            val screened = VerificationScreen.stations(set.osceChecklists)
            set.copy(osceChecklists = screened.kept) to VerificationScreen.note(screened)
        }
        StudySetKind.ANKI -> {
            val screened = VerificationScreen.cards(set.cards)
            set.copy(cards = screened.kept) to VerificationScreen.note(screened)
        }
        StudySetKind.CASES -> {
            val screened = CaseChecks.screen(set.caseFiles)
            set.copy(caseFiles = screened.kept) to CaseChecks.note(screened.kept.size, screened.dropped.size)
        }
        // pages: checked by the layer once saved
        else -> set to " The verification layer checks it once the set is saved."
    }
}
