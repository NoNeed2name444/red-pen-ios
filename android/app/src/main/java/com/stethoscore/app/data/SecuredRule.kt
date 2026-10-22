package com.stethoscore.app.data

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

// Ported from ios/RedPen/Shared/Learn/SecuredRule.swift. Tested by LearnTest.

/**
 * "Lock it in": a question counts as secured once it has been answered
 * correctly on three separate days.
 *
 * Successive relearning (Rawson & Dunlosky): the days count, not the
 * answers - three right answers this afternoon are one day. A wrong answer
 * starts the count again. Nothing new is stored: it is read from the dated
 * answer log (AnswerEvent).
 */
object SecuredRule {
    /** Correct days needed. */
    const val daysNeeded = 3

    /** Where one question stands. */
    sealed class Standing {
        /** Never answered. */
        data object New : Standing()
        /** Right on this many separate days (0...2) since its last wrong answer. */
        data class Building(val n: Int) : Standing()
        data object Secured : Standing()

        val isSecured: Boolean get() = this == Secured

        /** Correct days so far, 0...3. */
        val days: Int get() = when (this) {
            New -> 0
            is Building -> n
            Secured -> daysNeeded
        }
    }

    private fun day(at: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(at).atZone(zone).toLocalDate()

    /** Every question in the log, and where it stands. */
    fun standings(events: List<AnswerEvent>, zone: ZoneId = ZoneId.systemDefault()): Map<String, Standing> =
        events.groupBy { it.questionId }.mapValues { standing(it.value, zone) }

    /** One question's standing from its own answers. */
    fun standing(events: List<AnswerEvent>, zone: ZoneId = ZoneId.systemDefault()): Standing {
        if (events.isEmpty()) return Standing.New
        val days = HashSet<LocalDate>()
        for (event in events.sortedBy { it.at }) {
            if (event.correct) {
                // right with the attending's hint: neither a day towards locking in nor a slip
                if (event.hinted != true) days.add(day(event.at, zone))
            } else {
                // slipped: the count starts again
                days.clear()
            }
        }
        if (days.size >= daysNeeded) return Standing.Secured
        return Standing.Building(days.size)
    }

    /** One subject's ring: secured, building and not yet tried. */
    data class Ring(val subject: String, val secured: Int, val building: Int, val new: Int) {
        val id: String get() = subject
        val total: Int get() = secured + building + new
        val fraction: Double get() = if (total == 0) 0.0 else secured.toDouble() / total
    }

    /** Rings per subject for the questions in [subjects] (question id to subject), in subject order. */
    fun rings(subjects: Map<String, String>, standings: Map<String, Standing>): List<Ring> {
        val rings = HashMap<String, Ring>()
        for ((id, subject) in subjects) {
            val ring = rings[subject] ?: Ring(subject, 0, 0, 0)
            rings[subject] = when (standings[id] ?: Standing.New) {
                Standing.Secured -> ring.copy(secured = ring.secured + 1)
                // tried, even if only got wrong so far
                is Standing.Building -> ring.copy(building = ring.building + 1)
                Standing.New -> ring.copy(new = ring.new + 1)
            }
        }
        return rings.values.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.subject })
    }

    /** Of [ids], those one or two days short - two first, then one. */
    fun closeToSecure(ids: List<String>, standings: Map<String, Standing>): List<String> {
        val two = ids.filter { standings[it] == Standing.Building(2) }
        val one = ids.filter { standings[it] == Standing.Building(1) }
        return two + one
    }

    /** Whether a correct answer today would move this question on: it was not already answered correctly today. */
    fun countsToday(id: String, events: List<AnswerEvent>, now: Long, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        val today = day(now, zone)
        val latest = events.filter { it.questionId == id && day(it.at, zone) == today }.maxByOrNull { it.at }
        return latest?.correct != true
    }
}
