package com.stethoscore.app.data

import org.json.JSONObject
import java.util.Locale
import kotlin.math.ceil

// The ward round, ported from ios/RedPen/Shared/StudySession.swift.
//
// A focus session in rounds: 25 or 50 minutes on, a 5- or 10-minute break,
// four rounds. Started from the exam plan (WardRoundTile), shown as a small
// chip over the whole app while it runs (WardRoundOverlay).
//
// Everything here is worked out from dates, never from a ticking counter:
// the phone may be locked half way through a round, and when it comes back
// the clock simply runs forward to now (advance) and says what ended on the
// way. Dates are epoch milliseconds; lengths are seconds, as on iOS.
// Tested by WardRoundTest.

/** How a ward round is set up. Held to sane values, so a stored choice from
 *  an older build never makes a zero-length or day-long round. */
class WardRoundPlan(focusMinutes: Int, breakMinutes: Int, rounds: Int = 4) {
    val focusMinutes: Int = focusMinutes.coerceIn(1, 120)
    val breakMinutes: Int = breakMinutes.coerceIn(1, 30)
    val rounds: Int = rounds.coerceIn(1, 8)

    val focusLength: Double get() = (focusMinutes * 60).toDouble()
    val breakLength: Double get() = (breakMinutes * 60).toDouble()

    override fun equals(other: Any?): Boolean =
        other is WardRoundPlan && other.focusMinutes == focusMinutes &&
            other.breakMinutes == breakMinutes && other.rounds == rounds

    override fun hashCode(): Int = (focusMinutes * 31 + breakMinutes) * 31 + rounds
    override fun toString(): String =
        "WardRoundPlan(focusMinutes: $focusMinutes, breakMinutes: $breakMinutes, rounds: $rounds)"

    companion object {
        val focusChoices: List<Int> = listOf(25, 50)
        val breakChoices: List<Int> = listOf(5, 10)
        val standard = WardRoundPlan(focusMinutes = 25, breakMinutes = 5)
    }
}

/** One ward round under way, as a value: where it is, and what it has
 *  counted so far. */
data class WardRound(
    val plan: WardRoundPlan,
    val startedAt: Long,
    /** 1-based. During a break, the round just finished. */
    val round: Int,
    val phase: Phase,
    /** When the running phase's clock reaches zero (focus and rest only). */
    val phaseEnds: Long,
    /** The time left, held still, while paused. */
    val pausedLeft: Double?,
    /** Cards, questions and steps studied while a round's clock ran. */
    val items: Int,
    /** Focus time sat so far, in seconds, across every round. */
    val focusSeconds: Double,
) {
    enum class Phase(val raw: String) {
        /** The clock is running on a round. */
        Focus("focus"),
        /** The break after `round`. */
        Rest("rest"),
        /** The break is over; the next round waits for the student to start it. */
        Ready("ready"),
        /** Every round done, or stopped. */
        Done("done");

        companion object {
            fun from(raw: String): Phase? = entries.firstOrNull { it.raw == raw }
        }
    }

    /** What happened as the clock moved on, for WardRoundClock to act on. */
    sealed class Event {
        /** A round's focus ended - ran out, or was cut short - after `seconds` of it, at `end`. */
        data class FocusEnded(val round: Int, val seconds: Double, val end: Long) : Event()
        /** The break after `round` is over. */
        data class RestEnded(val round: Int) : Event()
        /** The whole ward round is over. */
        data object Finished : Event()
    }

    /** A heads-up for when the app is not in front. */
    data class Alarm(val id: String, val date: Long, val title: String, val body: String)

    val isPaused: Boolean get() = pausedLeft != null

    /** Whether a clock is counting down (or held) right now. */
    val isTimed: Boolean get() = phase == Phase.Focus || phase == Phase.Rest

    /** Whether a screen showing this needs to redraw every second. */
    val ticks: Boolean get() = isTimed && !isPaused

    /** The full length of the phase showing. */
    val phaseLength: Double
        get() = when (phase) {
            Phase.Focus -> plan.focusLength
            Phase.Rest -> plan.breakLength
            Phase.Ready, Phase.Done -> 0.0
        }

    /** Seconds left on the clock. */
    fun remaining(now: Long): Double {
        if (!isTimed) return 0.0
        pausedLeft?.let { return it }
        return maxOf(0.0, (phaseEnds - now) / 1000.0)
    }

    /** How much of the phase is left, 1 at its start and 0 at its end. */
    fun leftFraction(now: Long): Double {
        val length = phaseLength
        if (length <= 0) return 0.0
        return minOf(1.0, maxOf(0.0, remaining(now) / length))
    }

    /** Whole minutes of focus sat so far. */
    val focusMinutes: Int get() = (focusSeconds / 60).toInt()

    // MARK: moving on (each returns the new value and what happened)

    data class Step(val round: WardRound, val events: List<Event>)

    /** Runs the clock forward to `now`: every phase whose time has run out
     *  ends, in order, each at the moment it ran out. */
    fun advance(now: Long): Step {
        var r = this
        val events = mutableListOf<Event>()
        while (r.ticks && r.phaseEnds <= now) {
            val s = r.finishPhase(r.phaseEnds)
            r = s.round
            events += s.events
        }
        return Step(r, events)
    }

    /** Ends the running phase now: a round cut short (the time sat still
     *  counts) goes to its break, a skipped break to the next round's start. */
    fun skip(now: Long): Step = if (!isTimed) Step(this, emptyList()) else finishPhase(now)

    /** Starts the next round - after a break, or in place of the rest of it. */
    fun startNext(now: Long): WardRound {
        if (!(phase == Phase.Ready || phase == Phase.Rest) || round >= plan.rounds) return this
        return copy(round = round + 1, phase = Phase.Focus, pausedLeft = null,
            phaseEnds = now + (plan.focusLength * 1000).toLong())
    }

    fun pause(now: Long): WardRound = if (!isTimed || isPaused) this else copy(pausedLeft = remaining(now))

    fun resume(now: Long): WardRound {
        val left = pausedLeft ?: return this
        return copy(phaseEnds = now + (left * 1000).toLong(), pausedLeft = null)
    }

    /** Stops the whole ward round now. A round under way still counts for
     *  the time sat in it. */
    fun stop(now: Long): Step {
        if (phase == Phase.Done) return Step(this, emptyList())
        val events = mutableListOf<Event>()
        var seconds = focusSeconds
        if (phase == Phase.Focus) {
            val spent = plan.focusLength - remaining(now)
            seconds += spent
            events += Event.FocusEnded(round, spent, now)
        }
        events += Event.Finished
        return Step(copy(phase = Phase.Done, pausedLeft = null, focusSeconds = seconds), events)
    }

    /** Something studied: counted only while a round's clock is on - not
     *  in a break, and not while the round is paused. */
    fun noteStudied(count: Int): WardRound =
        if (phase != Phase.Focus || isPaused || count <= 0) this else copy(items = items + count)

    private fun finishPhase(end: Long): Step = when (phase) {
        Phase.Focus -> {
            val spent = plan.focusLength - remaining(end)
            val events = mutableListOf<Event>(Event.FocusEnded(round, spent, end))
            val base = copy(focusSeconds = focusSeconds + spent, pausedLeft = null)
            if (round >= plan.rounds) {
                events += Event.Finished
                Step(base.copy(phase = Phase.Done), events)
            } else {
                Step(base.copy(phase = Phase.Rest, phaseEnds = end + (plan.breakLength * 1000).toLong()), events)
            }
        }
        Phase.Rest -> Step(copy(pausedLeft = null, phase = Phase.Ready), listOf(Event.RestEnded(round)))
        Phase.Ready, Phase.Done -> Step(this, emptyList())
    }

    // MARK: what it says

    /** "Block 2 of 4". */
    val roundWords: String get() = "Block $round of ${plan.rounds}"

    /** One line for the chip's label and the panel:
     *  "Block 2 of 4 · 12:40 · 38 cards". */
    fun caption(now: Long): String {
        val dot = " · "
        val cards = cardWords(items)
        val time = clock(remaining(now))
        return when (phase) {
            Phase.Focus -> roundWords + dot + time + dot + cards
            Phase.Rest -> "Break" + dot + time + dot + cards
            Phase.Ready -> "Block ${round + 1} of ${plan.rounds} when you’re ready" + dot + cards
            Phase.Done -> "Focus session done" + dot + "$focusMinutes min" + dot + cards
        }
    }

    /** The phase ends still to come, as the notifications to leave with the
     *  system: the end of this round, and the end of the break after it.
     *  None while paused - there is no end to announce. */
    fun alarms(now: Long): List<Alarm> {
        if (!ticks) return emptyList()
        val out = mutableListOf<Alarm>()
        if (phase == Phase.Focus) {
            if (round >= plan.rounds) {
                out += Alarm("wardround-focus", phaseEnds, "Focus session done", "${plan.rounds} blocks sat. Well done.")
                return out
            }
            out += Alarm("wardround-focus", phaseEnds, "$roundWords done",
                "Take ${plan.breakMinutes} minutes away from the screen.")
            val breakEnds = phaseEnds + (plan.breakLength * 1000).toLong()
            out += Alarm("wardround-rest", breakEnds, "Break over",
                "Block ${round + 1} of ${plan.rounds} is ready when you are.")
        } else {
            out += Alarm("wardround-rest", phaseEnds, "Break over",
                "Block ${round + 1} of ${plan.rounds} is ready when you are.")
        }
        return out.filter { it.date > now }
    }

    // MARK: saving (the Codable round trip)

    fun toJson(): String = JSONObject().apply {
        put("plan", JSONObject().apply {
            put("focusMinutes", plan.focusMinutes)
            put("breakMinutes", plan.breakMinutes)
            put("rounds", plan.rounds)
        })
        put("startedAt", startedAt)
        put("round", round)
        put("phase", phase.raw)
        put("phaseEnds", phaseEnds)
        pausedLeft?.let { put("pausedLeft", it) }
        put("items", items)
        put("focusSeconds", focusSeconds)
    }.toString()

    companion object {
        fun begin(plan: WardRoundPlan, now: Long): WardRound =
            WardRound(plan, now, 1, Phase.Focus, now + (plan.focusLength * 1000).toLong(), null, 0, 0.0)

        /** "12:40": minutes and seconds, rounded up, so a fresh round reads
         *  25:00 and the last second 0:01. */
        fun clock(seconds: Double): String {
            val whole = ceil(seconds).toInt()
            return String.format(Locale.ROOT, "%d:%02d", whole / 60, whole % 60)
        }

        fun cardWords(count: Int): String = if (count == 1) "1 card" else "$count cards"

        val alarmIDs: List<String> = listOf("wardround-focus", "wardround-rest")

        fun fromJson(text: String): WardRound? = try {
            val o = JSONObject(text)
            val p = o.getJSONObject("plan")
            WardRound(
                plan = WardRoundPlan(p.getInt("focusMinutes"), p.getInt("breakMinutes"), p.getInt("rounds")),
                startedAt = o.getLong("startedAt"),
                round = o.getInt("round"),
                phase = Phase.from(o.getString("phase")) ?: return null,
                phaseEnds = o.getLong("phaseEnds"),
                pausedLeft = if (o.has("pausedLeft")) o.getDouble("pausedLeft") else null,
                items = o.getInt("items"),
                focusSeconds = o.getDouble("focusSeconds"),
            )
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * The ward round's focus minutes per day, keyed `yyyy-MM-dd` (iOS StudyLog's
 * minutes): a day with minutes on it counts for the streak.
 */
object StudyMinutes {
    const val key = "study.minutes"

    fun all(defaults: LearnDefaults = LearnDefaults.shared): Map<String, Int> = runCatching {
        val o = JSONObject(defaults.string(key) ?: return emptyMap())
        o.keys().asSequence().associateWith { o.optInt(it) }
    }.getOrDefault(emptyMap())

    fun record(count: Int, at: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault(),
               defaults: LearnDefaults = LearnDefaults.shared) {
        if (count <= 0) return
        val day = java.time.Instant.ofEpochMilli(at).atZone(zone).toLocalDate().toString()
        var minutes = all(defaults).toMutableMap()
        minutes[day] = (minutes[day] ?: 0) + count
        // two years is plenty
        if (minutes.size > 730) minutes = minutes.toSortedMap().entries.toList().takeLast(730).associate { it.key to it.value }.toMutableMap()
        defaults.set(key, JSONObject(minutes as Map<*, *>).toString())
    }
}
