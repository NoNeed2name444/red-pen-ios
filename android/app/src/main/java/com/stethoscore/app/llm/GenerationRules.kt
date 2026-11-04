package com.stethoscore.app.llm

import java.util.UUID

/**
 * Whether a new generation may start while another is running (iOS
 * Shared/GenerationRules.swift, ported line for line).
 *
 * Pure, and apart from GenerationCenter, because the answer decides whether
 * paid work survives: a cancelled cloud job is deleted on the server along
 * with what it had written (audit #94). The new one is refused, not queued: a
 * queue could lose the second request once New set is closed, and a refusal
 * loses nothing. The running job carries on and the student is told what is
 * running and how to stop it.
 */
object GenerationRules {

    sealed interface Admission {
        data object Start : Admission
        /** Something else is being written; the words say what, and how to stop it. */
        data class Refuse(val why: String) : Admission
    }

    /** [running]: the title of the generation on the card now ("Writing 40 questions"), or null when there is none. */
    fun admit(running: String?): Admission {
        if (running == null) return Admission.Start
        val title = running.trim()
        val what = when {
            title.startsWith("Writing ") && title.length > "Writing ".length -> "Still writing " + title.removePrefix("Writing ")
            title.isEmpty() -> "Something else is being written"
            else -> "Still busy: " + title.lowercase()
        }
        return Admission.Refuse("$what — wait for it to finish, or tap Cancel on its card, then try again.")
    }

    /**
     * Whether closing a screen stops the generation running: only when that
     * screen started it. [running]: the screen that started it (null for none,
     * or one started outside any such screen); [closing]: the screen closing.
     */
    fun closingStops(running: UUID?, closing: UUID): Boolean = running == closing

    /**
     * Whether a run that has just ended may clear the screen's "writing"
     * state: only while it is still the current run. A cancelled run ends
     * late, and by then a new one may have started (audit #68).
     */
    fun endingClears(ended: UUID, current: UUID?): Boolean = ended == current
}
