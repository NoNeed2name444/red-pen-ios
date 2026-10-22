package com.stethoscore.app.coverage

import com.stethoscore.app.data.StudySet
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.reading.BookPages

// A port of ios/RedPen/Shared/Coverage/CoverageEngine.swift: which
// parts of an exam's blueprint the student's library actually covers. Plain
// keyword matching over everything in the library, counted per subtopic, plus
// how the student did on the matching questions. Pure Kotlin.

/** How well the library covers one subtopic. */
@Suppress("EnumEntryName")
enum class CoverageStatus(val rawValue: String) {
    /** Plenty of material, some of it practice, and not answered badly. */
    covered("covered"),
    /** Something is there, but not much, only reading, or answered poorly. */
    thin("thin"),
    /** Nothing in the library mentions it. */
    notCovered("notCovered");

    val label: String get() = when (this) {
        covered -> "Covered"
        thin -> "Thin"
        notCovered -> "Not covered"
    }
}

/** What the engine found for one subtopic. */
data class SubtopicCoverage(
    val area: String,
    val subtopic: SyllabusSubtopic,
    /** Items that mention it: questions, cards, stations, pages. */
    val evidence: Int,
    /** Of those, the ones that test the student rather than being read. */
    val practice: Int,
    /** Answers given to the matching questions, and how many were right. */
    val answered: Int,
    val correct: Int,
    /** A few of the matching items, shortened. */
    val samples: List<String>,
    val status: CoverageStatus,
) {
    /** Stable across launches and exams: the area and the subtopic's name. */
    val id: String get() = CoverageEngine.key(area, subtopic.name)

    val accuracy: Double? get() = if (answered > 0) correct.toDouble() / answered else null
}

/** One area of the blueprint with its subtopics assessed. */
data class AreaCoverage(val area: SyllabusArea, val subtopics: List<SubtopicCoverage>) {
    val id: String get() = area.name

    fun count(status: CoverageStatus): Int = subtopics.count { it.status == status }
}

object CoverageEngine {

    /** At least this many items, and this many of them practice, to count as covered. */
    const val coveredEvidence = 5
    const val coveredPractice = 3
    /** Answered at least this many times at below this accuracy is thin, however much material there is. */
    const val weakAnswers = 5
    const val weakAccuracy = 0.6

    fun key(area: String, subtopic: String): String = "$area/$subtopic"

    /** One piece of the library, reduced to its words. */
    data class Item(
        /** Canonical words, each also without a trailing "s". */
        val words: Set<String>,
        /** The canonical words in order, space-padded, for phrase matching. */
        val phraseText: String,
        val isPractice: Boolean,
        /** The question this is, when it is one, for the answer history. */
        val questionId: String?,
        /** A short version, to show what the item is. */
        val preview: String,
    )

    // The whole assessment

    fun assess(library: List<StudySet>, history: Map<String, List<Boolean>>, areas: List<SyllabusArea>): List<AreaCoverage> =
        assessItems(items(library), history, areas)

    fun assessItems(items: List<Item>, history: Map<String, List<Boolean>>, areas: List<SyllabusArea>): List<AreaCoverage> =
        areas.map { area -> AreaCoverage(area, area.subtopics.map { assess(it, area.name, items, history) }) }

    fun assess(sub: SyllabusSubtopic, area: String, items: List<Item>, history: Map<String, List<Boolean>>): SubtopicCoverage {
        val keys = sub.keywords.map { Keyword(it) }
        var evidence = 0; var practice = 0; var answered = 0; var correct = 0
        val samples = ArrayList<String>()
        for (item in items) {
            if (keys.none { it.matches(item) }) continue
            evidence += 1
            if (item.isPractice) practice += 1
            val past = item.questionId?.let { history[it] }
            if (past != null) {
                answered += past.size
                correct += past.count { it }
            }
            // practice first in the samples: a question says more about what
            // is being studied than a page that mentions it in passing
            if (samples.size < 5 || (item.isPractice && samples.size < 8)) samples.add(item.preview)
        }
        return SubtopicCoverage(area, sub, evidence, practice, answered, correct, samples,
            status(evidence, practice, answered, correct))
    }

    /** The rule, on its own so it can be tested and explained. */
    fun status(evidence: Int, practice: Int, answered: Int, correct: Int): CoverageStatus {
        if (evidence <= 0) return CoverageStatus.notCovered
        if (answered >= weakAnswers && correct.toDouble() / answered < weakAccuracy) return CoverageStatus.thin
        if (evidence >= coveredEvidence && practice >= coveredPractice) return CoverageStatus.covered
        return CoverageStatus.thin
    }

    // The library as items

    /**
     * Everything in the library worth matching against, one item per question,
     * card, station, textbook page, stretch of transcript and lecture page. A
     * lecture kept by more than one set is read once.
     */
    fun items(library: List<StudySet>): List<Item> {
        val out = ArrayList<Item>()
        val seenSources = HashSet<String>()
        for (set in library) {
            out.add(item(set.name + " " + set.subject, practice = false))
            for (q in set.questions) {
                val answer = q.options.getOrNull(q.correctIndex) ?: ""
                out.add(item(q.stem + " " + answer, practice = true, question = q.id))
            }
            for (c in set.cards) {
                out.add(item(listOf(c.front, c.clozeText, c.bullets.joinToString(" ")).joinToString(" "), practice = true))
            }
            for (station in set.osceChecklists) {
                out.add(item(station.title + " " + station.steps.joinToString(" "), practice = true))
            }
            if (set.bookMarkdown.isNotEmpty()) {
                for (page in BookPages.split(set.bookMarkdown)) out.add(item(page.markdown, practice = false))
            }
            // a transcript a line at a time is too little to match; twenty
            // lines is about a minute of lecture
            val lines = set.narrateSegments.map { it.text }
            var start = 0
            while (start < lines.size) {
                val end = minOf(lines.size, start + 20)
                out.add(item(lines.subList(start, end).joinToString(" "), practice = false))
                start = end
            }
            for (source in set.sources) {
                if (!seenSources.add(source.id)) continue
                for (page in source.pages) out.add(item(page.text, practice = false))
            }
        }
        return out.filter { it.words.isNotEmpty() }
    }

    private val previewBreak = Regex("[ \\n\\r\\u000B\\u000C\\u0085\\u2028\\u2029]+")

    fun item(text: String, practice: Boolean, question: String? = null): Item {
        val tokens = canonicalWords(text)
        val words = LinkedHashSet<String>()
        for (w in tokens) {
            words.add(w)
            if (w.length > 3 && w.endsWith("s")) words.add(fold(w.dropLast(1)))
        }
        val preview = text.split(previewBreak).filter { it.isNotEmpty() }.joinToString(" ")
        return Item(words, " " + tokens.joinToString(" ") + " ", practice, question, preview.take(180))
    }

    // Words

    /** A keyword, split into canonical words once. */
    class Keyword(text: String) {
        val words: List<String> = canonicalWords(text)
        val phrase: String = words.joinToString(" ")

        fun matches(item: Item): Boolean {
            if (words.isEmpty() || !words.all { it in item.words }) return false
            if (words.size == 1) return true
            // every word is there; now check they are there together, in order
            return item.phraseText.contains(" $phrase ") || item.phraseText.contains(" ${phrase}s ")
        }
    }

    /**
     * Lowercase words with British and American spellings folded together:
     * "haemorrhage" and "hemorrhage", "tumour" and "tumor", "centre" and
     * "center" all come out the same. Short words are left alone.
     */
    fun canonicalWords(text: String): List<String> {
        val lower = text.lowercase()
        val out = ArrayList<String>()
        val current = StringBuilder()
        var i = 0
        while (i < lower.length) {
            val cp = lower.codePointAt(i)
            if (alphanumeric(cp)) current.appendCodePoint(cp)
            else if (current.isNotEmpty()) { out.add(fold(current.toString())); current.setLength(0) }
            i += Character.charCount(cp)
        }
        if (current.isNotEmpty()) out.add(fold(current.toString()))
        return out
    }

    /** Foundation's CharacterSet.alphanumerics: letters, marks and numbers of every script. */
    private fun alphanumeric(cp: Int): Boolean = when (Character.getType(cp).toByte()) {
        Character.UPPERCASE_LETTER, Character.LOWERCASE_LETTER, Character.TITLECASE_LETTER, Character.MODIFIER_LETTER,
        Character.OTHER_LETTER, Character.NON_SPACING_MARK, Character.ENCLOSING_MARK, Character.COMBINING_SPACING_MARK,
        Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
        else -> false
    }

    fun fold(word: String): String {
        if (word.length < 6) return word
        var w = word.replace("ae", "e").replace("oe", "e").replace("isation", "ization")
        if (w.endsWith("our")) w = w.dropLast(2) + "r"
        if (w.endsWith("ours")) w = w.dropLast(3) + "rs"
        if (w.endsWith("tre")) w = w.dropLast(3) + "ter"
        if (w.endsWith("tres")) w = w.dropLast(4) + "ters"
        return w
    }
}

/**
 * What a kept AI coverage check is filed under: the track, and the exam picked
 * under it, so a check run for NEET-PG is not the check for FMGE though both
 * sit under one track.
 */
object CoverageScope {
    fun key(track: ExamTrack, exam: String? = null): String {
        if (exam.isNullOrEmpty()) return track.rawValue
        val safe = exam.map { if (it.isLetterOrDigit()) it else '_' }.joinToString("")
        return track.rawValue + "-" + safe
    }
}
