package com.stethoscore.app.data

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.time.Instant
import java.time.OffsetDateTime

internal fun JSONObject.text(key: String, fallback: String = ""): String = if (isNull(key)) fallback else optString(key, fallback)
internal fun JSONObject.nullText(key: String): String? = if (isNull(key)) null else optString(key)
internal fun JSONObject.intOrNull(key: String): Int? = if (isNull(key)) null else optInt(key)
internal fun JSONObject.doubleOrNull(key: String): Double? = if (isNull(key)) null else optDouble(key).takeIf { it.isFinite() }
internal fun JSONObject.obj(key: String): JSONObject = optJSONObject(key) ?: JSONObject()
internal fun JSONObject.strings(key: String): List<String> = optJSONArray(key)?.let { a -> (0 until a.length()).mapNotNull { a.opt(it) as? String } } ?: emptyList()
internal fun <T> JSONObject.objects(key: String, decode: (JSONObject) -> T): List<T> = optJSONArray(key)?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let(decode) } } ?: emptyList()
internal fun raw(text: String): JSONObject = runCatching { JSONObject(text) }.getOrDefault(JSONObject())
internal fun jsonArray(items: List<Any?>): JSONArray = JSONArray().also { a -> items.forEach { a.put(it) } }
internal fun JSONObject.putDate(key: String, value: Long?): JSONObject = put(key, value?.let { Instant.ofEpochMilli(it).toString() } ?: JSONObject.NULL)

/** iOS normally exports ISO-8601; older JSONEncoder files use seconds from 2001-01-01. */
object StudyJson {
    private const val SWIFT_EPOCH_MS = 978307200000L
    fun date(value: Any?, fallback: Long = System.currentTimeMillis()): Long = when (value) {
        is Number -> if (value.toDouble().isFinite()) (value.toDouble() * 1000).toLong() + SWIFT_EPOCH_MS else fallback
        is String -> runCatching { Instant.parse(value).toEpochMilli() }.recoverCatching { OffsetDateTime.parse(value).toInstant().toEpochMilli() }.getOrDefault(fallback)
        else -> fallback
    }
    fun decodeSets(text: String): List<StudySet> {
        val root = JSONTokener(text).nextValue()
        val array = when (root) {
            is JSONArray -> root
            is JSONObject -> when { root.has("kind") -> JSONArray().put(root); root.optJSONArray("library") != null -> root.getJSONArray("library"); root.optJSONArray("sets") != null -> root.getJSONArray("sets"); root.optJSONObject("set") != null -> JSONArray().put(root.getJSONObject("set")); else -> throw IllegalArgumentException("Choose a Stethoscore study set or library JSON file.") }
            else -> throw IllegalArgumentException("The file does not contain a JSON object or library.")
        }
        require(array.length() <= 10000) { "This library contains too many sets to import at once." }
        return (0 until array.length()).mapNotNull { i -> array.optJSONObject(i)?.let { if (StudySetKind.from(it.text("kind")) != null) decodeSet(it) else null } }
    }
    fun decodeSet(o: JSONObject): StudySet {
        val kind = StudySetKind.from(o.text("kind")) ?: throw IllegalArgumentException("Unsupported study mode: ${o.text("kind")}")
        val created = date(o.opt("createdAt"))
        return StudySet(id = o.text("id", newId()), name = o.text("name", "Untitled"), subject = o.text("subject", "General"), kind = kind, createdAt = created, updatedAt = date(o.opt("updatedAt"), created), folderId = o.nullText("folderId"), questions = o.objects("questions", ::question), cards = o.objects("cards", ::card), bookMarkdown = o.text("bookMarkdown"), osceChecklists = o.objects("osceChecklists", ::osce), narrateSegments = o.objects("narrateSegments", ::narrate), caseFiles = o.objects("caseFiles", ::case), images = o.strings("images"), sources = o.objects("sources", ::source), exam = o.nullText("exam"), tags = o.strings("tags"), lectureLanguage = o.nullText("lectureLanguage"), rawJson = o.toString())
    }
    fun encodeSet(s: StudySet): JSONObject = raw(s.rawJson).put("id", s.id).put("name", s.name).put("subject", s.subject).put("kind", s.kind.rawValue).putDate("createdAt", s.createdAt).putDate("updatedAt", s.updatedAt).put("folderId", s.folderId ?: JSONObject.NULL).put("questions", jsonArray(s.questions.map(::encodeQuestion))).put("cards", jsonArray(s.cards.map(::encodeCard))).put("bookMarkdown", s.bookMarkdown).put("osceChecklists", jsonArray(s.osceChecklists.map { raw(it.rawJson).put("id", it.id).put("title", it.title).put("steps", jsonArray(it.steps)) })).put("narrateSegments", jsonArray(s.narrateSegments.map(::encodeNarrate))).put("caseFiles", jsonArray(s.caseFiles.map(::encodeCase))).put("images", jsonArray(s.images)).put("sources", jsonArray(s.sources.map(::encodeSource))).put("exam", s.exam ?: JSONObject.NULL).put("tags", jsonArray(s.tags)).put("lectureLanguage", s.lectureLanguage ?: JSONObject.NULL)
    private fun question(o: JSONObject) = MCQQuestion(id = o.text("id", newId()), stem = o.text("stem"), options = o.strings("options"), correctIndex = o.optInt("correctIndex", -1), explanation = o.text("explanation"), imageIndex = o.intOrNull("imageIndex"), source = o.nullText("source"), tags = o.strings("tags"), rawJson = o.toString())
    private fun encodeQuestion(q: MCQQuestion): JSONObject = raw(q.rawJson).put("id", q.id).put("stem", q.stem).put("options", jsonArray(q.options)).put("correctIndex", q.correctIndex).put("explanation", q.explanation).put("imageIndex", q.imageIndex ?: JSONObject.NULL).put("source", q.source ?: JSONObject.NULL).put("tags", jsonArray(q.tags))
    private fun box(o: JSONObject) = OcclusionBox(o.optDouble("x", 0.0), o.optDouble("y", 0.0), o.optDouble("w", 0.0), o.optDouble("h", 0.0), o.toString())
    private fun encodeBox(b: OcclusionBox): JSONObject = raw(b.rawJson).put("x", b.x).put("y", b.y).put("w", b.w).put("h", b.h)
    private fun card(o: JSONObject) = AnkiCard(id = o.text("id", newId()), type = AnkiCardType.entries.firstOrNull { it.rawValue == o.text("type") } ?: AnkiCardType.QA, front = o.text("front"), bullets = o.strings("bullets"), clozeText = o.text("clozeText"), why = o.text("why"), imageIndex = o.intOrNull("imageIndex"), pictureOnBack = if (o.isNull("pictureOnBack")) null else o.optBoolean("pictureOnBack"), occlusion = o.optJSONObject("occlusion")?.let(::box), source = o.nullText("source"), siblings = o.objects("siblings", ::box), tags = o.strings("tags"), rawJson = o.toString())
    private fun encodeCard(c: AnkiCard): JSONObject = raw(c.rawJson).put("id", c.id).put("type", c.type.rawValue).put("front", c.front).put("bullets", jsonArray(c.bullets)).put("clozeText", c.clozeText).put("why", c.why).put("imageIndex", c.imageIndex ?: JSONObject.NULL).put("pictureOnBack", c.pictureOnBack ?: JSONObject.NULL).put("occlusion", c.occlusion?.let(::encodeBox) ?: JSONObject.NULL).put("source", c.source ?: JSONObject.NULL).put("siblings", jsonArray(c.siblings.map(::encodeBox))).put("tags", jsonArray(c.tags))
    private fun osce(o: JSONObject) = OsceChecklist(o.text("id", newId()), o.text("title"), o.strings("steps"), o.toString())
    private fun narrate(o: JSONObject) = NarrateSegment(o.text("id", newId()), o.text("text"), o.text("lang", "en"), o.doubleOrNull("start"), o.doubleOrNull("end"), o.objects("words") { SpokenTiming(it.text("text"), it.optDouble("start", 0.0), it.optDouble("end", 0.0), it.toString()) }, o.nullText("model"), o.toString())
    private fun encodeNarrate(s: NarrateSegment): JSONObject = raw(s.rawJson).put("id", s.id).put("text", s.text).put("lang", s.lang).put("start", s.start ?: JSONObject.NULL).put("end", s.end ?: JSONObject.NULL).put("model", s.model ?: JSONObject.NULL).put("words", jsonArray(s.words.map { raw(it.rawJson).put("text", it.text).put("start", it.start).put("end", it.end) }))
    private fun source(o: JSONObject) = SourceDoc(o.text("id", newId()), o.text("name"), o.text("kind", "text"), o.objects("pages") { SourcePage(it.optInt("number", 1), it.text("text"), it.optBoolean("recognised"), it.toString()) }, date(o.opt("addedAt")), o.nullText("fileBlob"), o.toString())
    private fun encodeSource(s: SourceDoc): JSONObject = raw(s.rawJson).put("id", s.id).put("name", s.name).put("kind", s.kind).putDate("addedAt", s.addedAt).put("fileBlob", s.fileBlob ?: JSONObject.NULL).put("pages", jsonArray(s.pages.map { raw(it.rawJson).put("number", it.number).put("text", it.text).put("recognised", it.recognised) }))
    fun case(o: JSONObject): CaseFile = CaseJson.read(o)
    fun encodeCase(c: CaseFile): JSONObject = CaseJson.write(c)
    internal fun note(o: JSONObject): Note { val created = date(o.opt("createdAt")); return Note(o.text("id", newId()), o.text("title"), o.text("body"), o.nullText("folderId"), o.text("kind", "idea"), o.strings("links"), o.strings("tags"), o.optDouble("boardX", 0.0), o.optDouble("boardY", 0.0), created, date(o.opt("updatedAt"), created), o.toString()) }
    internal fun encodeNote(n: Note): JSONObject = raw(n.rawJson).put("id", n.id).put("title", n.title).put("body", n.body).put("folderId", n.folderId ?: JSONObject.NULL).put("kind", n.kind).put("links", jsonArray(n.links)).put("tags", jsonArray(n.tags)).put("boardX", n.boardX).put("boardY", n.boardY).putDate("createdAt", n.createdAt).putDate("updatedAt", n.updatedAt)
    internal fun review(o: JSONObject) = ReviewRecord(date(o.opt("due")), o.optDouble("intervalMin", 0.0).let { if (it.isFinite()) it.coerceIn(0.0, AnkiScheduler.maxIntervalMin) else AnkiScheduler.maxIntervalMin }, o.optInt("reviews"), o.optInt("lapses"), date(o.opt("ratedAt")), o.optBoolean("suspended"), if (o.isNull("buriedUntil")) null else date(o.opt("buriedUntil")), o.doubleOrNull("stability"), o.doubleOrNull("difficulty"), if (o.isNull("introducedAt")) null else date(o.opt("introducedAt")), if (o.isNull("changedAt")) null else date(o.opt("changedAt")), o.toString())
    /**
     * A record as iOS's Codable writes it: the review essentials' keys only when they are set,
     * so a record nothing has changed carries no new keys (no spurious sync).
     */
    internal fun encodeReview(r: ReviewRecord): JSONObject = raw(r.rawJson).putDate("due", r.due).put("intervalMin", r.intervalMin).put("reviews", r.reviews).put("lapses", r.lapses).putDate("ratedAt", r.ratedAt)
        .apply { if (r.suspended) put("suspended", true) else remove("suspended") }.putOptionalDate("buriedUntil", r.buriedUntil).put("stability", r.stability).put("difficulty", r.difficulty).putOptionalDate("introducedAt", r.introducedAt).putOptionalDate("changedAt", r.changedAt)
    private fun JSONObject.putOptionalDate(key: String, value: Long?): JSONObject = if (value == null) apply { remove(key) } else putDate(key, value)
}
