package com.stethoscore.app.data

import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.time.ZoneId

// A port of ios/RedPen/Shared/Platform/GlanceDigest.swift (GlanceDigest and
// GlanceShelf): the one small file the widgets, and later the watch, read.
// The app writes it beside the library each time the numbers change; a
// widget never opens the library or the schedule itself.
//
// The file is the Swift one, byte for byte: keys sorted, dates ISO-8601 in
// whole seconds, a missing value left out, "/" written as "\/" (JSONEncoder's
// default). `goal` is optional on both sides (iOS carries it since T0196),
// so either side reads the other's file, old or new. `examName` is home's
// name for the exam (ExamCountdown.examName), and the sentence is home's
// (WardWords.countdown). Pure Kotlin, tested on the JVM (GlanceDigestTest).

data class GlanceDigest(
    val version: Int = currentVersion,
    /** When the app worked this out, in epoch milliseconds (whole seconds). */
    val madeAt: Long,
    /** Cards due now, within the day's limits. */
    val dueNow: Int,
    /** The decks with the most due, at most three. */
    val topDecks: List<DueDeck>,
    /** When the next card not yet due comes due, if any. */
    val nextDue: Long? = null,
    /** Home's name for the exam and its day, when the student set a day. */
    val examName: String? = null,
    val examDate: Long? = null,
    /** Cards and questions done today. */
    val today: Int,
    /** Kept so older files still decode; no surface shows it. */
    val streak: Int = 0,
    /** The daily goal, as Settings keeps it (GoalProgress.goal); absent in older files. */
    val goal: Int? = null,
) {
    /** One deck with cards waiting. */
    data class DueDeck(val id: String, val name: String, val count: Int)

    /** Whole days from [now] to the exam in [zone], as home counts them: 0 on the day, negative after it, null without a date. */
    fun daysToExam(now: Long, zone: ZoneId = ZoneId.systemDefault()): Int? =
        examDate?.let { ExamWeekPlanner.daysLeft(Instant.ofEpochMilli(it), Instant.ofEpochMilli(now), zone) }

    /** Home's sentence: "Step 1 in 90 days", "Finals tomorrow"; null with no date, or once it has passed. */
    fun countdown(now: Long, zone: ZoneId = ZoneId.systemDefault()): String? =
        WardWords.countdown(daysToExam(now, zone), examName)

    /** The goal to show: 50 for a file written before the goal was, and always within DailyGoal.range. */
    val goalShown: Int get() = GoalProgress.goal(goal ?: 0)

    /** The same numbers, whenever they were worked out. The app only writes the file when this is false. */
    fun sameContent(other: GlanceDigest): Boolean = copy(madeAt = 0) == other.copy(madeAt = 0)

    /** The count to show at [now]: more may have come due since, so "at least one" is honest. */
    fun dueShown(now: Long): Int {
        val next = nextDue ?: return dueNow
        return if (next <= now) maxOf(dueNow, 1) else dueNow
    }

    /** The count done today at [now]: a digest written yesterday reads 0. */
    fun todayShown(now: Long, zone: ZoneId = ZoneId.systemDefault()): Int =
        if (Instant.ofEpochMilli(madeAt).atZone(zone).toLocalDate() == Instant.ofEpochMilli(now).atZone(zone).toLocalDate()) today else 0

    companion object {
        const val currentVersion = 1

        /** Nothing known yet: a fresh install. */
        val empty = GlanceDigest(madeAt = 0, dueNow = 0, topDecks = emptyList(), today = 0, streak = 0)

        /** Dates are kept in whole seconds, as the file keeps them, so a digest read back equals the one written. */
        fun seconds(ms: Long): Long = ms - Math.floorMod(ms, 1000L)

        /**
         * Worked out from the app's figures. [due] is every due card's deck id
         * and name, in any order; the decks are counted and the busiest kept.
         * An exam day already gone is left out, and its name with it.
         */
        fun make(
            now: Long, due: List<Pair<String, String>>, nextDue: Long?, examName: String?, examDate: Long?,
            today: Int, streak: Int, goal: Int?, zone: ZoneId = ZoneId.systemDefault(),
        ): GlanceDigest {
            val counts = LinkedHashMap<String, Int>()
            val names = HashMap<String, String>()
            for ((id, name) in due) { counts[id] = (counts[id] ?: 0) + 1; names[id] = name }
            val decks = counts.map { (id, count) -> DueDeck(id, names[id] ?: "", count) }
                .sortedWith(compareByDescending<DueDeck> { it.count }.thenBy { it.name }.thenBy { it.id })
            val startOfToday = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()
            val exam = examDate?.takeIf { it >= startOfToday }
            return GlanceDigest(
                madeAt = seconds(now), dueNow = due.size, topDecks = decks.take(3), nextDue = nextDue?.let(::seconds),
                examName = if (exam == null) null else examName, examDate = exam?.let(::seconds),
                today = today, streak = streak, goal = goal,
            )
        }

        /** The file's text, as Swift's JSONEncoder writes it with .iso8601 and .sortedKeys. */
        fun encode(d: GlanceDigest): String {
            val fields = sortedMapOf<String, String>()
            fields["version"] = d.version.toString()
            fields["madeAt"] = quote(date(d.madeAt))
            fields["dueNow"] = d.dueNow.toString()
            fields["topDecks"] = d.topDecks.joinToString(",", "[", "]") { deck ->
                "{\"count\":${deck.count},\"id\":${quote(deck.id)},\"name\":${quote(deck.name)}}"
            }
            d.nextDue?.let { fields["nextDue"] = quote(date(it)) }
            d.examName?.let { fields["examName"] = quote(it) }
            d.examDate?.let { fields["examDate"] = quote(date(it)) }
            fields["today"] = d.today.toString()
            fields["streak"] = d.streak.toString()
            d.goal?.let { fields["goal"] = it.toString() }
            return fields.entries.joinToString(",", "{", "}") { (key, value) -> "${quote(key)}:$value" }
        }

        /** A file this app can read, or null: a newer app's file, or a broken one, is shown as nothing, not garbage. */
        fun decode(text: String): GlanceDigest? = runCatching {
            val o = JSONObject(text)
            val digest = GlanceDigest(
                version = o.whole("version"), madeAt = o.date("madeAt"), dueNow = o.whole("dueNow"),
                topDecks = o.getJSONArray("topDecks").let { a -> (0 until a.length()).map { deck(a.getJSONObject(it)) } },
                nextDue = o.optionalDate("nextDue"), examName = o.optionalText("examName"), examDate = o.optionalDate("examDate"),
                today = o.whole("today"), streak = o.whole("streak"), goal = if (o.isNull("goal")) null else o.whole("goal"),
            )
            digest.takeIf { it.version <= currentVersion }
        }.getOrNull()

        private fun deck(o: JSONObject) = DueDeck(o.text("id"), o.text("name"), o.whole("count"))
        private fun JSONObject.whole(key: String): Int {
            val value = get(key)
            require(value is Number && value.toDouble() == value.toInt().toDouble()) { "$key is not a whole number" }
            return value.toInt()
        }
        private fun JSONObject.text(key: String): String = get(key) as? String ?: throw IllegalArgumentException("$key is not text")
        private fun JSONObject.optionalText(key: String): String? = if (isNull(key)) null else text(key)
        private fun JSONObject.date(key: String): Long = Instant.parse(text(key)).toEpochMilli()
        private fun JSONObject.optionalDate(key: String): Long? = if (isNull(key)) null else date(key)

        /** ISO-8601 in whole seconds, UTC: "2026-11-05T08:30:00Z" (ISO8601DateFormatter's internet date-time). */
        private fun date(ms: Long): String = Instant.ofEpochMilli(seconds(ms)).toString()

        /** A JSON string as JSONEncoder writes it: UTF-8 kept as it is, "/" escaped. */
        private fun quote(s: String): String {
            val out = StringBuilder(s.length + 2).append('"')
            for (c in s) when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '/' -> out.append("\\/")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (c < ' ') out.append("\\u00").append(Integer.toHexString(c.code).padStart(2, '0')) else out.append(c)
            }
            return out.append('"').toString()
        }
    }
}

/** What a widget has to say: no file yet, nothing due, or cards waiting. */
sealed class GlanceState {
    /** The app has not written the digest (or it cannot be read): "Open Stethoscore to see your cards". */
    data object NoFile : GlanceState()
    data class NothingDue(val digest: GlanceDigest) : GlanceState()
    data class CardsDue(val digest: GlanceDigest, val count: Int) : GlanceState()
}

/**
 * Where the digest is kept: glance-digest.json in the app's own files
 * directory, beside the library. A widget runs in the app's process, so no
 * shared container is needed (iOS keeps it in the App Group).
 */
class GlanceShelf(private val directory: File) {
    val file: File get() = File(directory, fileName)

    fun read(): GlanceDigest? = runCatching { if (file.exists()) GlanceDigest.decode(file.readText(Charsets.UTF_8)) else null }.getOrNull()

    /** What to show at [now]: the read-time corrections applied. */
    fun state(now: Long): GlanceState {
        val digest = read() ?: return GlanceState.NoFile
        val due = digest.dueShown(now)
        return if (due > 0) GlanceState.CardsDue(digest, due) else GlanceState.NothingDue(digest)
    }

    /** fsync then rename, as the library is saved, so a widget never reads half a file. */
    fun write(digest: GlanceDigest): Boolean {
        val temporary = File(directory, "$fileName.tmp")
        return try {
            if (!directory.exists() && !directory.mkdirs()) return false
            FileOutputStream(temporary).use { it.write(GlanceDigest.encode(digest).toByteArray(Charsets.UTF_8)); it.fd.sync() }
            try {
                Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
                if (!temporary.renameTo(file)) return false
            }
            true
        } catch (_: Exception) {
            temporary.delete()
            false
        }
    }

    companion object {
        const val fileName = "glance-digest.json"
    }
}
