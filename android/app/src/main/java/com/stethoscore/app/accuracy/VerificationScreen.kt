package com.stethoscore.app.accuracy

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist

/**
 * The verification layer's first stage on newly generated material, before
 * it is saved. It replaces the single-model accuracy checker the generators
 * used to wait on (the owner, 1 Oct): the same sensors the Worker runs
 * ([AccuracyRules]), on the device and instant.
 *
 * An item broken in its structure is removed, since it cannot be learned
 * from: no key, a key its own explanation contradicts or calls wrong, a
 * distractor that copies the key, "all of the above" keyed beside "none of
 * the above" (DNA brief: an unrecoverable item is removed cleanly, with its
 * reason). Everything else is kept. A medical red flag - a dose outside any
 * usual range, a retired practice, a look-alike drug, an impossible result -
 * grades the item Flagged, which holds it out of review and mock papers
 * until the checkers clear it. The rest of the layer - two model families
 * solving blind, the literature, the calibrated verdict - takes the set as
 * soon as it is saved.
 *
 * A port of iOS Shared/Accuracy/VerificationScreen.swift: the same rules, the
 * same reasons and the same words in the note.
 */
object VerificationScreen {

    /** Hits that make an item unusable as written. */
    fun breaks(hit: AccuracyRules.Hit): Boolean = when (hit.rule) {
        "no-key", "key-explanation-conflict", "key-called-wrong", "all-above-contradiction" -> true
        "duplicate-option" -> hit.isSevere
        else -> false
    }

    /** Why an item was removed, in words. */
    fun reason(rule: String): String = when (rule) {
        "no-key" -> "no answer key"
        "key-explanation-conflict", "key-called-wrong" -> "key contradicted by its explanation"
        "duplicate-option" -> "two identical correct options"
        "all-above-contradiction" -> "contradictory “of the above” options"
        else -> rule
    }

    /** How many items were removed for one reason. */
    data class Removal(val reason: String, val count: Int)

    data class Outcome<Item>(
        val kept: List<Item> = emptyList(),
        /** Removed items, counted by reason, in the order first met. */
        val removed: List<Removal> = emptyList(),
        /** Kept but held for the checkers: a severe medical red flag. */
        val held: Int = 0,
    ) {
        val removedCount: Int get() = removed.sumOf { it.count }
    }

    fun questions(questions: List<MCQQuestion>): Outcome<MCQQuestion> = screen(questions) { AccuracyItem.mcq(it) }

    fun stations(stations: List<OsceChecklist>): Outcome<OsceChecklist> = screen(stations) { AccuracyItem.osce(it) }

    fun cards(cards: List<AnkiCard>): Outcome<AnkiCard> = screen(cards) { AccuracyItem.card(it) }

    /** An item that gives no [AccuracyItem] has nothing to check and is kept. */
    fun <Item> screen(items: List<Item>, asItem: (Item) -> AccuracyItem?): Outcome<Item> {
        val kept = mutableListOf<Item>()
        val removed = mutableListOf<Removal>()
        var held = 0
        for (thing in items) {
            val checked = asItem(thing)
            if (checked == null) {
                kept += thing
                continue
            }
            val hits = AccuracyRules.hits(checked)
            val broken = hits.firstOrNull { breaks(it) }
            if (broken != null) {
                val why = reason(broken.rule)
                val at = removed.indexOfFirst { it.reason == why }
                if (at >= 0) removed[at] = removed[at].copy(count = removed[at].count + 1)
                else removed += Removal(why, 1)
                continue
            }
            if (hits.any { it.isSevere }) held += 1
            kept += thing
        }
        return Outcome(kept, removed, held)
    }

    /**
     * The status line's sentence: what the on-device checks did, and that
     * the independent checkers are on the rest. Empty when nothing was made.
     */
    fun <Item> note(outcome: Outcome<Item>): String {
        if (outcome.kept.isEmpty() && outcome.removedCount <= 0) return ""
        val parts = mutableListOf<String>()
        if (outcome.removedCount > 0) {
            val reasons = outcome.removed.joinToString(", ") { "${it.count} ${it.reason}" }
            parts += "${outcome.removedCount} removed ($reasons)"
        }
        if (outcome.held > 0) parts += "${outcome.held} held for a red flag"
        val device = if (parts.isEmpty()) " On-device checks passed." else " On-device checks: " + parts.joinToString("; ") + "."
        return "$device The independent checkers are verifying the rest now."
    }
}
