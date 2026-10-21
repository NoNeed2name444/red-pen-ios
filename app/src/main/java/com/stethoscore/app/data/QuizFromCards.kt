package com.stethoscore.app.data

/**
 * Turns a deck you already have into a quiz, using the deck as the
 * distractors (iOS QuizFromCards): a question built from card 14 tests card
 * 14, and its wrong answers are the right answers to other cards in the same
 * deck. Nothing is invented. A port of pipeline/tools/quiz_from_cards.py.
 */
object QuizFromCards {

    data class Skipped(val cardId: String, val why: String)

    data class Built(val questions: List<MCQQuestion>, val skipped: List<Skipped>)

    /** Two answers this alike cannot both be on one question. */
    const val tooAlike = 0.8
    /** Tells that make a question answerable without the medicine. */
    val fatal: Set<String> = setOf(
        "key-is-longest", "only-key-hedges", "stem-word-only-in-key",
        "absolute-in-key", "duplicate-option", "non-answer-option",
        "stem-not-a-question", "stem-too-thin", "option-count", "no-key")

    /** The single thing a card asks you to produce, or null if it asks for more than one. */
    fun answer(card: AnkiCard): String? {
        if (card.type == AnkiCardType.CLOZE) {
            // the first deletion is the card's subject; later ones are detail
            return CardQuality.clozeHoles(card.clozeText).firstOrNull()?.text?.trimSpaces()
        }
        val bullets = card.bullets.map { it.trimSpaces() }.filter { it.isNotEmpty() }
        return if (bullets.size == 1) bullets[0] else null
    }

    fun stem(card: AnkiCard): String {
        if (card.type == AnkiCardType.CLOZE) {
            val holes = CardQuality.clozeHoles(card.clozeText)
            val first = holes.firstOrNull() ?: return ""
            // every hole with the first one's number is blanked, as Anki hides a repeated c1 together
            val text = StringBuilder(card.clozeText)
            for (hole in holes.filter { it.number == first.number }.reversed()) {
                text.replace(hole.range.first, hole.range.last + 1, "______")
            }
            return CardQuality.clozeBare(text.toString()).trimSpaces()
        }
        return card.front.trimSpaces()
    }

    /** The card's reasoning, with the thing it reasons about named. */
    fun explanation(answer: String, why: String): String {
        val reason = why.trim()
        if (reason.isEmpty()) return answer
        if (CardQuality.terms(answer).intersect(CardQuality.terms(reason)).isNotEmpty()) return reason
        return answer + " — " + lowercasingFirstWord(reason)
    }

    /** "Lowers flares" reads "lowers flares" after a dash; "ACE", "CT" and "Addison disease" keep their capitals. */
    fun lowercasingFirstWord(text: String): String {
        val first = text.firstOrNull() ?: return text
        if (!first.isUpperCase()) return text
        val firstWord = text.takeWhile { it.isLetter() }
        if (firstWord == "A") return "a" + text.drop(1)
        if (firstWord.length <= 1) return text
        if (!firstWord[1].isLowerCase()) return text
        val rest = text.drop(firstWord.length)
        if (rest.startsWith("'s") || rest.startsWith("’s")) return text
        val next = rest.dropWhile { it == ' ' || it == '-' }.takeWhile { it.isLetter() }.lowercase()
        val named = setOf("disease", "syndrome", "sign", "triad", "test", "reflex", "phenomenon",
            "criteria", "score", "classification", "law", "node", "palsy", "ulcer",
            "fracture", "tumour", "tumor", "manoeuvre", "maneuver", "lesion")
        if (next in named) return text
        return first.lowercase() + text.drop(1)
    }

    /** Other cards' answers, nearest first, minus any that could also be right. */
    fun distractors(answer: String, stem: String, pool: List<String>, want: Int): List<String> {
        val stemWords = CardQuality.terms(stem)
        val answerWords = CardQuality.terms(answer)
        val value = isValue(answer)
        data class Ranked(val shape: Boolean, val shared: Int, val inStem: Int, val alike: Double, val text: String)
        val ranked = pool
            .filter { it.isNotEmpty() && it.lowercase() != answer.lowercase() }
            .filter { CardQuality.similarity(answer, it) < tooAlike }
            .map { other ->
                val terms = CardQuality.terms(other)
                Ranked(isValue(other) == value, answerWords.intersect(terms).size, stemWords.intersect(terms).size,
                    CardQuality.similarity(answer, other), other)
            }
            .sortedWith { a, b ->
                when {
                    a.shape != b.shape -> if (a.shape) -1 else 1
                    a.shared != b.shared -> b.shared - a.shared
                    a.inStem != b.inStem -> b.inStem - a.inStem
                    else -> b.alike.compareTo(a.alike)
                }
            }
        val chosen = mutableListOf<String>()
        val seen = mutableSetOf<String>()
        for (candidate in ranked) {
            val other = candidate.text
            if (other.lowercase() in seen) continue
            // never two distractors that are near-twins of each other either
            if (chosen.any { CardQuality.similarity(other, it) >= tooAlike }) continue
            chosen += other
            seen += other.lowercase()
            if (chosen.size == want) break
        }
        return chosen
    }

    /** An answer that is a value - "140 mmol/L", "3.5", "> 10 points". */
    fun isValue(text: String): Boolean {
        val lead = text.dropWhile { it.isWhitespace() || it in "<>≤≥~≈" }
        return lead.firstOrNull()?.let { isNumberChar(it) } == true
    }

    /** The key is the one value among terms, or the one term among values. */
    fun keyStandsOut(answer: String, distractors: List<String>): Boolean {
        val value = isValue(answer)
        return distractors.isNotEmpty() && distractors.all { isValue(it) != value }
    }

    /** Build the quiz from the deck alone. */
    fun build(cards: List<AnkiCard>, optionCount: Int = 5, seed: ULong = 0uL): Built =
        build(cards, emptyList(), optionCount, seed)

    /** The same, with the wrong answers drawn from a wider deck than the cards being asked about. */
    fun build(cards: List<AnkiCard>, distractorsFrom: List<AnkiCard>, optionCount: Int = 5, seed: ULong = 0uL): Built {
        val rng = SplitMixShuffle(if (seed == 0uL) 0x9E3779B97F4A7C15uL else seed)
        val answers = cards.map { answer(it) }
        val asking = cards.map { it.id }.toSet()
        val wider = distractorsFrom.filter { it.id !in asking }.mapNotNull { answer(it) }
        val pool = answers.filterNotNull() + wider
        val questions = mutableListOf<MCQQuestion>()
        val skipped = mutableListOf<Skipped>()
        for ((card, answerText) in cards.zip(answers)) {
            if (answerText.isNullOrEmpty()) { skipped += Skipped(card.id, "no single answer to ask for"); continue }
            val stemText = stem(card)
            if (stemText.split(" ").count { it.isNotEmpty() } < 3) { skipped += Skipped(card.id, "nothing to make a stem from"); continue }
            val wrong = distractors(answerText, stemText, pool, optionCount - 1)
            if (wrong.size != optionCount - 1) {
                skipped += Skipped(card.id, "only ${wrong.size} usable distractors in this deck"); continue
            }
            if (keyStandsOut(answerText, wrong)) {
                skipped += Skipped(card.id, if (isValue(answerText)) "the only answer that is a number" else "the only answer that is not a number")
                continue
            }
            val choices = rng.shuffled(wrong + answerText)
            val questionStem = if (stemText.endsWith("?") || stemText.contains("______")) stemText else stemText.trim('.') + "?"
            val question = MCQQuestion(stem = questionStem, options = choices,
                correctIndex = choices.indexOf(answerText).coerceAtLeast(0),
                explanation = explanation(answerText, card.why), imageIndex = null)
            val tells = CardQuality.check(question).map { it.rule }.toSet().intersect(fatal)
            if (tells.isNotEmpty()) {
                skipped += Skipped(card.id, "gives itself away (${tells.sorted().joinToString(", ")})"); continue
            }
            questions += question
        }
        return Built(questions, skipped)
    }
}

/** Swift's Character.isNumber: digits, and numerals such as ½ or Ⅻ. */
internal fun isNumberChar(c: Char): Boolean = when (Character.getType(c).toByte()) {
    Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
    else -> false
}

/**
 * What makes a generated card or question bad, found before you memorise it
 * (iOS CardQuality, a port of pipeline/tools/card_quality.py). Reports only.
 */
object CardQuality {

    data class Problem(val itemId: String?, val rule: String, val detail: String)

    val absolutes = listOf("always", "never", "all patients", "every patient", "exclusively")
    val hedges = listOf("may", "can", "sometimes", "often", "usually", "generally", "typically")
    val nonAnswers = listOf("all of the above", "none of the above", "both a and b", "a and b", "all of these", "none of these")
    val stopwords: Set<String> = setOf(
        "the", "a", "an", "of", "in", "is", "are", "to", "and", "or", "with", "for",
        "by", "on", "at", "as", "that", "this", "it", "be", "which", "what", "most",
        "best", "following", "patient", "next", "step")

    /** Content words only. */
    fun terms(text: String): Set<String> =
        text.lowercase().split(Regex("[^\\p{L}]+")).filter { it.length >= 4 && it !in stopwords }.toSet()

    private fun words(text: String): Int = text.split(" ").count { it.isNotEmpty() }

    fun check(q: MCQQuestion): List<Problem> {
        val out = mutableListOf<Problem>()
        fun flag(rule: String, detail: String) { out += Problem(q.id, rule, detail) }
        val stem = q.stem.trim()
        val options = q.options.map { it.trim() }
        if (options.size !in 4..5) flag("option-count", "${options.size} options, expected 4 or 5")
        if (q.correctIndex !in options.indices) {
            flag("no-key", "correctIndex ${q.correctIndex}")
            return out
        }
        val key = options[q.correctIndex]
        val others = options.filterIndexed { i, _ -> i != q.correctIndex }
        if (options.map { it.lowercase() }.toSet().size != options.size) flag("duplicate-option", "two options say the same thing")
        for (o in options) if (o.lowercase() in nonAnswers) flag("non-answer-option", o)
        if (!stem.endsWith("?") && !stem.contains("______") && stem.length <= 60) flag("stem-not-a-question", stem.take(80))
        if (words(stem) < 6) flag("stem-too-thin", "${words(stem)} words")
        val longest = others.maxOfOrNull { it.length }
        if (longest != null && key.length > 40 && key.length.toDouble() > 1.6 * longest) {
            flag("key-is-longest", "key ${key.length} chars, longest distractor $longest")
        }
        val keyHedges = hedges.any { key.lowercase().contains(it) }
        val othersHedge = others.any { o -> hedges.any { o.lowercase().contains(it) } }
        if (keyHedges && !othersHedge) flag("only-key-hedges", key.take(80))
        if (absolutes.any { key.lowercase().contains(it) }) flag("absolute-in-key", key.take(80))
        val elsewhere = others.flatMap { terms(it) }.toSet()
        val giveaway = terms(stem).intersect(terms(key)) - elsewhere
        if (giveaway.isNotEmpty()) flag("stem-word-only-in-key", giveaway.sorted().joinToString(", "))
        val why = q.explanation.trim()
        if (why.isEmpty()) flag("no-explanation", "")
        else if (terms(key).intersect(terms(why)).isEmpty()) flag("explanation-misses-the-key", why.take(80))
        return out
    }

    fun check(card: AnkiCard): List<Problem> {
        val out = mutableListOf<Problem>()
        fun flag(rule: String, detail: String) { out += Problem(card.id, rule, detail) }
        if (card.type == AnkiCardType.CLOZE) {
            val holes = clozeHoles(card.clozeText)
            if (holes.isEmpty()) { flag("cloze-without-a-deletion", card.clozeText.take(80)); return out }
            val deleted = holes.sumOf { it.text.length }
            val bare = clozeBare(card.clozeText)
            if (bare.isNotEmpty() && deleted.toDouble() > 0.5 * bare.length) flag("cloze-swallows-the-sentence", "$deleted of ${bare.length} characters deleted")
            val numbers = holes.map { it.number }.toSet().size
            if (numbers > 3) flag("too-many-deletions", "$numbers separate deletions")
            for (hole in holes) if (words(hole.text) > 6) flag("deletion-is-a-clause", hole.text.take(60))
            return out
        }
        val front = card.front.trim()
        val bullets = card.bullets.filter { it.trimSpaces().isNotEmpty() }
        if (card.type == AnkiCardType.OCCLUSION) {
            if (card.imageIndex == null) flag("occlusion-without-an-image", front)
            if (card.occlusion == null) flag("occlusion-without-a-box", front)
            return out
        }
        if (front.isEmpty()) flag("no-front", "") else if (words(front) < 3) flag("front-too-thin", front)
        if (bullets.size > 4) flag("too-many-facts", "${bullets.size} bullets")
        for (b in bullets) if (words(b) > 30) flag("bullet-is-a-paragraph", b.take(60))
        if (front.isNotEmpty() && bullets.isNotEmpty()) {
            val back = bullets.joinToString(" ").lowercase()
            if (back.contains(front.lowercase().replace("?", ""))) flag("front-appears-on-the-back", front.take(60))
        }
        if (bullets.isEmpty()) flag("no-answer", front.take(60))
        return out
    }

    data class Hole(val number: Int, val text: String, val range: IntRange)

    private val holePattern = Regex("""\{\{c(\d+)::(.+?)(?:::.*?)?\}\}""")
    private val barePattern = Regex("""\{\{c\d+::(.+?)(?:::.*?)?\}\}""")

    fun clozeHoles(text: String): List<Hole> = holePattern.findAll(text).map {
        Hole(it.groupValues[1].toIntOrNull() ?: 1, it.groupValues[2], it.range)
    }.toList()

    /** The sentence with the braces removed but the words kept. */
    fun clozeBare(text: String): String = barePattern.replace(text) { it.groupValues[1] }

    /** Pairs asking the same thing in different words. */
    fun duplicates(items: List<Pair<String, String>>, threshold: Double = 0.86): List<Problem> {
        val out = mutableListOf<Problem>()
        for (i in items.indices) for (j in i + 1 until items.size) {
            val a = items[i].second.lowercase(); val b = items[j].second.lowercase()
            if (a.isEmpty() || b.isEmpty()) continue
            val score = similarity(a, b)
            if (score >= threshold) out += Problem(items[i].first, "near-duplicate", String.format(java.util.Locale.ROOT, "%.2f like another", score))
        }
        return out
    }

    /** Token-level overlap, case, hyphens and a plural "s" aside. */
    fun similarity(a: String, b: String): Double {
        val x = similarityTokens(a); val y = similarityTokens(b)
        if (x.isEmpty() || y.isEmpty()) return 0.0
        return x.intersect(y).size.toDouble() / maxOf(x.size, y.size)
    }

    /** Lower-cased words and numbers ("3.5" is one number), a plural "s" off a longer word. */
    fun similarityTokens(text: String): Set<String> {
        val out = mutableSetOf<String>()
        val word = StringBuilder()
        val number = StringBuilder()
        fun flush() {
            if (word.isNotEmpty()) { out += singular(word.toString()); word.clear() }
            if (number.isNotEmpty()) {
                // a trailing point is punctuation, not a decimal
                while (number.endsWith(".")) number.setLength(number.length - 1)
                if (number.isNotEmpty()) out += number.toString()
                number.clear()
            }
        }
        for (ch in text.lowercase()) {
            if (isNumberChar(ch)) {
                if (word.isNotEmpty()) flush()
                number.append(ch)
            } else if (ch == '.' && number.isNotEmpty() && !number.contains('.')) {
                number.append(ch)
            } else if (ch.isLetter()) {
                if (number.isNotEmpty()) flush()
                word.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    private fun singular(word: String): String {
        if (word.length <= 3 || !word.endsWith("s")) return word
        for (kept in listOf("ss", "us", "is")) if (word.endsWith(kept)) return word
        return word.dropLast(1)
    }

    fun review(questions: List<MCQQuestion> = emptyList(), cards: List<AnkiCard> = emptyList()): List<Problem> {
        val out = mutableListOf<Problem>()
        questions.forEach { out += check(it) }
        cards.forEach { out += check(it) }
        out += duplicates(questions.map { it.id to it.stem })
        out += duplicates(cards.map { it.id to (if (it.type == AnkiCardType.CLOZE) it.clozeText else it.front) })
        return out
    }
}
