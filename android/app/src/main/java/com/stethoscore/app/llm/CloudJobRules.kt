package com.stethoscore.app.llm

/**
 * What becomes of a cloud job this device is still waiting for. Port of iOS
 * Shared/CloudJobRules.swift, rule for rule: every wrong answer here is a paid
 * generation thrown away.
 */
object CloudJobRules {

    /** How asking the server about a job ended. */
    sealed class Answer {
        /** It answered, with the job's status. */
        data class Status(val status: String) : Answer()
        /** It said it has no such job. */
        data object Gone : Answer()
        /** No answer worth acting on: no signal, a server error, too many requests, a session that ran out. */
        data object Unreachable : Answer()
    }

    /** What a failed status request means. Only the server saying "no such job" (404) is taken for gone. */
    fun answerForFailedStatus(code: Int?): Answer = if (code == 404) Answer.Gone else Answer.Unreachable

    /** The server keeps a finished job for a week (server/jobs.js keepDays); gone for longer than this, it was collected or expired. */
    const val GONE_AFTER_MILLIS: Long = 8L * 86_400_000
    /** A job made under an identity this device can no longer ask with is kept this long, in case it comes back. */
    const val UNREACHABLE_AFTER_MILLIS: Long = 30L * 86_400_000

    /** Whether this device lets go of its record of a job. */
    fun letGo(startedMillis: Long, answer: Answer, reachable: Boolean, nowMillis: Long = System.currentTimeMillis()): Boolean {
        val age = nowMillis - startedMillis
        if (!reachable) return age > UNREACHABLE_AFTER_MILLIS
        return answer == Answer.Gone && age > GONE_AFTER_MILLIS
    }

    /** What to do after a request for a finished job's result has failed. */
    sealed class Retry {
        /** Ask again after this many seconds, the screen still waiting. */
        data class After(val seconds: Double) : Retry()
        /** Stop asking from the screen; the job is handed to the collector. */
        data object HandOver : Retry()
    }

    /** The waits between tries while the screen waits: about two minutes in all. */
    val fetchWaits: List<Double> = listOf(2.0, 4.0, 8.0, 15.0, 30.0, 30.0, 30.0)

    /** `failed`: tries failed so far (1 after the first); `status`: the HTTP status, null for no answer at all. */
    fun afterFailedFetch(failed: Int, status: Int?): Retry {
        if (status == 401 || status == 403 || status == 404) return Retry.HandOver
        if (failed < 1 || failed > fetchWaits.size) return Retry.HandOver
        return Retry.After(fetchWaits[failed - 1])
    }

    /** Who stopped the generation a job was running under. */
    @Suppress("EnumEntryName")
    enum class Stop { student, system }

    /** iOS's continued-processing expiry: the system's only while the app is active. */
    fun stopAtExpiry(appActive: Boolean): Stop = if (appActive) Stop.system else Stop.student

    /** What becomes of the job when its generation is stopped. */
    @Suppress("EnumEntryName")
    enum class StopFate { delete, handOver }

    fun afterStop(stop: Stop): StopFate = if (stop == Stop.system) StopFate.handOver else StopFate.delete

    /** What the student is told when the screen stops waiting for a finished job's result. */
    fun handedOverMessage(what: String): String =
        what + " finished in the cloud but could not be downloaded yet. Nothing is lost: the set will be in your library as soon as the cloud can be reached."
}
