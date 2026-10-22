package com.stethoscore.app.audio

// Fix this word (ios/RedPen/Shared/Corrections.swift, fed0105).
//
// The student taps a word that came out wrong, types what it should say, and
// three things happen at once: that word is fixed; every OTHER word in the
// transcript that sounds the same is fixed too, reported and undoable; and the
// pronunciation is remembered, so the next lecture never shows it. Nothing is
// guessed: a correction only replaces spans that sound like the one the
// student pointed at.

data class CorrectionChange(val segment: Int, val firstWord: Int, val lastWord: Int, val was: String, val now: String)

data class CorrectionOutcome(
    /** the span the student pointed at */
    val here: CorrectionChange? = null,
    /** every other span that sounded the same */
    val elsewhere: List<CorrectionChange> = emptyList(),
    /** whether the pronunciation was added to the store */
    val learned: Boolean = false,
    /** a span that sounded the same but was ALREADY spelled the new way, so it needed no change */
    val alreadyRight: Int = 0,
) {
    val changed: Int get() = (if (here == null) 0 else 1) + elsewhere.size

    /** What to put on screen. Deliberately plain: the student is mid-lecture. */
    fun summary(): String {
        if (here == null) return "Nothing to fix"
        if (elsewhere.isEmpty()) return if (learned) "Fixed, and remembered" else "Fixed"
        val others = if (elsewhere.size == 1) "1 more like it" else "${elsewhere.size} more like it"
        return if (learned) "Fixed $others, and remembered" else "Fixed $others"
    }
}

object TranscriptCorrections {
    /** Tokens of one phrase, so a replacement can be spliced without disturbing what is around it. */
    fun tokens(text: String): List<String> = text.split(' ').filter { it.isNotEmpty() }

    /** The lecturer's definite article stays where he put it. */
    fun withArticle(head: String, spelling: String): String {
        val bare = SoundKey.stripArticle(head)
        return if (bare != head && SoundKey.clusters(head).size > 3) "الـ $spelling" else spelling
    }

    /**
     * The student fixed one word (or a short run of words, [words] inclusive).
     * [segments] is edited in place. The store learns the pronunciation with
     * correction evidence, which outranks anything else.
     */
    fun fix(segment: Int, words: IntRange, to: String, segments: MutableList<String>, store: PronunciationStore,
            spreadToRest: Boolean = true): CorrectionOutcome {
        val wanted = to.trim()
        if (segment !in segments.indices || wanted.isEmpty()) return CorrectionOutcome()
        val parts = tokens(segments[segment])
        if (words.first < 0 || words.last >= parts.size) return CorrectionOutcome()
        val span = parts.subList(words.first, words.last + 1).toList()
        val key = SoundKey.of(span)
        if (key.trim(' ', '\t').isEmpty()) return CorrectionOutcome()

        val was = span.joinToString(" ")
        val width = span.size
        // Where the student's own span sits; replacing an EARLIER span in the
        // same phrase shortens it, so this moves with it.
        var targetStart = words.first
        val elsewhere = ArrayList<CorrectionChange>()
        var alreadyRight = 0

        // Everywhere else first, so the word just fixed is never mistaken for one of the others it taught.
        if (spreadToRest) {
            for (i in segments.indices) {
                val line = tokens(segments[i]).toMutableList()
                var j = 0
                var touched = false
                while (j + width <= line.size) {
                    if (i == segment && j == targetStart) { j += width; continue }
                    val here = line.subList(j, j + width).toList()
                    if (SoundKey.of(here) != key) { j += 1; continue }
                    if (here.joinToString(" ").equals(wanted, ignoreCase = true)) {
                        alreadyRight += 1
                        j += width
                        continue
                    }
                    val replacement = withArticle(line[j], wanted)
                    repeat(width) { line.removeAt(j) }
                    line.add(j, replacement)
                    elsewhere.add(CorrectionChange(i, j, j + width - 1, here.joinToString(" "), wanted))
                    if (i == segment && j < targetStart) targetStart -= (width - 1)
                    touched = true
                    j += 1
                }
                if (touched) segments[i] = line.joinToString(" ")
            }
        }

        var here: CorrectionChange? = null
        val finalParts = tokens(segments[segment]).toMutableList()
        val last = targetStart + width - 1
        if (targetStart >= 0 && last < finalParts.size) {
            val replacement = withArticle(finalParts[targetStart], wanted)
            repeat(width) { finalParts.removeAt(targetStart) }
            finalParts.add(targetStart, replacement)
            segments[segment] = finalParts.joinToString(" ")
            here = CorrectionChange(segment, targetStart, last, was, wanted)
        }
        val learned = OnDeviceLearning.fromCorrection(span, wanted, store)
        return CorrectionOutcome(here, elsewhere, learned, alreadyRight)
    }

    /** Put back everything one correction changed, from the snapshot the caller took before [fix]. */
    fun undo(snapshot: List<String>, segments: MutableList<String>, touching: CorrectionOutcome) {
        val indexes = touching.elsewhere.map { it.segment }.toMutableSet()
        touching.here?.let { indexes.add(it.segment) }
        for (i in indexes) if (i in snapshot.indices && i in segments.indices) segments[i] = snapshot[i]
    }

    /** Apply everything already learned to a transcript that has just arrived: a mistake corrected once never shows again. */
    fun applyLearned(store: PronunciationStore, segments: MutableList<String>): Int {
        var fixed = 0
        for (i in segments.indices) {
            val applied = store.apply(segments[i])
            if (applied.hits.isNotEmpty()) {
                segments[i] = applied.text
                fixed += applied.hits.size
            }
        }
        return fixed
    }
}
