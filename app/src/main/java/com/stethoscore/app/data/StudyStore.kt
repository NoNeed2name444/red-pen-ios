package com.stethoscore.app.data

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Local library. Empty on first launch; examples are added only on request. */
class StudyStore(private val directory: File) {
    private val file = File(directory, "stethoscore.json")
    /** Settings > Review lives beside the library, not in it, as iOS keeps it in UserDefaults. */
    private val reviewSettingsFile = File(directory, "review-settings.json")
    var reviewSettings: ReviewSettings = readReviewSettings()
        private set
    private var original = JSONObject()
    private var unknownSets = emptyList<JSONObject>()
    var loadError: String? = null
        private set
    var library: List<StudySet> = emptyList()
        private set
    var folders: List<StudyFolder> = emptyList()
        private set
    var notes: List<Note> = emptyList()
        private set
    var reviews: Map<String, ReviewRecord> = emptyMap()
        private set
    var quizProgress: Map<String, QuizProgress> = emptyMap()
        private set
    var readingProgress: Map<String, ReadingProgress> = emptyMap()
        private set
    var osceProgress: Map<String, OsceProgress> = emptyMap()
        private set
    var caseRuns: Map<String, String> = emptyMap()
        private set
    var answerHistory: Map<String, List<Boolean>> = emptyMap()
        private set
    var answerLog: List<AnswerEvent> = emptyList()
        private set
    var flagged: Set<String> = emptySet()
        private set
    /** Why each wrong answer was wrong, in the student's own judgement, by question id. */
    var mistakeReasons: Map<String, MistakeNote> = emptyMap()
        private set
    var examDate: Long? = null
        private set
    /** The rating Undo would take back: the card and its record from before. One step, as in Anki. */
    data class UndoableRating(val cardId: String, val previous: ReviewRecord?, val rating: AnkiRating, val at: Long)
    var lastRating: UndoableRating? = null
        private set
    /** Everything that is written to disk, as last saved. A failed save puts memory back to this. */
    private data class Saved(
        val original: JSONObject, val unknownSets: List<JSONObject>, val library: List<StudySet>, val folders: List<StudyFolder>, val notes: List<Note>,
        val reviews: Map<String, ReviewRecord>, val quizProgress: Map<String, QuizProgress>, val readingProgress: Map<String, ReadingProgress>,
        val osceProgress: Map<String, OsceProgress>, val caseRuns: Map<String, String>, val answerHistory: Map<String, List<Boolean>>,
        val answerLog: List<AnswerEvent>, val flagged: Set<String>, val examDate: Long?,
        val mistakeReasons: Map<String, MistakeNote> = emptyMap(),
    )
    private var committed = current()
    /** Called when a background save (progress, ratings, answers) fails; the change is undone. */
    var onSaveError: ((String) -> Unit)? = null

    init { load() }

    @Synchronized fun load() {
        if (!file.exists()) return
        try {
            restore(parse(JSONObject(file.readText())))
            committed = current()
            loadError = null
        } catch (e: Exception) {
            loadError = "Your library could not be opened. The original file has been kept: ${e.message.orEmpty()}"
        }
    }
    private fun parse(root: JSONObject): Saved {
        val sets = root.objects("library") { it }
        return Saved(
            original = root,
            unknownSets = sets.filter { StudySetKind.from(it.text("kind")) == null },
            library = sets.filter { StudySetKind.from(it.text("kind")) != null }.map(StudyJson::decodeSet),
            folders = root.objects("folders") { StudyFolder(it.text("id", newId()), it.text("name", "Folder"), StudyJson.date(it.opt("updatedAt")), it.toString()) },
            notes = root.objects("notes", StudyJson::note),
            reviews = readMap(root.obj("reviews"), StudyJson::review),
            quizProgress = readMap(root.obj("quizProgress")) { o -> QuizProgress(o.optInt("current"), o.objects("answers") { MCQAnswer(it.intOrNull("selected"), it.optBoolean("checked")) }, o.strings("questionIds"), o.optJSONArray("optionOrders")?.let { a -> (0 until a.length()).map { i -> a.optJSONArray(i)?.let { row -> (0 until row.length()).map { row.optInt(it) } } ?: emptyList() } } ?: emptyList(), StudyJson.date(o.opt("savedAt"))) },
            readingProgress = readMap(root.obj("readingProgress")) { ReadingProgress(it.optInt("position"), StudyJson.date(it.opt("savedAt"))) },
            osceProgress = readMap(root.obj("osceProgress")) { OsceProgress(it.optInt("checklistIndex"), it.text("checklistTitle"), it.optInt("stepIndex"), intList(it.optJSONArray("missed")), StudyJson.date(it.opt("savedAt"))) },
            caseRuns = root.obj("caseRuns").let { o -> o.keys().asSequence().associateWith { o.get(it).toString() } },
            answerHistory = root.obj("answerHistory").let { o -> o.keys().asSequence().associateWith { key -> o.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.optBoolean(it) } } ?: emptyList() } },
            answerLog = root.objects("answerLog") { AnswerEvent(it.text("questionId"), it.optBoolean("correct"), StudyJson.date(it.opt("at")), it.nullText("confidence"), it.intOrNull("picked"), if (it.has("hinted") && !it.isNull("hinted")) it.optBoolean("hinted") else null) },
            flagged = root.strings("flagged").toSet(),
            examDate = if (root.isNull("examDate")) null else StudyJson.date(root.opt("examDate")),
            mistakeReasons = readMap(root.obj("mistakeReasons")) { MistakeNote(it.text("reason"), StudyJson.date(it.opt("at"))) }.filterValues { it.reason.isNotEmpty() },
        )
    }
    private fun current() = Saved(original, unknownSets, library, folders, notes, reviews, quizProgress, readingProgress, osceProgress, caseRuns, answerHistory, answerLog, flagged, examDate, mistakeReasons)
    private fun restore(s: Saved) {
        original = s.original; unknownSets = s.unknownSets; library = s.library; folders = s.folders; notes = s.notes
        reviews = s.reviews; quizProgress = s.quizProgress; readingProgress = s.readingProgress; osceProgress = s.osceProgress
        caseRuns = s.caseRuns; answerHistory = s.answerHistory; answerLog = s.answerLog; flagged = s.flagged; examDate = s.examDate
        mistakeReasons = s.mistakeReasons
    }
    private fun intList(a: JSONArray?): List<Int> = a?.let { (0 until it.length()).map(it::optInt) } ?: emptyList()
    private fun <T> readMap(o: JSONObject, decode: (JSONObject) -> T): Map<String, T> = o.keys().asSequence().mapNotNull { key -> o.optJSONObject(key)?.let { key to decode(it) } }.toMap()
    private fun <T> writeMap(map: Map<String, T>, encode: (T) -> Any): JSONObject = JSONObject().also { o -> map.forEach { (key, value) -> o.put(key, encode(value)) } }

    @Synchronized fun exportJson(): String = snapshot().toString(2)
    fun exportSet(set: StudySet): String = StudyJson.encodeSet(set).toString(2)

    private fun snapshot(): JSONObject = raw(original.toString())
        .put("format", "stethoscore-android-v1")
        .put("library", jsonArray(library.map(StudyJson::encodeSet) + unknownSets))
        .put("folders", jsonArray(folders.map { raw(it.rawJson).put("id", it.id).put("name", it.name).putDate("updatedAt", it.updatedAt) }))
        .put("notes", jsonArray(notes.map(StudyJson::encodeNote)))
        .put("reviews", writeMap(reviews, StudyJson::encodeReview))
        .put("quizProgress", writeMap(quizProgress) { p -> JSONObject().put("current", p.current).put("answers", jsonArray(p.answers.map { JSONObject().put("selected", it.selected ?: JSONObject.NULL).put("checked", it.checked) })).put("questionIds", jsonArray(p.questionIds)).put("optionOrders", jsonArray(p.optionOrders.map(::jsonArray))).putDate("savedAt", p.savedAt) })
        .put("readingProgress", writeMap(readingProgress) { JSONObject().put("position", it.position).putDate("savedAt", it.savedAt) })
        .put("osceProgress", writeMap(osceProgress) { JSONObject().put("checklistIndex", it.checklistIndex).put("checklistTitle", it.checklistTitle).put("stepIndex", it.stepIndex).put("missed", jsonArray(it.missed)).putDate("savedAt", it.savedAt) })
        .put("caseRuns", writeMap(caseRuns) { JSONObject(it) })
        .put("answerHistory", writeMap(answerHistory, ::jsonArray))
        .put("answerLog", jsonArray(answerLog.map { e -> JSONObject().put("questionId", e.questionId).put("correct", e.correct).putDate("at", e.at).also { o -> e.confidence?.let { o.put("confidence", it) }; e.picked?.let { o.put("picked", it) }; e.hinted?.let { o.put("hinted", it) } } }))
        .put("mistakeReasons", writeMap(mistakeReasons) { JSONObject().put("reason", it.reason).putDate("at", it.at) })
        .put("flagged", jsonArray(flagged.toList())).putDate("examDate", examDate)

    /**
     * fsync then atomic rename: interruption never replaces the library with a partial write.
     * If the write fails, memory goes back to the last saved state, so screen and disk agree,
     * and the failure is thrown as an IllegalStateException with a message for the person.
     */
    @Synchronized fun save() {
        val temporary = File(directory, "stethoscore.json.tmp")
        try {
            check(loadError == null) { loadError ?: "Library unavailable" }
            check(directory.exists() || directory.mkdirs()) { "Could not create the library directory." }
            val bytes = snapshot().toString().toByteArray(Charsets.UTF_8)
            FileOutputStream(temporary).use { stream -> stream.write(bytes); stream.fd.sync() }
            try {
                Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
                // Both files are in one directory; Android rename replaces atomically on its local filesystem.
                check(temporary.renameTo(file)) { "Could not replace the library file." }
            }
            committed = current()
        } catch (e: Exception) {
            restore(committed)
            temporary.delete()
            throw if (e is IllegalStateException) e else IllegalStateException("Could not save your library: ${e.message.orEmpty()}", e)
        }
    }
    /** Saves a background change; a failure is reported through [onSaveError] instead of thrown. */
    private fun saveQuietly() {
        try { save() } catch (e: IllegalStateException) { onSaveError?.invoke(e.message ?: "Could not save your library.") }
    }

    @Synchronized fun addSet(set: StudySet) {
        val existing = library.indexOfFirst { it.id == set.id }
        library = if (existing < 0) library + set else library.map { if (it.id == set.id) set.copy(updatedAt = System.currentTimeMillis()) else it }
        save()
    }
    fun updateSet(set: StudySet) = addSet(set)
    /** Forgets the schedule of these cards only (iOS ReviewStore.forget): the editor's deleted cards. */
    @Synchronized fun forgetReviews(cardIds: Collection<String>) {
        if (cardIds.isEmpty()) return
        val gone = cardIds.toSet()
        reviews = reviews.filterKeys { it !in gone }
        save()
    }
    @Synchronized fun deleteSet(id: String) {
        val removed = library.firstOrNull { it.id == id } ?: return
        library = library.filterNot { it.id == id }
        quizProgress = quizProgress - id; readingProgress = readingProgress - id; osceProgress = osceProgress - id
        val remainingCards = library.flatMap { it.cards }.map { it.id }.toSet()
        reviews = reviews.filterKeys { it in remainingCards }
        caseRuns = caseRuns.filterKeys { !it.startsWith("$id:") && it !in removed.caseFiles.map { case -> case.id } }
        save()
    }
    /** Several sets at once, with any folders they need, in one save (iOS Store.addSets). */
    @Synchronized fun addSets(sets: List<StudySet>, newFolders: List<StudyFolder> = emptyList()) {
        if (sets.isEmpty() && newFolders.isEmpty()) return
        folders = folders + newFolders
        library = library + sets
        save()
    }

    // Library: names and folders (iOS Store.rename / group / move / ungroup / renameFolder / combine)

    @Synchronized fun rename(id: String, name: String) {
        val set = library.firstOrNull { it.id == id } ?: return
        if (set.name == name) return
        library = library.map { if (it.id == id) it.copy(name = name, updatedAt = System.currentTimeMillis()) else it }
        save()
    }

    /** Puts [ids] into a new folder called [name]; any folder a set leaves that is now empty is removed. */
    @Synchronized fun group(ids: Set<String>, name: String): StudyFolder {
        val folder = StudyFolder(name = name.trim().ifEmpty { "Folder" })
        folders = folders + folder
        val left = library.filter { it.id in ids }.map { it.folderId }
        val now = System.currentTimeMillis()
        library = library.map { if (it.id in ids) it.copy(folderId = folder.id, updatedAt = now) else it }
        pruneEmptyFolders(left)
        save()
        return folder
    }

    /** Moves one set into a folder, or out of every folder with null. */
    @Synchronized fun move(id: String, folderId: String?) {
        val set = library.firstOrNull { it.id == id } ?: return
        if (set.folderId == folderId) return
        library = library.map { if (it.id == id) it.copy(folderId = folderId, updatedAt = System.currentTimeMillis()) else it }
        pruneEmptyFolders(listOf(set.folderId))
        save()
    }

    /** Clears the folder on every member and removes the folder; never deletes the sets themselves. */
    @Synchronized fun ungroup(folderId: String) {
        val now = System.currentTimeMillis()
        library = library.map { if (it.folderId == folderId) it.copy(folderId = null, updatedAt = now) else it }
        folders = folders.filterNot { it.id == folderId }
        save()
    }

    @Synchronized fun renameFolder(id: String, name: String) {
        val folder = folders.firstOrNull { it.id == id } ?: return
        if (folder.name == name) return
        folders = folders.map { if (it.id == id) it.copy(name = name, updatedAt = System.currentTimeMillis()) else it }
        save()
    }

    /** Only the folders sets just left, if that left them empty. */
    private fun pruneEmptyFolders(left: List<String?>) {
        val used = library.mapNotNull { it.folderId }.toSet()
        val emptied = left.filterNotNull().toSet() - used
        if (emptied.isNotEmpty()) folders = folders.filterNot { it.id in emptied }
    }

    /** Two or more sets of one kind joined into a new set; the originals are left untouched. */
    @Synchronized fun combine(ids: List<String>, name: String): StudySet? {
        val members = ids.mapNotNull { id -> library.firstOrNull { it.id == id } }
        val out = SetImport.combined(members, name) ?: return null
        library = library + out
        save()
        return out
    }

    @Synchronized fun importJson(text: String): Int {
        require(text.toByteArray(Charsets.UTF_8).size <= 32 * 1024 * 1024) { "Choose a JSON file smaller than 32 MB." }
        val incoming = StudyJson.decodeSets(text)
        require(incoming.isNotEmpty()) { "No supported study sets were found in this file." }
        val ids = library.map { it.id }.toMutableSet()
        val itemIds = library.flatMap { it.itemIds }.toMutableSet()
        val additions = incoming.map { candidate ->
            val set = if (candidate.id in ids || candidate.itemIds.any { it in itemIds }) candidate.duplicate() else candidate
            ids += set.id; itemIds += set.itemIds; set
        }
        library = library + additions
        backupOf(text)?.let(::mergeBackup)
        save()
        return additions.size
    }
    /** A whole-library export (from Settings) rather than a single set or a list of sets. */
    private fun backupOf(text: String): Saved? = runCatching {
        val root = JSONObject(text)
        if (!root.has("library") || !root.optString("format").startsWith("stethoscore")) null else parse(root)
    }.getOrNull()
    /** Adds what this device does not have yet; anything already here wins. */
    private fun mergeBackup(b: Saved) {
        val noteIds = notes.map { it.id }.toSet()
        notes = notes + b.notes.filter { it.id !in noteIds }
        // card by card, the later word on each card winning (iOS ReviewStore.merge)
        reviews = ReviewPlan.merging(reviews, b.reviews)
        quizProgress = b.quizProgress + quizProgress
        readingProgress = b.readingProgress + readingProgress
        osceProgress = b.osceProgress + osceProgress
        caseRuns = b.caseRuns + caseRuns
        answerHistory = b.answerHistory + answerHistory
        val logged = answerLog.map { Triple(it.questionId, it.correct, it.at) }.toSet()
        answerLog = (answerLog + b.answerLog.filter { Triple(it.questionId, it.correct, it.at) !in logged }).sortedBy { it.at }
        flagged = flagged + b.flagged
        if (examDate == null) examDate = b.examDate
        mistakeReasons = b.mistakeReasons + mistakeReasons
    }
    @Synchronized fun loadExamples() {
        val added = DemoData.sets.filter { example -> library.none { it.name == "Example: ${example.name}" } }.map { it.duplicate().copy(name = "Example: ${it.name}") }
        if (added.isNotEmpty()) { library = library + added; save() }
    }
    @Synchronized fun saveQuizProgress(setId: String, progress: QuizProgress) { quizProgress = quizProgress + (setId to progress); saveQuietly() }
    @Synchronized fun clearQuizProgress(setId: String) { quizProgress = quizProgress - setId; saveQuietly() }
    @Synchronized fun saveReadingProgress(setId: String, position: Int) { readingProgress = readingProgress + (setId to ReadingProgress(position.coerceAtLeast(0))); saveQuietly() }
    @Synchronized fun saveOsceProgress(setId: String, progress: OsceProgress) { osceProgress = osceProgress + (setId to progress); saveQuietly() }
    @Synchronized fun clearOsceProgress(setId: String) { osceProgress = osceProgress - setId; saveQuietly() }
    @Synchronized fun saveCaseRun(caseId: String, json: String) { JSONObject(json); caseRuns = caseRuns + (caseId to json); saveQuietly() }
    @Synchronized fun clearCaseRun(caseId: String) { caseRuns = caseRuns - caseId; saveQuietly() }
    /**
     * Records a checked answer: right or wrong in the history, and in the log
     * how sure the student was, what they picked (in the question's own
     * numbering) and whether the hint was shown first. [saving] false leaves
     * the write to the save that follows (the quiz's place), as iOS does.
     */
    @Synchronized fun recordAnswer(questionId: String, correct: Boolean, confidence: String? = null, picked: Int? = null, hinted: Boolean = false, saving: Boolean = true) {
        answerHistory = answerHistory + (questionId to ((answerHistory[questionId] ?: emptyList()) + correct))
        answerLog = answerLog + AnswerEvent(questionId, correct, confidence = confidence, picked = picked, hinted = if (hinted) true else null)
        if (saving) saveQuietly()
    }
    /** Files a wrong answer under a reason (MistakeReason's raw value), or clears it with null. */
    @Synchronized fun noteMistake(reason: String?, questionId: String) {
        if (reason != null) mistakeReasons = mistakeReasons + (questionId to MistakeNote(reason))
        else { if (questionId !in mistakeReasons) return; mistakeReasons = mistakeReasons - questionId }
        saveQuietly()
    }
    /** Questions answered wrongly while the student said they were sure, the last time they were answered. */
    val confidentMistakeIds: Set<String> get() = answerLog.associateBy { it.questionId }.values.filter { !it.correct && it.confidence == "sure" }.map { it.questionId }.toSet()
    @Synchronized fun toggleFlag(questionId: String) { flagged = if (questionId in flagged) flagged - questionId else flagged + questionId; saveQuietly() }
    /** Today's queue for one deck: due, not suspended or buried, within the library's daily limits. */
    fun queue(set: StudySet, now: Long = System.currentTimeMillis()): List<AnkiQueueItem> = ReviewOptions.dailyQueue(set.cards, reviews, now, reviewSettings.limits)
    fun dueCards(set: StudySet, now: Long = System.currentTimeMillis()): List<AnkiCard> = queue(set, now).map { it.card }
    /** Study ahead: the whole deck except suspended cards. */
    fun everything(set: StudySet, now: Long = System.currentTimeMillis()): List<AnkiQueueItem> = ReviewOptions.studyAhead(set.cards, reviews, now)
    fun nextDue(set: StudySet): Long? = ReviewPlan.nextDue(set.cards, reviews)
    private fun decks() = library.filter { it.kind == StudySetKind.ANKI }.map { it.reviewDeck() }
    /** Everything due across the library today; the daily limits apply once to the whole library. */
    fun dueAcross(now: Long = System.currentTimeMillis()): List<ReviewPlan.Due> = ReviewOptions.dueToday(decks(), reviews, now, reviewSettings.limits)
    fun dueCount(now: Long = System.currentTimeMillis()): Int = ReviewOptions.dueCount(library.filter { it.kind == StudySetKind.ANKI }.flatMap { it.cards }, reviews, now, reviewSettings.limits)
    /** Records a rating and returns the card's new standing. */
    @Synchronized fun rateCard(card: AnkiCard, rating: AnkiRating, now: Long = System.currentTimeMillis()): ReviewRecord {
        val kept = ReviewPlan.record(card, reviews, now)
        val next = ReviewOptions.after(rating, kept, now, examDate, reviewSettings.scheduler)
        lastRating = UndoableRating(card.id, reviews[card.id], rating, now)
        reviews = reviews + (card.id to next)
        saveQuietly(); return reviews[card.id] ?: next
    }
    /** Takes back the last rating, stamped now so a merge takes the undo over it. Returns what was undone. */
    @Synchronized fun undoLast(now: Long = System.currentTimeMillis()): UndoableRating? {
        val last = lastRating ?: return null
        lastRating = null
        reviews = reviews + (last.cardId to ReviewOptions.restoring(last.previous, now))
        saveQuietly(); return last
    }
    /** Out of every queue until let back in. */
    @Synchronized fun suspendCard(card: AnkiCard, on: Boolean = true, now: Long = System.currentTimeMillis()) {
        reviews = reviews + (card.id to ReviewOptions.suspending(card, on, reviews, now))
        if (lastRating?.cardId == card.id) lastRating = null
        saveQuietly()
    }
    /** Out of today's queues, back tomorrow. */
    @Synchronized fun buryCard(card: AnkiCard, now: Long = System.currentTimeMillis()) {
        reviews = reviews + (card.id to ReviewOptions.burying(card, reviews, now))
        if (lastRating?.cardId == card.id) lastRating = null
        saveQuietly()
    }
    /** Every suspended card back into its deck's schedule. */
    @Synchronized fun unsuspendAll(now: Long = System.currentTimeMillis()) {
        val back = reviews.filterValues { it.suspended }.mapValues { it.value.copy(suspended = false, changedAt = now) }
        if (back.isEmpty()) return
        reviews = reviews + back; saveQuietly()
    }
    val suspendedCount: Int get() = reviews.values.count { it.suspended }
    @Synchronized fun setExamDate(date: Long?) { examDate = date; saveQuietly() }
    @Synchronized fun setReviewSettings(settings: ReviewSettings) {
        val clean = settings.copy(limits = ReviewLimits(settings.limits.newPerDay.coerceIn(0, 9999), settings.limits.reviewsPerDay.coerceIn(0, 9999)))
        val json = JSONObject().put("scheduler", clean.scheduler.name.lowercase()).put("newPerDay", clean.limits.newPerDay).put("reviewsPerDay", clean.limits.reviewsPerDay)
        check(directory.exists() || directory.mkdirs()) { "Could not create the library directory." }
        val temporary = File(directory, "review-settings.json.tmp")
        FileOutputStream(temporary).use { it.write(json.toString().toByteArray(Charsets.UTF_8)); it.fd.sync() }
        check(temporary.renameTo(reviewSettingsFile)) { "Could not save the review settings." }
        reviewSettings = clean
    }
    private fun readReviewSettings(): ReviewSettings = runCatching {
        if (!reviewSettingsFile.exists()) return@runCatching ReviewSettings()
        val o = JSONObject(reviewSettingsFile.readText())
        ReviewSettings(
            scheduler = ReviewScheduler.entries.firstOrNull { it.name.equals(o.optString("scheduler"), ignoreCase = true) } ?: ReviewScheduler.CLASSIC,
            limits = ReviewLimits(o.optInt("newPerDay", 0).coerceAtLeast(0), o.optInt("reviewsPerDay", 0).coerceAtLeast(0)),
        )
    }.getOrDefault(ReviewSettings())
    @Synchronized fun saveNote(note: Note) {
        val existing = notes.firstOrNull { it.id == note.id }
        if (existing == note) return
        val updated = if (existing == null) note else note.copy(updatedAt = System.currentTimeMillis())
        notes = if (existing == null) notes + updated else notes.map { if (it.id == note.id) updated else it }
        save()
    }
    @Synchronized fun deleteNote(id: String) { notes = notes.filterNot { it.id == id }.map { it.copy(links = it.links - id) }; save() }
    fun searchNotes(query: String): List<Note> { val words = query.lowercase().split(Regex("\\s+")).filter { it.isNotBlank() }; return notes.filter { n -> val text = "${n.title} ${n.body} ${n.tags.joinToString(" ")}".lowercase(); words.all(text::contains) }.sortedByDescending { it.updatedAt } }
    fun backlinks(note: Note): List<Note> = notes.filter { it.id != note.id && (note.id in it.links || Regex("\\[\\[${Regex.escape(note.title)}(?:\\|[^]]*)?]]", RegexOption.IGNORE_CASE).containsMatchIn(it.body)) }
}
