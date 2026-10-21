package com.stethoscore.app.ui.home

import com.stethoscore.app.data.BedPlan
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.data.RhythmReading
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.StudyMinutes
import com.stethoscore.app.data.StudyStreak
import com.stethoscore.app.data.WardWords
import com.stethoscore.app.quiz.ExamTrack
import java.time.Instant
import java.time.ZoneId

// What home's round, tiles and countdown are made from, read from the
// library (iOS WardHome.swift's LibraryView extension: bedInput, dueSubjects,
// freshSets, roundStations, started, progress; ExamCountdown; and
// StoreStudy's subjectStats and drill). Nothing here is stored.

/** The exam date kept by Settings, as the home counts down to it (iOS ExamCountdown). */
object ExamCountdown {
    /**
     * The chosen exam's short name; nil for general revision, which the
     * countdown calls finals. Android has no exam choice or track yet
     * (ExamChoice, ExamTrack: batch 16), so it is always nil.
     */
    val examName: String? get() = null

    /** Days until the exam, or null when no date is set. */
    fun daysLeft(examDate: Long?, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Int? =
        examDate?.let { ExamWeekPlanner.daysLeft(Instant.ofEpochMilli(it), now, zone) }

    /** "Finals in 23 days"; null with no date, or once it has passed. */
    fun text(examDate: Long?, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String? =
        WardWords.countdown(daysLeft(examDate, now, zone), examName)
}

object HomeRound {
    /** A set's subject, "General" when it has none (Store.subjectName). */
    fun subjectName(set: StudySet): String = set.subject.trim().ifEmpty { "General" }

    /** Every subject as the answer history sees it, weakest answered first (Store.subjectStats). */
    fun subjectStats(store: StudyStore): List<BedPlan.Topic> {
        val by = LinkedHashMap<String, BedPlan.Topic>()
        val seen = HashSet<String>()
        for (set in store.library) if (set.kind == StudySetKind.MCQ) for (q in set.questions) {
            if (!seen.add(q.id)) continue
            val subject = subjectName(set)
            val now = by[subject] ?: BedPlan.Topic(subject, 0, 0, 0)
            val past = store.answerHistory[q.id].orEmpty()
            by[subject] = now.copy(questions = now.questions + 1, answered = now.answered + past.size, correct = now.correct + past.count { it })
        }
        return by.values.sortedWith(Comparator { a, b ->
            if ((a.answered == 0) != (b.answered == 0)) return@Comparator if (b.answered == 0) -1 else 1
            if (a.accuracy != b.accuracy) return@Comparator a.accuracy.compareTo(b.accuracy)
            a.name.compareTo(b.name)
        })
    }

    /** The modes a set can take a bed in. */
    fun bedMode(kind: StudySetKind): BedPlan.Mode? = when (kind) {
        StudySetKind.MCQ -> BedPlan.Mode.questions
        StudySetKind.ANKI -> BedPlan.Mode.cards
        StudySetKind.BOOK -> BedPlan.Mode.textbook
        else -> null
    }

    /**
     * How far into a set the student is, 0 to 1: questions answered at least
     * once, cards reviewed, the step reached in a station, the page reached.
     * Null for a lecture, which keeps no place.
     */
    fun progress(store: StudyStore, set: StudySet): Double? {
        val total = set.itemCount
        if (total <= 0) return null
        val done = when (set.kind) {
            StudySetKind.MCQ -> set.questions.count { store.answerHistory[it.id].orEmpty().isNotEmpty() }
            StudySetKind.ANKI -> set.cards.count { (store.reviews[it.id]?.reviews ?: 0) > 0 }
            StudySetKind.OSCE -> {
                val saved = store.osceProgress[set.id]
                if (saved == null || !saved.fits(set.osceChecklists)) 0
                else set.osceChecklists.take(saved.checklistIndex).sumOf { it.steps.size } + saved.stepIndex
            }
            StudySetKind.NARRATE -> return null
            else -> store.readingProgress[set.id]?.position ?: 0
        }
        return minOf(1.0, done.toDouble() / total)
    }

    /** Whether anything has been done in a set yet. */
    fun started(store: StudyStore, set: StudySet): Boolean {
        if (store.quizProgress[set.id] != null || store.readingProgress[set.id] != null) return true
        return (progress(store, set) ?: 0.0) > 0
    }

    /** The subjects the due cards come from, most cards first: a deck's subject, or its name when it has none. */
    fun dueSubjects(store: StudyStore, due: List<com.stethoscore.app.data.ReviewPlan.Due>): List<String> {
        val label = HashMap<String, String>()
        for (set in store.library) if (set.kind == StudySetKind.ANKI) {
            val subject = subjectName(set)
            label[set.id] = if (subject == "General") set.name else subject
        }
        val counts = LinkedHashMap<String, Int>()
        for (item in due) counts.merge(label[item.setId] ?: item.setName, 1, Int::plus)
        return counts.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }).map { it.key }
    }

    /** Everything BedPlan weighs, read from the library. */
    fun input(store: StudyStore, dueCount: Int, dueFrom: List<String>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault(),
              situation: ExamWeekPlanner.Situation? = null, track: ExamTrack = ExamTrack.general): BedPlan.Input {
        val fresh = store.library.mapNotNull { set ->
            val mode = bedMode(set.kind) ?: return@mapNotNull null
            if (started(store, set)) null
            else BedPlan.FreshSet(set.id, set.name, set.subject, mode, set.itemCount, set.createdAt)
        }
        // each OSCE set's station, the one opening the set lands on: where it was left, or the first
        val stations = store.library.filter { it.kind == StudySetKind.OSCE }.mapNotNull { set ->
            val first = set.osceChecklists.firstOrNull() ?: return@mapNotNull null
            val saved = store.osceProgress[set.id]
            if (saved != null && saved.fits(set.osceChecklists))
                BedPlan.Station(set.id, set.osceChecklists[saved.checklistIndex].title, true, set.createdAt)
            else BedPlan.Station(set.id, first.title, false, set.createdAt)
        }
        return BedPlan.Input(
            // the run-up's own priority (ExamWeekPlanner's mission), when the situation was read
            mission = situation?.let { ExamWeekPlanner.mission(it) } ?: ExamWeekPlanner.Mission.Nothing,
            phase = situation?.phase ?: ExamWeekPlanner.phase(store.examDate?.let { Instant.ofEpochMilli(it) }, now, zone),
            dueCards = dueCount,
            dueFrom = dueFrom,
            topics = subjectStats(store),
            fresh = fresh,
            stations = stations,
            untried = situation?.untried ?: 0,
            secondsPerQuestion = track.secondsPerQuestion,
            stationMinutes = stationMinutes(track),
            mockMinutes = ExamWeekPlanner.paper(track).minutes,
        )
    }

    /** Minutes an OSCE station gets in this exam (iOS ExamTrack.stationMinutes). */
    fun stationMinutes(track: ExamTrack): Int = when (track) {
        ExamTrack.plab -> 8
        ExamTrack.mrcp -> 10
        ExamTrack.mrcs -> 9
        ExamTrack.usmle, ExamTrack.general -> 15
    }

    /**
     * The days anything was studied, `yyyy-MM-dd`: answers checked and cards
     * rated (StudyLog's days, from what Android keeps), and the days a ward
     * round's focus minutes were sat, which count for the streak too.
     */
    fun studyDays(store: StudyStore, zone: ZoneId = ZoneId.systemDefault(),
                  minutes: Map<String, Int> = StudyMinutes.all()): Map<String, Int> {
        val dates = store.answerLog.map { Instant.ofEpochMilli(it.at) } +
            store.reviews.values.filter { it.reviews > 0 }.map { Instant.ofEpochMilli(it.ratedAt) }
        val days = RhythmReading.merged(emptyMap(), dates, zone).toMutableMap()
        for ((day, count) in minutes) if (count > 0 && (days[day] ?: 0) == 0) days[day] = 1
        return days
    }

    fun streak(days: Map<String, Int>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Int =
        StudyStreak.summary(days.filter { it.value > 0 }.keys, now, zone).streak

    /** The brain map's numbers: the notes, and the links between them (as the Ideas page counts them). */
    fun brainMap(store: StudyStore): Pair<Int, Int> {
        val ids = store.notes.map { it.id }.toSet()
        return store.notes.size to store.notes.sumOf { note -> note.links.count { it in ids && it != note.id } }
    }

    /**
     * Up to [limit] questions from one subject, the ones being missed first:
     * those got wrong while sure, then those whose last answer was wrong,
     * then those ever got wrong, then those never tried, and only then the
     * ones always got right (Store.drill), as a quiz not saved anywhere.
     */
    fun drill(store: StudyStore, subject: String, limit: Int = 20): StudySet {
        val confident = store.confidentMistakeIds
        val groups = List(5) { mutableListOf<Pair<StudySet, com.stethoscore.app.data.MCQQuestion>>() }
        val seen = HashSet<String>()
        for (set in store.library) if (set.kind == StudySetKind.MCQ && subjectName(set) == subject) for (q in set.questions) {
            if (!seen.add(q.id)) continue
            val past = store.answerHistory[q.id].orEmpty()
            val at = when {
                q.id in confident -> 0
                past.lastOrNull() == false -> 1
                false in past -> 2
                past.isEmpty() -> 3
                else -> 4
            }
            groups[at].add(set to q)
        }
        val chosen = groups.flatMap { it.shuffled() }.take(limit).shuffled()
        // each set's pictures copied in once, the questions' picture numbers moved along to match
        val images = mutableListOf<String>()
        val bases = HashMap<String, Int>()
        val questions = chosen.map { (set, q) ->
            val i = q.imageIndex ?: return@map q
            if (i !in set.images.indices) return@map q.copy(imageIndex = null)
            val base = bases.getOrPut(set.id) { images.size.also { images.addAll(set.images) } }
            q.copy(imageIndex = i + base)
        }
        return StudySet(name = "Drill – $subject", subject = subject, kind = StudySetKind.MCQ, questions = questions, images = images)
    }
}
