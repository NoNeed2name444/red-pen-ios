package com.stethoscore.app.data

import java.text.Normalizer
import java.util.UUID

// Finding things in a case, and how names are matched: the lookups the
// screens, the checks and the score use. Port of iOS Shared/Cases/CaseNames.swift.

// MARK: looking things up

fun CaseFile.step(id: String): CaseStep? = steps.firstOrNull { it.id == id }

fun CaseFile.steps(group: CaseStep.Group): List<CaseStep> = steps.filter { it.group == group }

val CaseFile.keySteps: List<CaseStep> get() = steps.filter { it.value == CaseStep.Yield.key }

val CaseFile.redFlagSteps: List<CaseStep> get() = steps.filter { it.redFlag }

/** The differential that is the diagnosis, if the writer listed it. */
val CaseFile.diagnosisDifferential: Differential?
    get() = differentials.firstOrNull { CaseNames.same(it.name, diagnosis.name) || it.answers(diagnosis.name) }

/** The next most likely: the first differential that is not the diagnosis. */
val CaseFile.runnerUp: Differential? get() = differentials.firstOrNull { !isDiagnosis(it.name) }

/** Whether a name - picked or typed - is the diagnosis. */
fun CaseFile.isDiagnosis(name: String): Boolean =
    CaseNames.matches(name, listOf(diagnosis.name) + diagnosis.accepted + (diagnosisDifferential?.accepted ?: emptyList()))

/** The case's own name for what was typed: a differential's, the diagnosis's or a distractor's; null when it is none of them. */
fun CaseFile.resolve(typed: String): String? {
    if (isDiagnosis(typed)) return diagnosisDifferential?.name ?: diagnosis.name
    differentials.firstOrNull { it.answers(typed) }?.let { return it.name }
    return distractors.firstOrNull { CaseNames.same(it, typed) }
}

/**
 * Everything the ladder can be picked from: the differentials and the
 * distractors, once each, in an order fixed for this case (so the list does
 * not jump about between visits) that does not give the answer away by its place.
 */
val CaseFile.candidates: List<String> get() {
    val seen = mutableSetOf<String>()
    val names = mutableListOf<String>()
    for (name in differentials.map { it.name } + distractors) {
        val key = CaseNames.normal(name)
        if (key.isEmpty() || key in seen) continue
        seen += key
        names += name
    }
    return CaseShuffle(id).shuffled(names)
}

/** Whether a typed name is this one. */
fun Differential.answers(typed: String): Boolean = CaseNames.matches(typed, listOf(name) + accepted)

/**
 * How names are compared: case, accents, punctuation and spacing aside, so
 * "Pulmonary embolism", "pulmonary-embolism" and "PE" (when accepted) match.
 */
object CaseNames {
    private fun alphanumeric(cp: Int): Boolean = Character.isLetterOrDigit(cp) || when (Character.getType(cp).toByte()) {
        Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK,
        Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
        else -> false
    }

    fun normal(text: String): String {
        val folded = Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()
        val out = StringBuilder()
        var space = false
        var i = 0
        while (i < folded.length) {
            val cp = folded.codePointAt(i)
            if (alphanumeric(cp)) {
                if (space && out.isNotEmpty()) out.append(' ')
                out.appendCodePoint(cp)
                space = false
            } else {
                space = true
            }
            i += Character.charCount(cp)
        }
        return out.toString()
    }

    fun same(a: String, b: String): Boolean {
        val x = normal(a)
        return x.isNotEmpty() && x == normal(b)
    }

    fun matches(typed: String, names: List<String>): Boolean = names.any { same(typed, it) }
}

/**
 * A shuffle that comes out the same for the same case every time (SplitMix64,
 * seeded from the case's id), drawn as Swift's `shuffled(using:)` draws so a
 * case lists its names in the same order on Android as on iOS.
 */
class CaseShuffle(seed: String) {
    private var state: ULong

    init {
        var s = 0x9E3779B97F4A7C15uL
        for (byte in bytes(seed)) s = (s xor byte.toUByte().toULong()) * 0x100000001B3uL
        state = s
    }

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    /** Lemire's nearly divisionless draw below [upperBound], as Swift's RandomNumberGenerator.next(upperBound:). */
    fun next(upperBound: ULong): ULong {
        require(upperBound != 0uL)
        var random = next()
        var high = highBits(random, upperBound)
        var low = random * upperBound
        if (low < upperBound) {
            val t = (0uL - upperBound) % upperBound
            while (low < t) {
                random = next()
                high = highBits(random, upperBound)
                low = random * upperBound
            }
        }
        return high
    }

    /** The high 64 bits of the 128-bit product, as Swift's multipliedFullWidth(by:).high. */
    private fun highBits(a: ULong, b: ULong): ULong {
        val mask = 0xFFFFFFFFuL
        val aLo = a and mask; val aHi = a shr 32
        val bLo = b and mask; val bHi = b shr 32
        val loLo = aLo * bLo
        val hiLo = aHi * bLo
        val loHi = aLo * bHi
        val hiHi = aHi * bHi
        val cross = (loLo shr 32) + (hiLo and mask) + loHi
        return hiHi + (hiLo shr 32) + (cross shr 32)
    }

    /** Fisher-Yates from the front, as Swift's MutableCollection.shuffle(using:). */
    fun <T> shuffled(items: List<T>): List<T> {
        val out = items.toMutableList()
        if (out.size <= 1) return out
        var amount = out.size
        var current = 0
        while (amount > 1) {
            val random = next(amount.toULong()).toInt()
            amount -= 1
            val other = current + random
            val held = out[current]; out[current] = out[other]; out[other] = held
            current += 1
        }
        return out
    }

    private companion object {
        /** The id's sixteen bytes when it is a UUID (as Swift's `uuid`), else its UTF-8. */
        fun bytes(seed: String): ByteArray = runCatching {
            val u = UUID.fromString(seed)
            java.nio.ByteBuffer.allocate(16).putLong(u.mostSignificantBits).putLong(u.leastSignificantBits).array()
        }.getOrElse { seed.toByteArray(Charsets.UTF_8) }
    }
}
