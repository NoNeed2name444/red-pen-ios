package com.stethoscore.app.audio

import java.text.BreakIterator
import java.text.Normalizer

// The sound of a word, whatever script it is written in (ios/RedPen/Shared/SoundKey.swift, fed0105).
//
// The recogniser writes what it hears in Arabic letters; the slides write the
// same words in English. Compared as consonant skeletons they are one word.
// The skeleton is lossy ON PURPOSE (q and k fold together, so قلب and كلب are
// one sound), and must agree exactly with iOS's, which agrees with sound() in
// consensus.py: a table learned on one is read by the other.
//
// Swift walks a String by Character (a grapheme cluster: a letter and the
// marks on it) and compares Characters by canonical equivalence, so this
// walks clusters too, and looks a cluster up in its composed form.
object SoundKey {
    private val arabicToLatin: Map<String, String> = mapOf(
        "ء" to "'", "آ" to "a", "أ" to "a", "ؤ" to "w", "إ" to "i", "ئ" to "y", "ا" to "a",
        "ب" to "b", "ة" to "a", "ت" to "t", "ث" to "th", "ج" to "g", "ح" to "h", "خ" to "kh",
        "د" to "d", "ذ" to "z", "ر" to "r", "ز" to "z", "س" to "s", "ش" to "sh", "ص" to "s",
        "ض" to "d", "ط" to "t", "ظ" to "z", "ع" to "a", "غ" to "gh", "ف" to "f", "ق" to "k",
        "ك" to "k", "ل" to "l", "م" to "m", "ن" to "n", "ه" to "h", "و" to "w", "ى" to "a",
        "ي" to "y",
    )
    /** harakat, the hamza and madda marks NFD frees from a carrier, the superscript alef, and the tatweel stretcher */
    private val marks = 0x064B..0x0655
    private val vowels = setOf('a', 'e', 'i', 'o', 'u', 'w', 'y')
    private val digraphs = listOf("sh" to "$", "th" to "0", "ph" to "f", "gh" to "g", "kh" to "X", "ck" to "k", "qu" to "k")
    private val single: Map<Char, String> = mapOf('c' to "k", 'q' to "k", 'z' to "s", 'j' to "g", 'v' to "f", 'p' to "b", 'x' to "ks")

    /** The string's Characters, as Swift counts them. */
    internal fun clusters(s: String): List<String> {
        if (s.isEmpty()) return emptyList()
        val it = BreakIterator.getCharacterInstance()
        it.setText(s)
        val out = ArrayList<String>()
        var start = it.first()
        var end = it.next()
        while (end != BreakIterator.DONE) {
            out.add(s.substring(start, end))
            start = end
            end = it.next()
        }
        return out
    }

    private fun firstScalar(ch: String): Int? = if (ch.isEmpty()) null else ch.codePointAt(0)

    private fun isArabicLetterScalar(v: Int): Boolean = v in 0x0621..0x064A || v in 0x066E..0x06D3

    fun isArabicLetter(ch: String): Boolean = firstScalar(ch)?.let(::isArabicLetterScalar) ?: false

    fun hasArabic(s: String): Boolean = clusters(s).any(::isArabicLetter)

    /** Egyptian glues و/ف/ب/ل onto the definite article, so والـ is the article wearing a conjunction. Both come off. */
    fun stripArticle(s: String): String {
        var t = clusters(s)
        val first = t.firstOrNull()
        if (first != null && first in listOf("و", "ف", "ب", "ل") && t.size > 3) {
            val rest = t.drop(1)
            if (rest.take(2) == listOf("ا", "ل")) t = rest
        }
        if (t.take(3) == listOf("ا", "ل", "ـ")) return t.drop(3).joinToString("")
        if (t.take(2) == listOf("ا", "ل")) return t.drop(2).joinToString("")
        return t.joinToString("")
    }

    internal fun fold(s: String): String {
        val out = StringBuilder()
        for (ch in clusters(Normalizer.normalize(s, Normalizer.Form.NFD))) {
            val v = firstScalar(ch) ?: continue
            if (v in marks || v == 0x0670 || v == 0x0640) continue
            when (ch) {
                "ى" -> out.append("ي")      // alef maqsura reads as ya
                "ة" -> out.append("ه")      // ta marbuta reads as ha
                else -> out.append(ch)
            }
        }
        return out.toString()
    }

    internal fun romanize(s: String): String {
        val out = StringBuilder()
        for (ch in clusters(s)) {
            val latin = arabicToLatin[Normalizer.normalize(ch, Normalizer.Form.NFC)]
            if (latin != null) out.append(latin) else if (!isArabicLetter(ch)) out.append(ch)
        }
        return out.toString()
    }

    /** 'ch' is /k/ in Greek-derived medical words (chronic, chloride) and a different sound otherwise, so it splits on the letter that follows it. */
    internal fun foldCh(s: String): String {
        val out = StringBuilder()
        var i = 0
        while (i < s.length) {
            if (s[i] == 'c' && i + 1 < s.length && s[i + 1] == 'h') {
                val next = if (i + 2 < s.length) s[i + 2] else ' '
                out.append(if (next == 'r' || next == 'l') "k" else "$")
                i += 2
                continue
            }
            out.append(s[i])
            i += 1
        }
        return out.toString()
    }

    internal fun skeleton(raw: String): String {
        var s = clusters(raw.lowercase()).joinToString("") { ch ->
            val ascii = ch.length == 1 && ch[0].code < 128
            if ((ascii && ch[0].isLetter()) || ch == "'" || ch == " ") ch else " "
        }
        s = foldCh(s)
        for ((from, to) in digraphs) s = s.replace(from, to)
        s = s.map { single[it] ?: it.toString() }.joinToString("")
        s = s.filter { it !in vowels && it != '\'' }
        // collapse runs: the recogniser's split keeps a doubled letter across a space that the joined word has already lost
        val collapsed = StringBuilder()
        for (ch in s) if (collapsed.isEmpty() || collapsed.last() != ch) collapsed.append(ch)
        return collapsed.toString().trim(' ', '\t')
    }

    private const val edges = " .,:;!?\"'()[]{}…،؛؟-"

    /** The key a token is stored and looked up under. */
    fun of(token: String): String {
        val bare = token.trim { it in edges }
        if (!hasArabic(bare)) return skeleton(bare.lowercase())
        return skeleton(romanize(fold(stripArticle(bare))))
    }

    fun of(span: List<String>): String = span.joinToString(" ") { of(it) }

    /** The same sound with the word boundary removed: a two-token span and a one-word spelling have to be comparable. */
    fun collapsed(key: String): String {
        val out = StringBuilder()
        for (ch in key) if (ch != ' ' && (out.isEmpty() || out.last() != ch)) out.append(ch)
        return out.toString()
    }
}
