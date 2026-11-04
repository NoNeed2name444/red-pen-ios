package com.stethoscore.app.llm

import com.stethoscore.app.data.CaseWriting
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import org.json.JSONArray
import org.json.JSONObject

/**
 * What a set written in the cloud needs to be finished without the screen
 * that asked for it: kept with the job ([CloudJobs.Pending.recipe]) in case
 * the app is closed before the server is done. Port of iOS CloudRecipe
 * (Shared/CloudJobCollector.swift).
 *
 * Not ported yet (T0115b): a textbook's figures and the image occlusion
 * cards that go with written ones; no Android screen sends those to the cloud.
 */
data class CloudRecipe(
    val kind: StudySetKind,
    val name: String,
    val subject: String,
    val count: Int,
    val source: SourceDoc? = null,
    /** The exam it was written for (ExamCatalog id), for the set's badge. */
    val exam: String? = null,
) {
    fun json(): String = JSONObject().put("kind", kind.rawValue).put("name", name).put("subject", subject).put("count", count)
        .put("source", source?.let(::encodeSource) ?: JSONObject.NULL).put("exam", exam ?: JSONObject.NULL).toString()

    /**
     * The set, from the job's replies: the same parsing the screens use. Null
     * when the replies make no set, or for a kind Android does not write in
     * the cloud yet (the collector keeps those replies as text).
     */
    fun set(replies: List<String>, @Suppress("UNUSED_PARAMETER") extra: String?): StudySet? {
        val title = name.trim()
        var set = StudySet(
            name = title.ifEmpty { "${subject.ifEmpty { "Generated" }} – ${kind.cloudNoun}" },
            subject = subject.ifEmpty { "General" }, kind = kind, exam = exam,
        )
        set = when (kind) {
            StudySetKind.MCQ -> {
                val questions = runCatching { MedicalGenerate.collectQuestions(replies, count) }.getOrNull()
                if (questions.isNullOrEmpty()) return null
                set.copy(questions = questions)
            }
            StudySetKind.CASES -> {
                val written = CaseWriting.collect(replies, count, source?.name.orEmpty())
                if (written.isEmpty()) return null
                set.copy(caseFiles = written)
            }
            // no Android writer sends these to the cloud yet (T0115b)
            StudySetKind.OSCE, StudySetKind.ANKI, StudySetKind.BOOK, StudySetKind.NARRATE -> return null
        }
        return set.copy(sources = listOfNotNull(source))
    }

    companion object {
        fun of(text: String?): CloudRecipe? {
            if (text == null) return null
            return runCatching {
                val o = JSONObject(text)
                CloudRecipe(
                    StudySetKind.from(o.getString("kind")) ?: return null,
                    o.optString("name"), o.optString("subject"), o.optInt("count"),
                    o.optJSONObject("source")?.let(::decodeSource), o.opt("exam") as? String,
                )
            }.getOrNull()
        }

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
