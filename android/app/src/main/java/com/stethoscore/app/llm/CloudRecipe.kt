package com.stethoscore.app.llm

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.CaseWriting
import com.stethoscore.app.data.PlainTextImport
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudyJson
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.reading.BookFigures
import org.json.JSONArray
import org.json.JSONObject

/**
 * What a set written in the cloud needs to be finished without the screen
 * that asked for it: kept with the job ([CloudJobs.Pending.recipe]) in case
 * the app is closed before the server is done. Port of iOS CloudRecipe
 * (Shared/CloudJobCollector.swift), for every kind iOS finishes this way:
 * questions, stations, cards (with the image occlusion cards that go with
 * them), a textbook (with its figures) and cases.
 *
 * Not ported yet (T0115b): Provenance.attribute on a question set made from a
 * source (Android has only Provenance.label), and the evidence the server's
 * check cites (CloudChecks).
 */
data class CloudRecipe(
    val kind: StudySetKind,
    val name: String,
    val subject: String,
    val count: Int,
    val source: SourceDoc? = null,
    /** The exam it was written for (ExamCatalog id), for the set's badge. */
    val exam: String? = null,
    /** A textbook's figures (JPEG, base64), in the order the job's placement counts them. */
    val figures: List<String>? = null,
    /** Image occlusion cards that go with the written ones. */
    val diagramCards: List<AnkiCard>? = null,
    /** The pictures [diagramCards] sit on (JPEG, base64). */
    val diagramImages: List<String>? = null,
) {
    fun json(): String = JSONObject().put("kind", kind.rawValue).put("name", name).put("subject", subject).put("count", count)
        .put("source", source?.let(::encodeSource) ?: JSONObject.NULL).put("exam", exam ?: JSONObject.NULL)
        .put("figures", figures?.let { JSONArray(it) } ?: JSONObject.NULL)
        .put("diagramCards", diagramCards?.let(::encodeCards) ?: JSONObject.NULL)
        .put("diagramImages", diagramImages?.let { JSONArray(it) } ?: JSONObject.NULL)
        .toString()

    /**
     * The set, from the job's replies: the same parsing the screens use. Null
     * when the replies make no set, or for a kind the cloud does not write
     * (a narrated lecture): the collector keeps those replies as text.
     * [extra] is the job's own note ([CloudJobs.Pending.extra]): a textbook's
     * figure placement.
     */
    fun set(replies: List<String>, extra: String?): StudySet? {
        val title = name.trim()
        val set = StudySet(
            name = title.ifEmpty { "${subject.ifEmpty { "Generated" }} – ${kind.cloudNoun}" },
            subject = subject.ifEmpty { "General" }, kind = kind, exam = exam,
        )
        // replies that cannot be read make no set, never an error: the job is then kept as text
        val made: StudySet? = try { build(set, replies, extra) } catch (e: Exception) { null }
        return made?.copy(sources = listOfNotNull(source))
    }

    private fun build(set: StudySet, replies: List<String>, extra: String?): StudySet? = when (kind) {
        StudySetKind.MCQ ->
            MedicalGenerate.collectQuestions(replies, count).takeIf { it.isNotEmpty() }?.let { set.copy(questions = it) }
        StudySetKind.OSCE ->
            MedicalGenerate.collectStations(replies, count).takeIf { it.isNotEmpty() }?.let { set.copy(osceChecklists = it) }
        StudySetKind.ANKI -> {
            val lines = LectureWriter.collectLines(replies, StudySetKind.ANKI, count).joinToString("\n")
            val cards = PlainTextImport.parseAnkiQA(lines)
            val pictures = diagramCards
            val sheets = diagramImages
            when {
                cards.isEmpty() -> null
                // the diagram cards ride along with the written ones, on their pictures
                pictures != null && sheets != null && pictures.isNotEmpty() -> set.copy(cards = cards + pictures, images = sheets)
                else -> set.copy(cards = cards)
            }
        }
        StudySetKind.BOOK -> {
            val markdown = LectureWriter.assembleBook(replies, placement(extra))
            if (markdown.isEmpty()) null
            else {
                // only the pictures the pages actually show, renumbered to match
                val (pages, images) = BookFigures.compact(markdown, figures.orEmpty())
                set.copy(bookMarkdown = pages, images = images)
            }
        }
        StudySetKind.NARRATE -> null
        StudySetKind.CASES ->
            CaseWriting.collect(replies, count, source?.name.orEmpty()).takeIf { it.isNotEmpty() }?.let { set.copy(caseFiles = it) }
    }

    companion object {
        fun of(text: String?): CloudRecipe? {
            if (text == null) return null
            return runCatching {
                val o = JSONObject(text)
                CloudRecipe(
                    kind = StudySetKind.from(o.getString("kind")) ?: return null,
                    name = o.optString("name"), subject = o.optString("subject"), count = o.optInt("count"),
                    source = o.optJSONObject("source")?.let(::decodeSource), exam = o.opt("exam") as? String,
                    figures = o.optJSONArray("figures")?.let { LLMText.strings(it) },
                    diagramCards = o.optJSONArray("diagramCards")?.let(::decodeCards),
                    diagramImages = o.optJSONArray("diagramImages")?.let { LLMText.strings(it) },
                )
            }.getOrNull()
        }

        /** A textbook's figure placement ([CloudJobs.Pending.extra]): the figures of each page, by number; none when it cannot be read. */
        private fun placement(extra: String?): List<List<Int>> {
            if (extra == null) return emptyList()
            return try {
                val pages = JSONArray(extra)
                (0 until pages.length()).map { i ->
                    val figures = pages.optJSONArray(i)
                    if (figures == null) emptyList() else (0 until figures.length()).map { figures.getInt(it) }
                }
            } catch (e: Exception) {
                emptyList()
            }
        }

        // the cards are kept in the library's own form (StudyJson), so what is stored here reads as a set's cards do
        private fun encodeCards(cards: List<AnkiCard>): JSONArray =
            StudyJson.encodeSet(StudySet(name = "", kind = StudySetKind.ANKI, cards = cards)).getJSONArray("cards")

        private fun decodeCards(cards: JSONArray): List<AnkiCard> =
            StudyJson.decodeSet(JSONObject().put("kind", StudySetKind.ANKI.rawValue).put("cards", cards)).cards

        private fun encodeSource(s: SourceDoc): JSONObject = JSONObject().put("id", s.id).put("name", s.name).put("kind", s.kind)
            .put("pages", JSONArray(s.pages.map { JSONObject().put("number", it.number).put("text", it.text).put("recognised", it.recognised) }))

        private fun decodeSource(o: JSONObject): SourceDoc {
            val pages = o.optJSONArray("pages") ?: JSONArray()
            return SourceDoc(
                id = o.getString("id"), name = o.optString("name"), kind = o.optString("kind", "text"),
                pages = (0 until pages.length()).mapNotNull { pages.optJSONObject(it) }
                    .map { SourcePage(it.optInt("number", 1), it.optString("text"), it.optBoolean("recognised")) },
            )
        }
    }
}

/** What a set of each kind is called in a cloud set's name (iOS StudySetKind.cloudNoun). */
internal val StudySetKind.cloudNoun: String get() = when (this) {
    StudySetKind.MCQ -> "questions"
    StudySetKind.OSCE -> "OSCE stations"
    StudySetKind.ANKI -> "cards"
    StudySetKind.BOOK -> "textbook"
    StudySetKind.NARRATE -> "lecture"
    StudySetKind.CASES -> "cases"
}

/** The same noun as it reads after "made into" in a sentence: the two singular kinds take "a". */
internal val StudySetKind.cloudPhrase: String get() = when (this) {
    StudySetKind.BOOK, StudySetKind.NARRATE -> "a $cloudNoun"
    else -> cloudNoun
}
