package com.stethoscore.app.data

import java.time.Instant
import java.time.ZoneId
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.roundToLong

/**
 * FSRS-5, the Free Spaced Repetition Scheduler Anki ships, with its published default
 * weights. Port of ios/RedPen/Shared/FSRS.swift. Stability is how many days recall takes to
 * fall to 90%; difficulty (1 to 10) is how hard the card is to push up. Grades are Anki's:
 * 1 Again, 2 Hard, 3 Good, 4 Easy. Optional: Classic stays the default.
 */
object FSRS {
    val defaultWeights = doubleArrayOf(
        0.40255, 1.18385, 3.173, 15.69105, 7.1949,
        0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698,
        0.2315, 2.9898, 0.51655, 0.6621,
    )
    const val decay = -0.5
    const val factor = 19.0 / 81.0
    const val defaultRetention = 0.9
    const val minStability = 0.01
    const val maxStability = 36_500.0

    data class State(val stability: Double, val difficulty: Double)

    private fun w(i: Int, weights: DoubleArray) = if (i in weights.indices) weights[i] else defaultWeights[i]
    private fun clampGrade(g: Int) = g.coerceIn(1, 4)
    private fun clampD(d: Double) = d.coerceIn(1.0, 10.0)
    private fun clampS(s: Double) = if (!s.isFinite()) maxStability else s.coerceIn(minStability, maxStability)

    fun retrievability(elapsedDays: Double, stability: Double): Double =
        (1 + factor * maxOf(0.0, elapsedDays) / clampS(stability)).pow(decay)

    fun intervalDays(stability: Double, retention: Double = defaultRetention): Double {
        val r = retention.coerceIn(0.7, 0.99)
        return clampS(stability) / factor * (r.pow(1 / decay) - 1)
    }

    fun initialStability(grade: Int, weights: DoubleArray = defaultWeights) = clampS(w(clampGrade(grade) - 1, weights))

    fun initialDifficulty(grade: Int, weights: DoubleArray = defaultWeights): Double =
        clampD(w(4, weights) - exp(w(5, weights) * (clampGrade(grade) - 1)) + 1)

    fun nextDifficulty(d: Double, grade: Int, weights: DoubleArray = defaultWeights): Double {
        val delta = -w(6, weights) * (clampGrade(grade) - 3)
        val damped = d + delta * (10 - d) / 9
        val pull = w(7, weights)
        return clampD(pull * initialDifficulty(4, weights) + (1 - pull) * damped)
    }

    fun recallStability(s: Double, difficulty: Double, retrievability: Double, grade: Int, weights: DoubleArray = defaultWeights): Double {
        val g = clampGrade(grade)
        val hardPenalty = if (g == 2) w(15, weights) else 1.0
        val easyBonus = if (g == 4) w(16, weights) else 1.0
        val growth = exp(w(8, weights)) * (11 - difficulty) * clampS(s).pow(-w(9, weights)) *
            (exp(w(10, weights) * (1 - retrievability)) - 1) * hardPenalty * easyBonus
        return clampS(s * (growth + 1))
    }

    fun forgetStability(s: Double, difficulty: Double, retrievability: Double, weights: DoubleArray = defaultWeights): Double {
        val fresh = w(11, weights) * difficulty.pow(-w(12, weights)) * ((clampS(s) + 1).pow(w(13, weights)) - 1) *
            exp(w(14, weights) * (1 - retrievability))
        val shortCap = s / exp(w(17, weights) * w(18, weights))
        return clampS(minOf(fresh, shortCap))
    }

    fun shortTermStability(s: Double, grade: Int, weights: DoubleArray = defaultWeights): Double =
        clampS(s * exp(w(17, weights) * (clampGrade(grade) - 3 + w(18, weights))))

    fun next(previous: State?, grade: Int, elapsedDays: Double, weights: DoubleArray = defaultWeights): State {
        val g = clampGrade(grade)
        if (previous == null) return State(initialStability(g, weights), initialDifficulty(g, weights))
        val d = nextDifficulty(previous.difficulty, g, weights)
        val s = if (elapsedDays < 1) shortTermStability(previous.stability, g, weights) else {
            val r = retrievability(elapsedDays, previous.stability)
            if (g == 1) forgetStability(previous.stability, previous.difficulty, r, weights)
            else recallStability(previous.stability, previous.difficulty, r, g, weights)
        }
        return State(s, d)
    }

    /** A memory for a card Classic scheduled before FSRS was switched on. */
    fun estimated(intervalDays: Double, lapses: Int) = State(clampS(maxOf(0.1, intervalDays)), clampD(5.0 + maxOf(0, lapses)))
}

/** Which scheduler rates cards. Classic is the app's own and stays the default. */
enum class ReviewScheduler(val title: String) { CLASSIC("Classic"), FSRS("FSRS") }

/** How many cards a day. Zero means no limit, which is the default. */
data class ReviewLimits(val newPerDay: Int = 0, val reviewsPerDay: Int = 0) {
    val isUnlimited get() = newPerDay <= 0 && reviewsPerDay <= 0
    companion object { val unlimited = ReviewLimits() }
}

/** Settings > Review, kept on this device beside the library (iOS keeps them in UserDefaults). */
data class ReviewSettings(val scheduler: ReviewScheduler = ReviewScheduler.CLASSIC, val limits: ReviewLimits = ReviewLimits.unlimited)

/** A study day, as Anki counts one: it turns over at 4 in the morning. */
object ReviewDay {
    const val rolloverHours = 4L

    fun start(of: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
        val shift = rolloverHours * 3_600_000
        val day = Instant.ofEpochMilli(of - shift).atZone(zone).toLocalDate().atStartOfDay(zone)
        return day.toInstant().toEpochMilli() + shift
    }

    /**
     * When "bury until tomorrow" ends: the next day's start. As iOS does it, a calendar day
     * added to today's start, so across a clock change it keeps today's start's wall-clock time.
     */
    fun next(after: Long, zone: ZoneId = ZoneId.systemDefault()): Long =
        Instant.ofEpochMilli(start(after, zone)).atZone(zone).plusDays(1).toInstant().toEpochMilli()
}

/**
 * What the accuracy check has graded Flagged (possibly wrong), by item id: held back from
 * daily review so a wrong fact is not drilled in. Empty where no check has run, so nothing
 * is held for want of one. Port of iOS AccuracyHolds.
 */
object AccuracyHolds {
    private val flagged = HashSet<String>()

    @Synchronized fun update(id: String, flagged: Boolean) { if (flagged) this.flagged.add(id) else this.flagged.remove(id) }
    @Synchronized fun snapshot(): Set<String> = flagged.toSet()
    fun isHeld(id: String): Boolean = id in snapshot()
    @Synchronized fun reset() = flagged.clear()
}

/** Daily limits, holds and the scheduler switch. Port of ios/RedPen/Shared/ReviewOptions.swift. */
object ReviewOptions {
    enum class Stage { NEW, LEARNING, REVIEW }

    fun stage(record: ReviewRecord?): Stage = when {
        record == null || record.reviews <= 0 -> Stage.NEW
        record.intervalMin < ExamCap.day -> Stage.LEARNING
        else -> Stage.REVIEW
    }

    fun isHeld(record: ReviewRecord?, now: Long): Boolean =
        record != null && (record.suspended || (record.buriedUntil ?: 0) > now)

    data class DayCounts(val newCards: Int = 0, val reviews: Int = 0)

    /** New cards first rated today and review cards rated today, read from the schedule itself. */
    fun counts(records: Map<String, ReviewRecord>, now: Long, zone: ZoneId = ZoneId.systemDefault()): DayCounts {
        val start = ReviewDay.start(now, zone)
        var fresh = 0; var reviews = 0
        for (r in records.values) {
            if (r.reviews <= 0 || r.ratedAt < start) continue
            val newToday = r.introducedAt?.let { it >= start } ?: (r.reviews == 1)
            if (newToday) fresh++ else reviews++
        }
        return DayCounts(fresh, reviews)
    }

    /** What is left of today's limits. Learning cards are never limited, as in Anki. */
    class Allowance(limits: ReviewLimits, counts: DayCounts) {
        var newLeft: Int? = if (limits.newPerDay > 0) maxOf(0, limits.newPerDay - counts.newCards) else null; private set
        var reviewsLeft: Int? = if (limits.reviewsPerDay > 0) maxOf(0, limits.reviewsPerDay - counts.reviews) else null; private set

        fun take(stage: Stage): Boolean = when (stage) {
            Stage.LEARNING -> true
            Stage.NEW -> newLeft.let { left -> if (left == null) true else if (left <= 0) false else { newLeft = left - 1; true } }
            Stage.REVIEW -> reviewsLeft.let { left -> if (left == null) true else if (left <= 0) false else { reviewsLeft = left - 1; true } }
        }
    }

    fun allowance(limits: ReviewLimits, records: Map<String, ReviewRecord>, now: Long, today: DayCounts? = null, zone: ZoneId = ZoneId.systemDefault()) =
        Allowance(limits, if (limits.isUnlimited) DayCounts() else today ?: counts(records, now, zone))

    /** Cards due now, not held and not Flagged, soonest first, with their stage. */
    private fun due(cards: List<AnkiCard>, records: Map<String, ReviewRecord>, now: Long): List<Pair<AnkiQueueItem, Stage>> {
        val held = AccuracyHolds.snapshot()
        return cards.mapNotNull { card ->
            if (card.id in held) return@mapNotNull null
            val stored = records[card.id]
            if (isHeld(stored, now)) return@mapNotNull null
            val record = ReviewPlan.record(card, records, now)
            if (record.due > now) null else AnkiQueueItem(card, record.due, record.intervalMin) to stage(stored)
        }.sortedBy { it.first.due }
    }

    /** One deck's queue for today: due, not held, within the day's limits. */
    fun dailyQueue(cards: List<AnkiCard>, records: Map<String, ReviewRecord>, now: Long, limits: ReviewLimits, today: DayCounts? = null, zone: ZoneId = ZoneId.systemDefault()): List<AnkiQueueItem> {
        val budget = allowance(limits, records, now, today, zone)
        return due(cards, records, now).filter { budget.take(it.second) }.map { it.first }
    }

    /** Everything due across the library today, within the library's limits, soonest first. */
    fun <D : ReviewDeck> dueToday(decks: List<D>, records: Map<String, ReviewRecord>, now: Long, limits: ReviewLimits, cap: Int = 500, today: DayCounts? = null, zone: ZoneId = ZoneId.systemDefault()): List<ReviewPlan.Due> {
        val budget = allowance(limits, records, now, today, zone)
        val held = AccuracyHolds.snapshot()
        val found = ArrayList<Pair<ReviewPlan.Due, Stage>>()
        for (deck in decks) for (card in deck.deckCards) {
            if (card.id in held) continue
            val stored = records[card.id]
            if (isHeld(stored, now)) continue
            val kept = ReviewPlan.record(card, records, now)
            if (kept.due > now) continue
            found.add(ReviewPlan.Due(deck.deckId, deck.deckName, card, kept.due) to stage(stored))
        }
        found.sortBy { it.first.due }
        val out = ArrayList<ReviewPlan.Due>()
        for (entry in found) {
            if (out.size >= cap) break
            if (budget.take(entry.second)) out.add(entry.first)
        }
        return out
    }

    /** Study ahead: the whole deck, except what the student suspended. */
    fun studyAhead(cards: List<AnkiCard>, records: Map<String, ReviewRecord>, now: Long): List<AnkiQueueItem> =
        ReviewPlan.everything(cards.filter { records[it.id]?.suspended != true }, records, now)

    // ---- suspend, bury, undo ----

    /** The card suspended (or let back in). A card never rated gets a record to carry it. */
    fun suspending(card: AnkiCard, on: Boolean, records: Map<String, ReviewRecord>, now: Long): ReviewRecord =
        ReviewPlan.record(card, records, now).copy(suspended = on, changedAt = now)

    /** The card out of today's queues, back at the next day's start. */
    fun burying(card: AnkiCard, records: Map<String, ReviewRecord>, now: Long, zone: ZoneId = ZoneId.systemDefault()): ReviewRecord =
        ReviewPlan.record(card, records, now).copy(buriedUntil = ReviewDay.next(now, zone), changedAt = now)

    /**
     * What undoing a rating writes back: the record from before it, stamped now so a merge
     * takes the undo over the rating it cancels. A card that had no record gets a fresh,
     * never-rated one for the same reason.
     */
    fun restoring(previous: ReviewRecord?, now: Long): ReviewRecord =
        (previous ?: ReviewRecord(due = now, intervalMin = 0.0, ratedAt = now)).copy(changedAt = now)

    /** How many cards [dailyQueue] would hold; the library's limits apply once across all decks given. */
    fun dueCount(cards: List<AnkiCard>, records: Map<String, ReviewRecord>, now: Long, limits: ReviewLimits, today: DayCounts? = null, zone: ZoneId = ZoneId.systemDefault()): Int {
        var learning = 0; var fresh = 0; var reviewing = 0
        val held = AccuracyHolds.snapshot()
        for (card in cards) {
            val stored = records[card.id]
            if (isHeld(stored, now)) continue
            if (card.id in held) continue
            if (ReviewPlan.record(card, records, now).due > now) continue
            when (stage(stored)) { Stage.LEARNING -> learning++; Stage.NEW -> fresh++; Stage.REVIEW -> reviewing++ }
        }
        if (limits.isUnlimited) return learning + fresh + reviewing
        val left = allowance(limits, records, now, today, zone)
        return learning + (left.newLeft?.let { minOf(it, fresh) } ?: fresh) + (left.reviewsLeft?.let { minOf(it, reviewing) } ?: reviewing)
    }

    // ---- the scheduler switch ----

    fun after(rating: AnkiRating, record: ReviewRecord, now: Long, exam: Long?, scheduler: ReviewScheduler): ReviewRecord = when (scheduler) {
        ReviewScheduler.CLASSIC -> ReviewPlan.after(rating, record, now, exam).copy(stability = null, difficulty = null)
        ReviewScheduler.FSRS -> fsrsAfter(rating, record, now, exam)
    }

    fun previewLabels(record: ReviewRecord, now: Long, exam: Long?, scheduler: ReviewScheduler): Map<AnkiRating, String> {
        if (scheduler == ReviewScheduler.CLASSIC) return ReviewPlan.previewLabels(record, now, exam)
        val plan = fsrsPlan(record, now)
        return AnkiRating.entries.associateWith { "in " + AnkiScheduler.formatInterval(ExamCap.capped(plan.getValue(it).minutes, now, exam)) }
    }

    data class FSRSStep(val minutes: Double, val state: FSRS.State)

    fun grade(rating: AnkiRating) = when (rating) { AnkiRating.AGAIN -> 1; AnkiRating.HARD -> 2; AnkiRating.GOOD -> 3; AnkiRating.EASY -> 4 }

    /**
     * All four ratings' outcomes at once, so the buttons and the stored schedule read the
     * same numbers and Hard < Good < Easy always holds. Learning steps are Anki's defaults
     * (1 and 10 minutes); Good on the last step, or Easy at any time, graduates the card.
     */
    fun fsrsPlan(kept: ReviewRecord, now: Long): Map<AnkiRating, FSRSStep> {
        val seen = kept.reviews > 0
        val elapsed = if (seen) maxOf(0L, now - kept.ratedAt) / 86_400_000.0 else 0.0
        val prior = if (seen) memory(kept) else null
        val learning = !seen || kept.intervalMin < ExamCap.day
        val lastStep = seen && kept.intervalMin >= 10
        val states = AnkiRating.entries.associateWith { FSRS.next(prior, grade(it), elapsed) }
        val hardS = states.getValue(AnkiRating.HARD); val goodS = states.getValue(AnkiRating.GOOD); val easyS = states.getValue(AnkiRating.EASY)
        var hard: Double; var good: Double
        if (learning) {
            hard = if (lastStep) 10.0 else 6.0
            good = if (lastStep) graduated(goodS) else 10.0
        } else {
            hard = graduated(hardS)
            good = maxOf(graduated(goodS), hard + ExamCap.day)
        }
        val easyFloor = if (good >= ExamCap.day) good + ExamCap.day else ExamCap.day
        val easy = minOf(AnkiScheduler.maxIntervalMin, maxOf(graduated(easyS), easyFloor))
        hard = minOf(AnkiScheduler.maxIntervalMin, hard); good = minOf(AnkiScheduler.maxIntervalMin, good)
        return mapOf(
            AnkiRating.AGAIN to FSRSStep(1.0, states.getValue(AnkiRating.AGAIN)),
            AnkiRating.HARD to FSRSStep(hard, hardS),
            AnkiRating.GOOD to FSRSStep(good, goodS),
            AnkiRating.EASY to FSRSStep(easy, easyS),
        )
    }

    fun memory(kept: ReviewRecord): FSRS.State {
        val s = kept.stability; val d = kept.difficulty
        return if (s != null && d != null && s > 0) FSRS.State(s, d) else FSRS.estimated(kept.intervalMin / ExamCap.day, kept.lapses)
    }

    /** Whole days, at least one, for recall to fall to 90%. */
    fun graduated(state: FSRS.State): Double {
        val whole = maxOf(1.0, FSRS.intervalDays(state.stability).roundToLong().toDouble())
        return minOf(AnkiScheduler.maxIntervalMin, whole * ExamCap.day)
    }

    fun fsrsAfter(rating: AnkiRating, kept: ReviewRecord, now: Long, exam: Long?): ReviewRecord {
        val step = fsrsPlan(kept, now)[rating] ?: FSRSStep(1.0, memory(kept))
        val next = ExamCap.capped(step.minutes, now, exam)
        val lapse = if (rating == AnkiRating.AGAIN && kept.reviews > 0) 1 else 0
        return ReviewRecord(
            due = now + (next * 60_000).toLong(), intervalMin = next, reviews = kept.reviews + 1, lapses = kept.lapses + lapse,
            ratedAt = now, suspended = kept.suspended, stability = step.state.stability, difficulty = step.state.difficulty,
            introducedAt = if (kept.reviews == 0) now else kept.introducedAt, rawJson = kept.rawJson,
        )
    }
}
