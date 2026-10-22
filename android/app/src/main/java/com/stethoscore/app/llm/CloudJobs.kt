package com.stethoscore.app.llm

import com.stethoscore.app.network.BackendClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import kotlin.coroutines.coroutineContext

/**
 * Generation that carries on when the app is closed. Port of iOS
 * Shared/LLM/CloudJobs.swift.
 *
 * With Stethoscore Cloud writing, the app does not make the model calls
 * itself: it sends the server every prompt it would have sent (the lecture
 * once, as `{{SOURCE}}`; what is already written as `{{ALREADY}}`), and
 * watches the server work through them.
 *
 * Not ported yet (T0115b): the Delivery that keeps a finished job until its
 * screen has saved the set, the recipe, the collector that makes a set from
 * a job finished while the app was closed (CloudJobCollector) and the
 * evidence the server's check cites (CloudChecks). The records of jobs not
 * yet collected are kept on disk ([PendingStore]) for that collector.
 */
object CloudJobs {

    data class Step(val system: String, val user: String, val source: Int = 0, val maxTokens: Int, val temperature: Double) {
        fun json(): JSONObject = JSONObject().put("system", system).put("user", user).put("source", source)
            .put("maxTokens", maxTokens).put("temperature", temperature)
    }

    data class Spec(
        val title: String,
        /** "loop": prompts taken in turn until `count` items; "each": every prompt once, in order. */
        val mode: String,
        /** How the server counts a reply's items: lines, questions, stations, pages. */
        val extract: String,
        val count: Int,
        val sources: List<String>,
        val steps: List<Step>,
        val minFields: Int = 2,
        val keyFields: Int = 1,
        val cloze: Boolean = false,
        val patience: Int = 3,
        /** Items one reply writes, for counting the owner key's spend by progress. Never sent. */
        val perReply: Int = 1,
    ) {
        fun json(): JSONObject = JSONObject().put("title", title).put("mode", mode).put("extract", extract)
            .put("count", count).put("sources", JSONArray(sources)).put("steps", JSONArray(steps.map { it.json() }))
            .put("minFields", minFields).put("keyFields", keyFields).put("cloze", cloze).put("patience", patience)

        /** The characters one call to step `i` sends: its prompts with its source in place of {{SOURCE}}. */
        fun promptChars(i: Int): Int {
            val step = steps[i % steps.size]
            val source = sources.getOrNull(step.source)?.length ?: 0
            return step.system.length + step.user.length + if (step.system.contains("{{SOURCE}}")) source else 0
        }
    }

    data class Status(val id: String, val title: String, val status: String, val done: Int, val total: Int, val error: String?, val phase: String?) {
        companion object {
            fun of(json: JSONObject): Status = Status(
                json.optString("id"), json.optString("title"), json.optString("status"),
                json.optInt("done"), json.optInt("total"),
                json.opt("error") as? String, json.opt("phase") as? String,
            )
        }
    }

    /** A job this device started and has not collected yet, kept so a closed app can pick it up again. */
    data class Pending(
        val id: String, val title: String, val started: Long,
        /** The run of the app that is watching it; another run collects it. */
        val launch: String?,
        val done: Int = 0, val total: Int = 0,
        /** Whose job it is: the account it was made under, or "owner" for the owner key. */
        val identity: String? = null,
    ) {
        /** "Your 40 questions", from "Writing 40 questions". */
        val what: String get() = "Your " + if (title.startsWith("Writing ")) title.removePrefix("Writing ") else title.lowercase()

        fun json(): JSONObject = JSONObject().put("id", id).put("title", title).put("started", started)
            .put("launch", launch ?: JSONObject.NULL).put("done", done).put("total", total).put("identity", identity ?: JSONObject.NULL)

        companion object {
            fun of(json: JSONObject): Pending = Pending(
                json.getString("id"), json.optString("title"), json.optLong("started"),
                json.opt("launch") as? String, json.optInt("done"), json.optInt("total"), json.opt("identity") as? String,
            )
        }
    }

    /** Where pending jobs are kept. */
    interface PendingStore {
        fun save(pending: Pending)
        fun remove(id: String)
        fun all(): List<Pending>
    }

    class MemoryStore : PendingStore {
        private val kept = linkedMapOf<String, Pending>()
        @Synchronized override fun save(pending: Pending) { kept[pending.id] = pending }
        @Synchronized override fun remove(id: String) { kept.remove(id) }
        @Synchronized override fun all(): List<Pending> = kept.values.sortedBy { it.started }
    }

    /** One JSON file a job, in the app's files ("cloud-jobs"), as iOS keeps them in Application Support. */
    class FileStore(private val folder: File) : PendingStore {
        override fun save(pending: Pending) {
            folder.mkdirs()
            val target = File(folder, pending.id + ".json")
            val part = File(folder, pending.id + ".json.part")
            runCatching { part.writeText(pending.json().toString()); part.renameTo(target) }
        }
        override fun remove(id: String) { File(folder, "$id.json").delete() }
        override fun all(): List<Pending> = (folder.listFiles { f -> f.name.endsWith(".json") } ?: emptyArray())
            .mapNotNull { runCatching { Pending.of(JSONObject(it.readText())) }.getOrNull() }.sortedBy { it.started }
    }

    /** This run of the app. */
    val launch: String = UUID.randomUUID().toString()

    /** The jobs endpoint for this backend, or null to generate call by call. */
    fun endpoint(backend: LLMBackend): CloudEndpoint? = (backend as? HostedLLMClient)?.jobs

    /** How often the server is asked how the job is going. */
    const val POLL_MILLIS = 2_500L

    /**
     * Sends the job and waits for it, reporting progress. The replies come
     * back in the order they were written. Cancelling stops the job on the
     * server too.
     */
    suspend fun run(
        spec: Spec, at: CloudEndpoint, store: PendingStore = MemoryStore(),
        /** How a wait is made; null waits for real (tests pass one that returns at once). */
        pause: (suspend (Long) -> Unit)? = null,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): List<String> {
        at.meter?.ensureRoom()
        val created = call { at.client.createJob(spec.json()) }
        val id = created.optJSONObject("job")?.optString("id").orEmpty()
        if (id.isEmpty()) throw LLMError.BadResponse()
        var pending = Pending(id, spec.title, System.currentTimeMillis(), launch, 0, spec.count, at.identity)
        store.save(pending)
        onProgress(0, spec.count)
        var misses = 0
        var charged = false
        // the owner key's spend: every reply at its step's worst case, or
        // the calls the progress implies when the replies never came back
        fun charge(replies: Int) {
            val meter = at.meter ?: return
            if (charged) return
            charged = true
            for (i in 0 until replies) meter.record(null, spec.promptChars(i), spec.steps[i % spec.steps.size].maxTokens)
        }
        fun byProgress(): Int = (pending.done + spec.perReply - 1) / maxOf(1, spec.perReply)
        try {
            while (true) {
                wait(pause, POLL_MILLIS)
                val status: Status
                try {
                    status = status(id, at)
                    misses = 0
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    misses += 1
                    if (misses >= 30) {
                        // the server still has it: collected when the app next opens
                        store.save(pending.copy(launch = null))
                        throw LLMError.NotReady("Lost the connection. The cloud is still writing — it will be in your library when it is done.")
                    }
                    continue
                }
                onProgress(status.done, status.total)
                if (status.done != pending.done) {
                    pending = pending.copy(done = status.done, total = status.total)
                    store.save(pending)
                }
                when (status.status) {
                    "done" -> {
                        val outputs = try {
                            resultRetrying(id, at, pause)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            coroutineContext.ensureActive()
                            // finished, and kept on the server: handed to the collector
                            charge(byProgress())
                            store.save(pending.copy(launch = null))
                            throw LLMError.NotReady(CloudJobRules.handedOverMessage(pending.what))
                        }
                        charge(outputs.size)
                        store.remove(id)
                        // nothing waits on the server's copy going
                        withContext(NonCancellable) { forget(id, at) }
                        return outputs
                    }
                    "failed" -> {
                        charge(byProgress())
                        store.remove(id)
                        forget(id, at)
                        throw LLMError.NotReady(status.error ?: "The cloud model could not write this.")
                    }
                    else -> continue
                }
            }
        } catch (e: CancellationException) {
            // the student stopped it: stopped on the server and forgotten here
            // (CloudJobRules.afterStop(.student)); the system's stop, which
            // hands the job over, needs the Delivery that is not ported yet
            charge(byProgress())
            store.remove(id)
            withContext(NonCancellable) { forget(id, at) }
            throw e
        }
    }

    suspend fun status(id: String, at: CloudEndpoint): Status {
        val fetched = call { at.client.jobStatus(id) }
        return Status.of(fetched.optJSONObject("job") ?: throw LLMError.BadResponse())
    }

    /** A finished job's replies. */
    suspend fun result(id: String, at: CloudEndpoint): List<String> {
        val fetched = call { at.client.jobResult(id) }
        return LLMText.strings(fetched.optJSONArray("outputs"))
    }

    /** A finished job's result, asked for again after a failed request, with the waits CloudJobRules gives. */
    suspend fun resultRetrying(id: String, at: CloudEndpoint, pause: (suspend (Long) -> Unit)? = null): List<String> {
        var failed = 0
        while (true) {
            try {
                return result(id, at)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                coroutineContext.ensureActive()
                failed += 1
                val code = (e as? LLMError.Http)?.status
                when (val next = CloudJobRules.afterFailedFetch(failed, code)) {
                    is CloudJobRules.Retry.After -> wait(pause, (next.seconds * 1000).toLong())
                    CloudJobRules.Retry.HandOver -> throw e
                }
            }
        }
    }

    /**
     * A wait: the given one, else a real delay. A plain call rather than a
     * default suspend lambda, which the Kotlin compiler's IR lowering cannot
     * give a continuation (AddContinuationLowering) on a clean build.
     */
    private suspend fun wait(pause: (suspend (Long) -> Unit)?, millis: Long) {
        if (pause != null) pause(millis) else delay(millis)
    }

    /** Stops a job, or clears a collected one off the server. */
    suspend fun forget(id: String, at: CloudEndpoint) {
        runCatching { call { at.client.cancelJob(id) } }
    }

    /**
     * Where the blocking work around a job runs: its requests, and the
     * lecture read that feeds one (CaseMakeSection). Dispatchers.IO; a test
     * driving the screens with a stand-in worker runs it in place, so what
     * follows comes back on the thread that runs the test's clock.
     */
    @Volatile internal var io: CoroutineDispatcher = Dispatchers.IO

    /** One blocking request, off the main thread, its failure in LLMError's words. */
    private suspend fun call(block: () -> JSONObject): JSONObject = withContext(io) {
        try {
            block()
        } catch (e: BackendClient.BackendException) {
            throw if (e.status == 0) LLMError.NotReady(e.message ?: "The server could not be reached.") else LLMError.Http(e.status, e.message ?: "")
        }
    }
}
