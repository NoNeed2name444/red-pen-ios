package com.stethoscore.app.data

/**
 * Plain-text import for a quick hand-authored or scripted set (iOS
 * PlainTextImport). One line per question:
 *   Stem | OptionA; OptionB; OptionC; OptionD | correctLetter | Explanation
 * or, for cards:
 *   Front | bullet1; bullet2 | why (optional)
 * and tables of cards from Quizlet, Brainscape, Sheets, Excel or Anki's text
 * export, with the separator worked out from the text itself.
 */
object PlainTextImport {

    /** The text's lines, whichever line endings it was written with. */
    fun lines(text: String, keepingEmpty: Boolean = false): List<String> {
        val unix = text.replace("\r\n", "\n").replace("\r", "\n")
        val parts = unix.split("\n")
        if (keepingEmpty) return parts
        return parts.filter { it.isNotEmpty() }
    }

    /** The option a letter names: A is 0, B is 1. Null for anything not a letter from A to Z. */
    fun optionIndex(field: String): Int? {
        val first = field.trimSpaces().firstOrNull() ?: return null
        if (!first.isLetter() || first.code > 127) return null
        // lower-cased by its bit, so "b" and "B" are both 1
        return (first.code or 0x20) - 97
    }

    fun parseMCQ(text: String): List<MCQQuestion> = lines(text).mapNotNull { rawLine ->
        val line = rawLine.trimSpaces()
        if (line.isEmpty()) return@mapNotNull null
        val parts = line.split("|").map { it.trimSpaces() }
        if (parts.size < 3) return@mapNotNull null
        val options = parts[1].split(";").map { it.trimSpaces() }.filter { it.isNotEmpty() }
        val correctIndex = optionIndex(parts[2]) ?: return@mapNotNull null
        val explanation = if (parts.size >= 4) parts[3] else ""
        if (options.isEmpty() || correctIndex >= options.size) return@mapNotNull null
        MCQQuestion(stem = parts[0], options = options, correctIndex = correctIndex, explanation = explanation)
    }

    /** OSCE: stations, each a "## Title" line followed by one step per line. */
    fun parseOsce(text: String): List<OsceChecklist> {
        val checklists = mutableListOf<OsceChecklist>()
        var title = ""
        val steps = mutableListOf<String>()
        fun flush() {
            val t = title.trimSpaces()
            val s = steps.map { it.trimSpaces() }.filter { it.isNotEmpty() }
            if (t.isNotEmpty() && s.isNotEmpty()) checklists += OsceChecklist(title = t, steps = s)
            steps.clear()
        }
        for (line in lines(text, keepingEmpty = true)) {
            val trimmed = line.trimSpaces()
            if (trimmed.startsWith("##")) {
                flush()
                title = trimmed.trim('#').trimSpaces()
            } else if (trimmed.isNotEmpty()) {
                steps += line
            }
        }
        flush()
        return checklists
    }

    /** Narrate: one line per segment, "en|Text" or "ar|النص"; the tag defaults to "en". */
    fun parseNarrate(text: String): List<NarrateSegment> = lines(text).mapNotNull { rawLine ->
        val line = rawLine.trimSpaces()
        if (line.isEmpty()) return@mapNotNull null
        val parts = line.split("|")
        val lang = parts[0].trimSpaces().lowercase()
        if (parts.size >= 2 && lang in listOf("en", "ar")) {
            val body = parts.drop(1).joinToString("|").trimSpaces()
            if (body.isEmpty()) return@mapNotNull null
            return@mapNotNull NarrateSegment(text = body, lang = lang)
        }
        NarrateSegment(text = line, lang = "en")
    }

    fun parseAnkiQA(text: String): List<AnkiCard> = lines(text).mapNotNull { rawLine ->
        val line = rawLine.trimSpaces()
        if (line.isEmpty()) return@mapNotNull null
        val parts = line.split("|").map { it.trimSpaces() }
        // a cloze line: the sentence with its hidden part as {{c1::...}}, then why
        if (parts[0].contains("{{c") && parts[0].contains("::") && parts[0].contains("}}")) {
            return@mapNotNull AnkiCard(type = AnkiCardType.CLOZE, clozeText = parts[0], why = if (parts.size >= 2) parts[1] else "")
        }
        if (parts.size < 2) return@mapNotNull null
        val bullets = parts[1].split(";").map { it.trimSpaces() }.filter { it.isNotEmpty() }
        val why = if (parts.size >= 3) parts[2] else ""
        if (bullets.isEmpty()) return@mapNotNull null
        AnkiCard(type = AnkiCardType.QA, front = parts[0], bullets = bullets, why = why)
    }

    // spreadsheets: Quizlet, Brainscape, Google Sheets, Excel, Anki's text export

    data class Table(val rows: List<List<String>>, val separator: Char, val header: List<String>?, val tagsColumn: Int?)

    /** The header lines Anki writes at the top of a text export. */
    val ankiHeaderKeys: Set<String> = setOf("separator", "html", "tags column", "columns", "notetype",
        "deck", "notetype column", "deck column", "guid column", "if matches")

    /** The separators tried, most specific first. */
    val separators: List<Char> = listOf('\t', ';', ',', '|')

    /** Whether some text is a table rather than the pipe-separated line format. */
    fun looksDelimited(text: String): Boolean {
        val sample = lines(text).take(40).filter { !it.startsWith("#") }
        if (sample.isEmpty()) return false
        if (text.startsWith("#separator:")) return true
        val tabbed = sample.count { it.contains("\t") }
        if (tabbed * 2 >= sample.size) return true
        if (sample.any { it.contains("|") }) return false
        val table = table(text) ?: return false
        return table.separator != '|' && table.rows.any { it.size >= 2 }
    }

    /** The text as rows and cells, with its separator and header found. */
    fun table(text: String): Table? {
        val body = text.removePrefix("﻿")
        var declared: Char? = null
        var tagsColumn: Int? = null
        var headerNames: List<String>? = null
        val kept = mutableListOf<String>()
        var inHeader = true
        for (line in lines(body, keepingEmpty = true)) {
            val colon = line.indexOf(':')
            if (inHeader && line.startsWith("#") && colon > 0 && line.substring(1, colon).lowercase() in ankiHeaderKeys) {
                val key = line.substring(1, colon).lowercase()
                val value = line.substring(colon + 1).trimSpaces()
                when (key) {
                    "separator" -> declared = separatorNamed(value)
                    "tags column" -> tagsColumn = value.toIntOrNull()?.let { it - 1 }
                    "columns" -> headerNames = value.split('\t', ',', ';', '|')
                }
                continue
            }
            inHeader = false
            kept += line
        }
        val joined = kept.joinToString("\n")
        if (joined.isBlank()) return null
        val separator = declared ?: detectSeparator(joined)
        val rows = cells(joined, separator)
            .map { row -> row.map { it.trimSpaces() } }
            .filter { row -> row.any { it.isNotEmpty() } }
            .toMutableList()
        if (rows.isEmpty()) return null
        var header: List<String>? = headerNames
        if (header == null && rows.size > 1 && isHeader(rows.first())) {
            header = rows.removeAt(0)
        }
        if (tagsColumn == null && header != null) {
            tagsColumn = header.indexOfFirst { normalized(it) in listOf("tags", "tag", "labels") }.takeIf { it >= 0 }
        }
        return Table(rows, separator, header, tagsColumn)
    }

    fun separatorNamed(value: String): Char? = when (value.lowercase()) {
        "tab", "\t" -> '\t'
        "comma", "," -> ','
        "semicolon", ";" -> ';'
        "pipe", "|" -> '|'
        "colon", ":" -> ':'
        "space", " " -> ' '
        else -> if (value.length == 1) value[0] else null
    }

    /** The separator that splits the most lines into the same number of cells; ties to the earlier. */
    fun detectSeparator(text: String): Char {
        var best = '\t'
        var bestScore = -1
        for (candidate in separators) {
            val rows = cells(text, candidate, 30)
            val counts = rows.map { it.size }.filter { it >= 2 }
            if (counts.isEmpty()) continue
            val common = counts.groupingBy { it }.eachCount().values.maxOrNull() ?: 0
            val score = common * 4 - (rows.size - common)
            if (score > bestScore) { best = candidate; bestScore = score }
        }
        return best
    }

    /** RFC 4180 cells: a quoted cell may hold the separator, line breaks, and "" for a quote. */
    fun cells(text: String, separator: Char, limit: Int = Int.MAX_VALUE): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val cell = StringBuilder()
        var quoted = false
        var atCellStart = true
        var i = 0
        while (i < text.length) {
            val c = text[i]
            i++
            if (quoted) {
                if (c == '"') {
                    if (i < text.length && text[i] == '"') { cell.append('"'); i++ } else quoted = false
                } else {
                    cell.append(c)
                }
                continue
            }
            if (c == '"' && atCellStart) { quoted = true; atCellStart = false; continue }
            if (c == separator) { row += cell.toString(); cell.clear(); atCellStart = true; continue }
            if (c == '\n' || c == '\r') {
                // "\r\n" is one line break, as Swift reads it as one Character
                if (c == '\r' && i < text.length && text[i] == '\n') i++
                row += cell.toString()
                rows += row
                if (rows.size >= limit) return rows
                row = mutableListOf(); cell.clear(); atCellStart = true
                continue
            }
            if (!(atCellStart && c == ' ')) atCellStart = false
            cell.append(c)
        }
        if (cell.isNotEmpty() || row.isNotEmpty()) { row += cell.toString(); rows += row }
        return rows
    }

    private val headerWords: Set<String> = setOf(
        "front", "back", "term", "definition", "question", "answer", "tags", "tag", "extra", "why",
        "explanation", "notes", "note", "stem", "correct", "key", "options", "choices", "prompt",
        "word", "meaning", "back extra", "text", "a", "b", "c", "d", "e", "option a", "option b",
        "choice a", "choice b", "correct answer", "subject", "topic", "source", "hint")

    fun normalized(cell: String): String = cell.trimSpaces().lowercase().replace("_", " ").trim(':', '#', '*')

    /** A first row that names columns: every cell short, and at least one a column name people use. */
    fun isHeader(row: List<String>): Boolean {
        val names = row.map { normalized(it) }
        if (!names.all { it.length <= 24 }) return false
        return names.any { it in headerWords }
    }

    /** Which column is which, by header name where there is one. */
    class Columns(table: Table) {
        var front = 0
        var back = 1
        var why: Int? = null
        var tags: Int? = table.tagsColumn
        var question: Int? = null
        val options = mutableListOf<Int>()
        var answer: Int? = null
        var explanation: Int? = null

        init {
            val header = table.header?.map { normalized(it) }
            if (header != null) {
                fun find(names: List<String>): Int? = header.indexOfFirst { it in names }.takeIf { it >= 0 }
                front = find(listOf("front", "term", "question", "prompt", "word", "stem", "text")) ?: 0
                back = find(listOf("back", "definition", "answer", "meaning", "correct answer")) ?: (if (front == 0) 1 else 0)
                why = find(listOf("extra", "why", "explanation", "notes", "note", "back extra", "hint"))
                question = find(listOf("question", "stem", "prompt"))
                answer = find(listOf("correct", "correct answer", "key", "answer"))
                explanation = find(listOf("explanation", "why", "rationale", "notes"))
                val letters = listOf("a", "b", "c", "d", "e", "f")
                header.forEachIndexed { index, name ->
                    val bare = name.replace("option ", "").replace("choice ", "")
                    if (bare in letters || name.startsWith("option") || name.startsWith("choice")) {
                        if (name != "options" && name != "choices") options += index
                    }
                }
                if (options.isEmpty()) find(listOf("options", "choices"))?.let { options += it }
            }
        }
    }

    /** A cell as plain text: exported HTML's tags and entities undone. */
    fun cellText(cell: String): String {
        if (!cell.contains("<") && !cell.contains("&")) return cell
        var text = cell
        for (br in listOf("<br>", "<br/>", "<br />", "<BR>", "</div>", "</p>", "</li>")) text = text.replace(br, "\n")
        text = text.replace("<b>", "**").replace("</b>", "**")
        text = text.replace(Regex("<[^>]+>"), "")
        for ((entity, plain) in listOf("&nbsp;" to " ", "&lt;" to "<", "&gt;" to ">", "&quot;" to "\"", "&#39;" to "'", "&amp;" to "&")) {
            text = text.replace(entity, plain)
        }
        return text.split("\n").map { it.trimSpaces() }.filter { it.isNotEmpty() }.joinToString("\n")
    }

    fun tagList(cell: String): List<String> {
        val pieces = if (cell.contains(",")) cell.split(",") else cell.split(' ', '\t')
        return pieces.map { it.trimSpaces() }.filter { it.isNotEmpty() }.take(20)
    }

    /** Flashcards from a table: front and back (a `{{c1::...}}` front makes a cloze), the why, the tags. */
    fun delimitedCards(text: String): List<AnkiCard> {
        val table = table(text) ?: return emptyList()
        val columns = Columns(table)
        return table.rows.mapNotNull { row ->
            fun cell(index: Int?): String = if (index != null && index in row.indices) cellText(row[index]) else ""
            val front = cell(columns.front)
            val back = cell(columns.back)
            val why = if (columns.why == columns.back) "" else cell(columns.why)
            var card = if (front.contains("{{c") && front.contains("::") && front.contains("}}")) {
                AnkiCard(type = AnkiCardType.CLOZE, clozeText = front, why = listOf(back, why).filter { it.isNotEmpty() }.joinToString("\n"))
            } else {
                val bullets = back.split("\n").filter { it.isNotEmpty() }
                if (front.isEmpty() || bullets.isEmpty()) return@mapNotNull null
                AnkiCard(type = AnkiCardType.QA, front = front, bullets = bullets, why = why)
            }
            columns.tags?.let { if (it in row.indices) card = card.copy(tags = tagList(row[it])) }
            card
        }
    }

    /** Questions from a table with a question column, option columns and the correct answer. */
    fun delimitedQuestions(text: String): List<MCQQuestion> {
        val table = table(text) ?: return emptyList()
        val columns = Columns(table)
        val stemColumn = columns.question ?: (if (table.header == null) 0 else null) ?: return emptyList()
        return table.rows.mapNotNull { row ->
            fun cell(index: Int?): String = if (index != null && index in row.indices) cellText(row[index]) else ""
            val stem = cell(stemColumn)
            var answerColumn = columns.answer
            val options: List<String>
            if (columns.options.size > 1) {
                options = columns.options.map { cell(it) }.filter { it.isNotEmpty() }
            } else if (columns.options.size == 1) {
                options = cell(columns.options[0]).split(';', '|', '\n').map { it.trimSpaces() }.filter { it.isNotEmpty() }
            } else {
                // no header: stem, options..., answer letter, explanation
                if (table.header != null || row.size < 4) return@mapNotNull null
                val letterAt = row.indices.drop(2).firstOrNull { index ->
                    val value = row[index].trimSpaces()
                    value.length == 1 && optionIndex(value) != null
                } ?: return@mapNotNull null
                options = row.subList(1, letterAt).map { cellText(it) }.filter { it.isNotEmpty() }
                answerColumn = letterAt
            }
            if (stem.isEmpty() || options.size < 2) return@mapNotNull null
            val key = cell(answerColumn)
            var correct: Int? = null
            if (key.length == 1) optionIndex(key)?.let { if (it < options.size) correct = it }
            if (correct == null) key.toIntOrNull()?.let { if (it >= 1 && it <= options.size) correct = it - 1 }
            if (correct == null) correct = options.indexOfFirst { it.equals(key, ignoreCase = true) }.takeIf { it >= 0 }
            val right = correct ?: return@mapNotNull null
            var explanationColumn = columns.explanation
            if (table.header == null && answerColumn != null && answerColumn + 1 < row.size) explanationColumn = answerColumn + 1
            val tags = columns.tags?.let { if (it in row.indices) tagList(row[it]) else null } ?: emptyList()
            MCQQuestion(stem = stem, options = options, correctIndex = right, explanation = cell(explanationColumn), tags = tags)
        }
    }

    /** Cards from whatever was pasted: the line format when it is that, a table when it is one. */
    fun parseAnyCards(text: String): List<AnkiCard> {
        if (looksDelimited(text)) delimitedCards(text).let { if (it.isNotEmpty()) return it }
        return parseAnkiQA(text)
    }

    /** Whether a table opened from another app is a question sheet rather than front/back cards. */
    fun holdsQuestions(text: String): Boolean = looksDelimited(text) && delimitedQuestions(text).isNotEmpty()

    /** Questions from whatever was pasted, the same way. */
    fun parseAnyMCQ(text: String): List<MCQQuestion> {
        if (looksDelimited(text)) delimitedQuestions(text).let { if (it.isNotEmpty()) return it }
        return parseMCQ(text)
    }
}
