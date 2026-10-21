package com.stethoscore.app.data

// A port of upstream/ios/RedPen/Shared/Learn/WardWords.swift: the few words
// the Ward Round home and the Vitals screen put around their numbers: the
// exam countdown, the greeting, and where the readiness estimate stands
// against the pass mark. Calm by rule: a countdown never shouts, a standing
// below the pass mark is "for now", and a name that is only a placeholder is
// not used as one. Pure Kotlin.
object WardWords {

    /** What the countdown calls the exam when none is chosen: the owner's finals. */
    const val defaultExam = "Finals"

    /** "Finals in 23 days", "PLAB 1 tomorrow", "Finals today"; null with no date, or once it has passed. */
    fun countdown(days: Int?, exam: String? = null): String? {
        if (days == null || days < 0) return null
        val given = (exam ?: "").trim()
        val name = if (given.isEmpty()) defaultExam else given
        return when (days) {
            0 -> "$name today"
            1 -> "$name tomorrow"
            else -> "$name in $days days"
        }
    }

    /** "Good morning, Sam"; "Good evening" without a name. */
    fun greeting(hour: Int, name: String? = null): String {
        val part = when (hour) {
            in 5 until 12 -> "Good morning"
            in 12 until 18 -> "Good afternoon"
            else -> "Good evening"
        }
        val first = firstName(name) ?: return part
        return "$part, $first"
    }

    /** The first word of a display name, when it is a name: not an email address, and not "Me". */
    fun firstName(display: String?): String? {
        val trimmed = (display ?: "").trim()
        if (trimmed.isEmpty() || trimmed.contains("@") || trimmed.lowercase() == "me") return null
        val first = trimmed.split(" ").firstOrNull { it.isNotEmpty() } ?: trimmed
        if (first.length > 24) return null
        return first
    }

    /** Where a readiness estimate stands against the pass mark. */
    fun standing(low: Double, high: Double, passMark: Double): String {
        if (low >= passMark) return "on track for a pass"
        if (high < passMark) return "below the pass mark for now"
        return "around the pass mark"
    }

    /** "Finals in 23 days · on track for a pass"; null with no countdown. */
    fun vitalsLine(countdown: String?, standing: String?): String? {
        if (countdown == null) return null
        if (standing.isNullOrEmpty()) return countdown
        return "$countdown · $standing"
    }
}
