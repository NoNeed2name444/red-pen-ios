package com.stethoscore.app.data

import com.stethoscore.app.quiz.MockRandom

// Ported from ios/RedPen/Shared/Learn/Pretest.swift. Tested by LearnTest.

/**
 * "Guess first": five quick questions before a new textbook or narrate set
 * is read for the first time.
 *
 * Trying to answer before studying, then seeing the answer, makes the
 * material stick better than reading alone - even when the guesses are wrong
 * (the pretesting effect). So the questions are made from the set's own
 * text, on the device, with no model: a sentence that carries one of the
 * text's key terms, with that term blanked, and four other key terms from
 * the same text as the other options. Nothing is invented.
 */
object Pretest {
    /** How many questions a pretest asks. */
    const val count = 5
    /** Options per question, A to E. */
    const val optionCount = 5
    /** The one line on screen about why this is worth it. */
    const val why = "Guessing before you read, then seeing the answer, helps it stick — even when the guess is wrong."

    private data class Ranked(val index: Int, val sentence: String, val terms: List<Pair<String, Int>>)
    private data class Pick(val index: Int, val sentence: String, val term: String)

    /** Up to [count] fill-the-gap questions from [text], spread through it. */
    fun questions(text: String, count: Int = Pretest.count, seed: ULong = 1uL): List<MCQQuestion> {
        val sentences = sentences(plain(text))
        if (sentences.isEmpty()) return emptyList()
        val freq = termFrequencies(sentences)
        val terms = freq.filter { it.value >= 2 }.map { it.key }
        if (terms.size < optionCount) return emptyList()

        // the best sentence in each stretch of the text, so the questions
        // cover the whole of it rather than the first page; each term asked
        // about once, so a chapter's topic word is not the answer five times
        val ranked = sentences.mapIndexed { i, s -> Ranked(i, s, keyTerms(s, freq)) }
        val stretch = maxOf(1, (sentences.size + count - 1) / count)
        val chosen = mutableListOf<Pair<String, String>>()
        val usedTerms = HashSet<String>()
        val usedSentences = HashSet<Int>()
        fun best(range: IntRange?): Pick? {
            var top: Pick? = null
            var topScore = 0
            for (c in ranked) {
                if (c.index in usedSentences || (range != null && c.index !in range)) continue
                val t = c.terms.firstOrNull { it.first.lowercase() !in usedTerms } ?: continue
                if (top == null || t.second > topScore) {
                    top = Pick(c.index, c.sentence, t.first)
                    topScore = t.second
                }
            }
            return top
        }
        fun take(pick: Pick) {
            chosen.add(pick.sentence to pick.term)
            usedTerms.add(pick.term.lowercase())
            usedSentences.add(pick.index)
        }
        for (part in 0 until count) best(part * stretch until part * stretch + stretch)?.let(::take)
        // a short text: top up from anywhere
        while (chosen.size < count) take(best(null) ?: break)

        val rng = Mixer(if (seed == 0uL) 0x9E3779B97F4A7C15uL else seed)
        val out = mutableListOf<MCQQuestion>()
        for ((sentence, term) in chosen) {
            val wrong = distractors(term, sentence, terms)
            if (wrong.size != optionCount - 1) continue
            val options = rng.shuffled(wrong + term)
            out.add(MCQQuestion(stem = blanked(term, sentence), options = options,
                correctIndex = options.indexOf(term).coerceAtLeast(0), explanation = sentence))
        }
        return out
    }

    // MARK: the pieces

    /** Markdown down to prose: headings, emphasis, list markers, code and links' brackets go. */
    fun plain(text: String): String = text.split("\r\n", "\n", "\r").joinToString("\n") { raw ->
        var line = raw.trim(' ', '\t')
        while (line.isNotEmpty() && line[0] in "#>-*+|") line = line.substring(1)
        line = line.replace("**", "").replace("__", "").replace("`", "").replace("[", "").replace("]", "")
        line.trim(' ', '\t')
    }

    /** Sentences of 8 to 40 words. */
    fun sentences(text: String): List<String> {
        val out = mutableListOf<String>()
        val current = StringBuilder()
        fun flush() {
            val s = current.toString().trim()
            current.clear()
            val words = s.split(' ').count { it.isNotEmpty() }
            if (words in 8..40) out.add(s)
        }
        for ((i, ch) in text.withIndex()) {
            if (ch == '\n') {
                flush()
                continue
            }
            current.append(ch)
            if (ch in ".?!") {
                val next = if (i + 1 < text.length) text[i + 1] else null
                // "e.g." and "2.5" are not the end of a sentence
                if (next == null || next == ' ' || next == '\n') {
                    val tail = current.takeLast(5).toString().lowercase()
                    if (!tail.endsWith("e.g.") && !tail.endsWith("i.e.") && !tail.endsWith("vs.")) flush()
                }
            }
        }
        flush()
        return out
    }

    /** Common words that are never the point of a sentence. */
    val stopwords: Set<String> = setOf(
        "about", "above", "after", "again", "against", "along", "also", "although", "always", "among",
        "another", "around", "because", "been", "before", "being", "below", "between", "both", "cause",
        "caused", "causes", "could", "does", "doing", "down", "during", "each", "either", "every",
        "first", "following", "from", "further", "have", "having", "here", "however", "into", "itself",
        "later", "least", "less", "like", "likely", "made", "make", "many", "might", "more", "most",
        "much", "must", "never", "often", "only", "other", "others", "over", "patient", "patients",
        "people", "rather", "same", "second", "seen", "should", "shows", "since", "some", "such",
        "than", "that", "their", "them", "then", "there", "these", "they", "this", "those", "though",
        "three", "through", "under", "until", "usually", "used", "using", "very", "what", "when",
        "where", "whether", "which", "while", "with", "within", "without", "would", "your", "years",
        "common", "commonly", "important", "include", "includes", "including", "known", "called",
        "usual", "emerges", "passes", "pushes", "appears", "typically", "typical", "result", "results", "occur", "occurs", "found", "given",
    )

    /**
     * A word worth blanking: at least five letters, not a stopword. Words
     * ending "-ing" or "-ed" are nearly always verbs here, and a verb makes a
     * poor blank.
     */
    fun isTerm(word: String): Boolean {
        val letters = word.count { it.isLetter() }
        if (letters < 5 || letters != word.count { it.isLetter() || it == '-' }) return false
        val lower = word.lowercase()
        if (lower.endsWith("ing") || lower.endsWith("ed")) return false
        return lower !in stopwords
    }

    private fun isPunctuation(c: Char): Boolean {
        if (c == '-') return false
        return when (Character.getType(c).toByte()) {
            Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
            Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
            Character.OTHER_PUNCTUATION -> true
            else -> false
        }
    }

    /** The words of a sentence, punctuation trimmed. */
    fun words(sentence: String): List<String> =
        sentence.split(' ', '/').map { it.trim(::isPunctuation) }.filter { it.isNotEmpty() }

    /** How often each term appears across the text, by lower-case form; the key is the first spelling met. */
    fun termFrequencies(sentences: List<String>): Map<String, Int> {
        val counts = LinkedHashMap<String, Int>()
        val spelling = HashMap<String, String>()
        for (s in sentences) for (w in words(s)) {
            if (!isTerm(w)) continue
            val key = w.lowercase()
            counts[key] = (counts[key] ?: 0) + 1
            if (key !in spelling) spelling[key] = w
        }
        val out = LinkedHashMap<String, Int>()
        for ((key, n) in counts) out[spelling[key] ?: key] = n
        return out
    }

    /** The sentence's telling terms, best first: ones the text keeps coming back to, longer ones first. */
    fun keyTerms(sentence: String, frequencies: Map<String, Int>): List<Pair<String, Int>> {
        val lower = HashMap<String, Pair<String, Int>>()
        for ((k, v) in frequencies) lower[k.lowercase()] = k to v
        val out = mutableListOf<Pair<String, Int>>()
        val seen = HashSet<String>()
        for ((position, w) in words(sentence).withIndex()) {
            if (!isTerm(w)) continue
            val (term, n) = lower[w.lowercase()] ?: continue
            if (n < 2 || !seen.add(term.lowercase())) continue
            // the sentence's own first word is usually its subject, and
            // blanking it leaves a stem with no footing
            val score = n * 10 + w.length - (if (position == 0) 15 else 0)
            out.add(term to score)
        }
        return out.sortedWith(Comparator { a, b -> if (a.second != b.second) b.second - a.second else a.first.compareTo(b.first) })
    }

    /** Four other key terms, nearest in length, none already in the sentence. */
    fun distractors(term: String, sentence: String, pool: List<String>): List<String> {
        val inSentence = words(sentence).map { it.lowercase() }.toSet()
        val capital = term.firstOrNull()?.isUpperCase() ?: false
        val ending = term.lowercase().takeLast(2)
        val others = pool.filter { it.lowercase() != term.lowercase() && it.lowercase() !in inSentence }
        // same ending (adjectives with adjectives: femoral, inguinal), then
        // same capitalisation (names with names), then length
        val ranked = others.sortedWith(Comparator { a, b ->
            val ea = a.lowercase().takeLast(2) == ending
            val eb = b.lowercase().takeLast(2) == ending
            if (ea != eb) return@Comparator if (ea) -1 else 1
            val ca = (a.firstOrNull()?.isUpperCase() ?: false) == capital
            val cb = (b.firstOrNull()?.isUpperCase() ?: false) == capital
            if (ca != cb) return@Comparator if (ca) -1 else 1
            val da = kotlin.math.abs(a.length - term.length)
            val db = kotlin.math.abs(b.length - term.length)
            if (da != db) return@Comparator da - db
            a.compareTo(b)
        })
        val out = mutableListOf<String>()
        val seen = HashSet<String>()
        for (t in ranked) {
            if (!seen.add(t.lowercase())) continue
            out.add(t)
            if (out.size == optionCount - 1) break
        }
        return out
    }

    /**
     * The sentence with the term replaced by a blank, every time it appears,
     * whole words only: "renal" is not blanked inside "adrenal".
     */
    fun blanked(term: String, sentence: String): String {
        if (term.isEmpty()) return sentence
        val out = StringBuilder()
        var from = 0
        while (true) {
            val start = sentence.indexOf(term, from, ignoreCase = true)
            if (start < 0) break
            val end = start + term.length
            val before = if (start > 0) sentence[start - 1] else null
            val after = if (end < sentence.length) sentence[end] else null
            out.append(sentence, from, start)
            if (before?.isLetter() == true || after?.isLetter() == true) out.append(sentence, start, end)
            else out.append("_____")
            from = end
        }
        out.append(sentence, from, sentence.length)
        return out.toString()
    }

    /** A small seeded generator (SplitMix64), so a set's pretest is the same each time. */
    class Mixer(var state: ULong) : MockRandom {
        override fun next(): ULong {
            state += 0x9E3779B97F4A7C15uL
            var z = state
            z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
            z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
            return z xor (z shr 31)
        }
    }
}
