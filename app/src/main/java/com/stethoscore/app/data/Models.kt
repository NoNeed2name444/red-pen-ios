package com.stethoscore.app.data

import java.util.UUID

fun newId(): String = UUID.randomUUID().toString()

enum class StudySetKind(val rawValue: String, val label: String) {
    MCQ("mcq", "MCQ"), ANKI("anki", "Cards"), BOOK("book", "Textbook"),
    OSCE("osce", "OSCE"), NARRATE("narrate", "Narrate"), CASES("cases", "Cases");
    companion object { fun from(value: String): StudySetKind? = entries.firstOrNull { it.rawValue == value.lowercase() } }
}
/** What a lecture is spoken in (iOS LectureLanguage): kept on the set as text, so a value a newer version adds never stops the set reading. */
enum class LectureLanguage(val rawValue: String) {
    /** Egyptian Arabic with English medical terms inside the same sentence. */
    MIXED("mixed"),
    /** English throughout. */
    ENGLISH("english");
    /** The on-device recogniser for it. */
    val locale: String get() = if (this == ENGLISH) "en-US" else "ar-EG"
    companion object { fun from(value: String?): LectureLanguage = entries.firstOrNull { it.rawValue == value } ?: MIXED }
}
enum class AnkiCardType(val rawValue: String) { QA("qa"), CLOZE("cloze"), OCCLUSION("occlusion") }

data class StudySet(
    val id: String = newId(), val name: String, val subject: String = "General", val kind: StudySetKind,
    val createdAt: Long = System.currentTimeMillis(), val updatedAt: Long = createdAt, val folderId: String? = null,
    val questions: List<MCQQuestion> = emptyList(), val cards: List<AnkiCard> = emptyList(),
    val bookMarkdown: String = "", val osceChecklists: List<OsceChecklist> = emptyList(),
    val narrateSegments: List<NarrateSegment> = emptyList(), val caseFiles: List<CaseFile> = emptyList(),
    val images: List<String> = emptyList(), val sources: List<SourceDoc> = emptyList(),
    val exam: String? = null, val tags: List<String> = emptyList(), val lectureLanguage: String? = null,
    /** Original object retained so fields added by another version survive export. */
    val rawJson: String = "{}"
) {
    /** The lecture's language, mixed unless the set says otherwise. */
    val language: LectureLanguage get() = LectureLanguage.from(lectureLanguage)
    fun withLanguage(language: LectureLanguage): StudySet = copy(lectureLanguage = language.rawValue)

    val itemCount: Int get() = when (kind) {
        StudySetKind.MCQ -> questions.size
        StudySetKind.ANKI -> cards.size
        StudySetKind.BOOK -> bookPages.size
        StudySetKind.OSCE -> osceChecklists.sumOf { it.steps.size }
        StudySetKind.NARRATE -> narrateSegments.size
        StudySetKind.CASES -> caseFiles.size
    }
    val itemNoun: String get() = when (kind) {
        StudySetKind.MCQ -> "question"; StudySetKind.ANKI -> "card"; StudySetKind.BOOK -> "page"
        StudySetKind.OSCE -> "step"; StudySetKind.NARRATE -> "line"; StudySetKind.CASES -> "patient"
    }
    val bookPages: List<String> get() = bookMarkdown.split(Regex("(?m)(?=^#{1,2}\\s+)")).filter { it.isNotBlank() }
    val itemIds: Set<String> get() = (questions.map { it.id } + cards.map { it.id } + osceChecklists.map { it.id } + narrateSegments.map { it.id } + caseFiles.map { it.id }).toSet()
    fun duplicate(): StudySet = copy(id = newId(), questions = questions.map { it.copy(id = newId()) }, cards = cards.map { it.copy(id = newId()) }, osceChecklists = osceChecklists.map { it.copy(id = newId()) }, narrateSegments = narrateSegments.map { it.copy(id = newId()) }, caseFiles = caseFiles.map { it.copy(id = newId()) }, createdAt = System.currentTimeMillis(), updatedAt = System.currentTimeMillis())
}
data class StudyFolder(val id: String = newId(), val name: String, val updatedAt: Long = System.currentTimeMillis(), val rawJson: String = "{}")
data class MCQQuestion(val id: String = newId(), val stem: String, val options: List<String>, val correctIndex: Int, val explanation: String = "", val imageIndex: Int? = null, val source: String? = null, val tags: List<String> = emptyList(), val rawJson: String = "{}")
data class MCQAnswer(val selected: Int? = null, val checked: Boolean = false) { fun isCorrect(question: MCQQuestion): Boolean = checked && selected == question.correctIndex }
data class OcclusionBox(val x: Double, val y: Double, val w: Double, val h: Double, val rawJson: String = "{}")
data class AnkiCard(val id: String = newId(), val type: AnkiCardType = AnkiCardType.QA, val front: String = "", val bullets: List<String> = emptyList(), val clozeText: String = "", val why: String = "", val imageIndex: Int? = null, val pictureOnBack: Boolean? = null, val occlusion: OcclusionBox? = null, val source: String? = null, val siblings: List<OcclusionBox> = emptyList(), val tags: List<String> = emptyList(), val rawJson: String = "{}") {
    val displayFront: String get() = when { type == AnkiCardType.CLOZE -> cloze(false); type == AnkiCardType.OCCLUSION && front.isBlank() -> "What's hidden here?"; else -> front }
    val pictureOnFront: Boolean get() = type == AnkiCardType.OCCLUSION || pictureOnBack != true
    fun cloze(revealed: Boolean): String = clozeText.replace(Regex("\\{\\{c\\d+::([\\s\\S]+?)(?:::([\\s\\S]*?))?\\}\\}")) { if (revealed) it.groupValues[1] else "[${it.groupValues[2].ifBlank { "…" }}]" }
}
data class OsceChecklist(val id: String = newId(), val title: String, val steps: List<String>, val rawJson: String = "{}")
data class SpokenTiming(val text: String, val start: Double, val end: Double, val rawJson: String = "{}")
data class NarrateSegment(val id: String = newId(), val text: String, val lang: String = "en", val start: Double? = null, val end: Double? = null, val words: List<SpokenTiming> = emptyList(), val model: String? = null, val rawJson: String = "{}")
object NarrateScheduler {
    fun segmentMs(segment: NarrateSegment, speed: Double = 1.0): Double {
        val duration = if (segment.start != null && segment.end != null && segment.end > segment.start) maxOf(300.0, (segment.end - segment.start) * 1000) else maxOf(900.0, segment.text.trim().split(Regex("\\s+")).size.coerceAtLeast(1) / (if (segment.lang == "ar") 110.0 else 150.0) * 60000)
        return duration / maxOf(0.1, speed)
    }
}
data class SourceDoc(val id: String = newId(), val name: String, val kind: String = "text", val pages: List<SourcePage> = emptyList(), val addedAt: Long = System.currentTimeMillis(), val fileBlob: String? = null, val rawJson: String = "{}")
data class SourcePage(val number: Int, val text: String, val recognised: Boolean = false, val rawJson: String = "{}")

data class QuizProgress(val current: Int, val answers: List<MCQAnswer>, val questionIds: List<String>, val optionOrders: List<List<Int>>, val savedAt: Long = System.currentTimeMillis())
data class ReadingProgress(val position: Int, val savedAt: Long = System.currentTimeMillis())
data class OsceProgress(val checklistIndex: Int, val checklistTitle: String, val stepIndex: Int, val missed: List<Int> = emptyList(), val savedAt: Long = System.currentTimeMillis()) {
    fun fits(checklists: List<OsceChecklist>): Boolean { val station = checklists.getOrNull(checklistIndex) ?: return false; return station.title == checklistTitle && stepIndex in 0 until maxOf(1, station.steps.size) && missed.all { it in station.steps.indices } }
}
/**
 * One checked answer (iOS AnswerEvent): how sure the student said they were
 * ("sure", "maybe", "guess"), the option picked as its index in the
 * question's own options, and whether the attending's hint was shown first.
 */
data class AnswerEvent(val questionId: String, val correct: Boolean, val at: Long = System.currentTimeMillis(), val confidence: String? = null, val picked: Int? = null, val hinted: Boolean? = null)
/** The latest reason given for getting one question wrong (iOS MistakeNote); the reason is MistakeReason's raw value. */
data class MistakeNote(val reason: String, val at: Long = System.currentTimeMillis())
data class Note(val id: String = newId(), val title: String, val body: String = "", val folderId: String? = null, val kind: String = "idea", val links: List<String> = emptyList(), val tags: List<String> = emptyList(), val boardX: Double = 0.0, val boardY: Double = 0.0, val createdAt: Long = System.currentTimeMillis(), val updatedAt: Long = createdAt, val rawJson: String = "{}")
