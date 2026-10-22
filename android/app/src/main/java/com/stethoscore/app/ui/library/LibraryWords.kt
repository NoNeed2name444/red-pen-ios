package com.stethoscore.app.ui.library

import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.LibraryStats
import com.stethoscore.app.data.QuestionPick
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.MistakeReason

// The library's words, each a port of its iOS source: StudyCategory and
// CategoryFeature (Features/Library/StudyCategory.swift), NewSetStep and the
// New set paths (NewSetView.swift), and StatsView's small formatters. Plain
// Kotlin, so the screens and their tests read the same strings.

/** The five kinds of studying in the dock (iOS StudyCategory); [title] is the dock's word. */
enum class StudyCategory(val title: String) {
    QUESTIONS("Questions"), CARDS("Cards"), CASES("Cases"), OSCE("OSCE"), AUDIO("Audio");

    /** The kinds of set that live here, the main one first. */
    val kinds: List<StudySetKind> get() = when (this) {
        QUESTIONS -> listOf(StudySetKind.MCQ)
        CARDS -> listOf(StudySetKind.ANKI, StudySetKind.BOOK)
        CASES -> listOf(StudySetKind.CASES)
        OSCE -> listOf(StudySetKind.OSCE)
        AUDIO -> listOf(StudySetKind.NARRATE)
    }

    /** The kind "New set" starts on from here. */
    val mainKind: StudySetKind get() = kinds.first()

    /** The heading over this category's sets. */
    val setsHeading: String get() = when (this) {
        QUESTIONS -> "Your sets"
        CARDS -> "Your decks and books"
        CASES -> "Your patients"
        OSCE -> "Your OSCE stations"
        AUDIO -> "Your lectures"
    }

    /** Said where the sets would be, when there are none yet. */
    val emptySets: String get() = when (this) {
        QUESTIONS -> "No question sets yet."
        CARDS -> "No flashcards or books yet."
        CASES -> "No patients yet."
        OSCE -> "No OSCE stations yet."
        AUDIO -> "No lectures yet."
    }

    /** The tiles under one small heading, of those Android has. */
    fun features(group: FeatureGroup): List<CategoryFeature> = when (group) {
        FeatureGroup.MODES -> when (this) {
            QUESTIONS -> listOf(CategoryFeature.MULTIPLE_CHOICE)
            CARDS -> listOf(CategoryFeature.FLASHCARDS, CategoryFeature.TEXTBOOKS, CategoryFeature.PICTURES)
            CASES -> listOf(CategoryFeature.PATIENTS)
            OSCE -> listOf(CategoryFeature.STATIONS)
            AUDIO -> listOf(CategoryFeature.LECTURES)
        }
        FeatureGroup.PRACTISE -> when (this) {
            QUESTIONS -> listOf(CategoryFeature.MIXED, CategoryFeature.MISTAKES, CategoryFeature.FLAGGED, CategoryFeature.TIMED,
                CategoryFeature.WEAKEST, CategoryFeature.CONFIDENT, CategoryFeature.SLOW, CategoryFeature.ONE)
            CARDS -> emptyList()
            else -> emptyList()
        }
        FeatureGroup.TOOLS -> when (this) {
            QUESTIONS -> listOf(CategoryFeature.SUBJECTS, CategoryFeature.ADD)
            CARDS, OSCE, AUDIO -> listOf(CategoryFeature.ADD)
            CASES -> emptyList()
        }
    }

    companion object {
        /** Where a set of this kind lives. */
        fun of(kind: StudySetKind): StudyCategory = when (kind) {
            StudySetKind.MCQ -> QUESTIONS
            StudySetKind.ANKI, StudySetKind.BOOK -> CARDS
            StudySetKind.OSCE -> OSCE
            StudySetKind.NARRATE -> AUDIO
            StudySetKind.CASES -> CASES
        }

        /** The category the dock's word names; Questions for anything else. */
        fun named(title: String): StudyCategory = entries.firstOrNull { it.title == title } ?: QUESTIONS
    }
}

/** The three small headings a category's tiles sit under. */
enum class FeatureGroup(val title: String) { MODES("Modes"), PRACTISE("Practise"), TOOLS("Tools") }

/** The tiles on a category's page that Android has (iOS CategoryFeature). */
enum class CategoryFeature(val rawValue: String, val title: String, val detail: String) {
    MULTIPLE_CHOICE("multipleChoice", "Multiple choice", "Exam-style questions"),
    FLASHCARDS("flashcards", "Flashcards", "Cards that come back in time"),
    TEXTBOOKS("textbooks", "Textbooks", "Your lecture as pages"),
    PICTURES("pictures", "Picture cards", "Hide labels on a diagram"),
    STATIONS("stations", "OSCE stations", "Step-by-step checklists"),
    LECTURES("lectures", "Narrated lectures", "Read along with the lecture"),
    PATIENTS("patients", "Patient cases", "Work up, decide, debrief"),
    MIXED("mixed", "Mixed quiz", "20 across all your sets"),
    MISTAKES("mistakes", "My mistakes", "Last got wrong"),
    FLAGGED("flagged", "Flagged", "The ones you flagged"),
    TIMED("timed", "Timed exam", "10 against the clock"),
    WEAKEST("weakest", "Weakest topic", "Your lowest subject"),
    CONFIDENT("confident", "Sure but wrong", "Fix the misconceptions"),
    SLOW("slow", "Slow reading", "Key words marked, 15 s each"),
    ONE("one", "Just one", "A single question"),
    SUBJECTS("subjects", "By subject", "Your score in each subject"),
    DUE("due", "Due cards", "Cards waiting today"),
    ADD("add", "Paste or import", "Type, paste, or open Anki, Quizlet or CSV");

    /** The kind of set this mode's page lists, for the mode tiles. */
    val shelfKind: StudySetKind? get() = when (this) {
        MULTIPLE_CHOICE -> StudySetKind.MCQ
        FLASHCARDS, PICTURES -> StudySetKind.ANKI
        TEXTBOOKS -> StudySetKind.BOOK
        STATIONS -> StudySetKind.OSCE
        LECTURES -> StudySetKind.NARRATE
        PATIENTS -> StudySetKind.CASES
        else -> null
    }

    /** What "New ..." makes, on a mode's page. */
    val newNoun: String get() = when (this) {
        MULTIPLE_CHOICE -> "question set"
        FLASHCARDS -> "flashcard deck"
        TEXTBOOKS -> "textbook"
        PICTURES -> "picture card deck"
        STATIONS -> "OSCE station"
        LECTURES -> "narrated lecture"
        PATIENTS -> "Cases set"
        else -> "set"
    }

    /** Said when a quiz tile has nothing to build from. */
    val emptyText: String get() = when (this) {
        DUE -> "No cards are due right now. Come back later."
        FLAGGED -> "Flag a question while you answer it and it will wait here."
        MISTAKES, CONFIDENT -> "Answer a few questions first. Anything you get wrong comes back here."
        SLOW -> "When you get one wrong, tap “Misread the question” under it and it comes back here, to read slowly."
        else -> "Make a question set first."
    }

    /** Every set of this mode, newest first; picture cards only the decks with one. */
    fun shelfSets(library: List<StudySet>): List<StudySet> {
        val kind = shelfKind ?: return emptyList()
        val all = library.filter { it.kind == kind }
        val kept = if (this == PICTURES) all.filter { set -> set.cards.any { it.type == AnkiCardType.OCCLUSION } } else all
        return kept.sortedByDescending { it.updatedAt }
    }

    /** A mode tile's line: how many sets, or the feature's own line. */
    fun tileDetail(library: List<StudySet>): String {
        if (shelfKind == null) return detail
        val count = shelfSets(library).size
        if (count == 0) return "None yet — tap to make one"
        return if (count == 1) "1 set" else "$count sets"
    }

    /** The quiz this tile opens, built now; null for a tile that is not a quiz. */
    fun quiz(store: StudyStore): LibraryQuiz? = when (this) {
        MIXED -> LibraryQuiz(LibraryStats.temporaryQuiz("Mixed quiz", "Mixed", LibraryStats.mcqPicks(store).shuffled().take(20)))
        MISTAKES -> {
            val wrong = LibraryStats.mcqPicks(store) { store.answerHistory[it.question.id]?.lastOrNull() == false }
            LibraryQuiz(LibraryStats.temporaryQuiz("My mistakes", "Mistakes", wrong.shuffled().take(20)))
        }
        FLAGGED -> LibraryQuiz(LibraryStats.temporaryQuiz("Flagged questions", "Flagged",
            LibraryStats.mcqPicks(store) { it.question.id in store.flagged }.shuffled()))
        TIMED -> LibraryQuiz(LibraryStats.timedDrill(store), timed = true)
        WEAKEST -> {
            val stats = LibraryStats.subjectStats(store)
            (stats.firstOrNull { it.answered > 0 } ?: stats.firstOrNull())?.let { LibraryQuiz(LibraryStats.drill(store, it.subject)) }
        }
        CONFIDENT -> LibraryQuiz(LibraryStats.confidentMistakesQuiz(store))
        SLOW -> LibraryQuiz(LibraryStats.reasonQuiz(store, MistakeReason.misread, "Slow reading drill"), minReadSeconds = 15)
        ONE -> LibraryQuiz(LibraryStats.temporaryQuiz("One question", "One question", LibraryStats.mcqPicks(store).shuffled().take(1)))
        else -> null
    }

    val isQuiz: Boolean get() = this in setOf(MIXED, MISTAKES, FLAGGED, TIMED, WEAKEST, CONFIDENT, SLOW, ONE)
}

/** A quiz put together on the spot, and how it is sat (iOS InsightQuiz). */
data class LibraryQuiz(val set: StudySet, val minReadSeconds: Int = 0, val timed: Boolean = false)

/** The New set sheet's three steps (iOS NewSetStep). */
enum class NewSetStep(val number: Int, val short: String, val question: String) {
    KIND(1, "Choose", "What do you want to make?"),
    MATERIAL(2, "Add", "Add your lecture"),
    MAKE(3, "Make", "Make it");
}

/** The ways to bring material in (iOS NewSetView.Path). */
enum class NewSetPath(val title: String, val blurb: String) {
    LECTURE("From a lecture file", "A PDF, Word or PowerPoint file — or notes you paste"),
    TYPE("Type or paste", "Write the questions or cards yourself"),
    IMPORT_FILE("Open a file", "An Anki deck, a Quizlet or CSV table, or a shared set");
}

object NewSetWords {
    /**
     * The paths a kind offers. iOS offers From a lecture file first for every
     * kind but Narrate; its writers come with batch 6 (MCQGenerateForm,
     * LectureWriterSection), so here it is left out until then.
     */
    fun paths(kind: StudySetKind): List<NewSetPath> = when (kind) {
        StudySetKind.NARRATE -> listOf(NewSetPath.TYPE, NewSetPath.IMPORT_FILE)
        StudySetKind.CASES -> listOf(NewSetPath.IMPORT_FILE)
        else -> listOf(NewSetPath.TYPE, NewSetPath.IMPORT_FILE)
    }

    fun plainName(kind: StudySetKind): String = when (kind) {
        StudySetKind.MCQ -> "Practice questions (MCQ)"
        StudySetKind.ANKI -> "Flashcards"
        StudySetKind.BOOK -> "Textbook"
        StudySetKind.OSCE -> "OSCE checklists"
        StudySetKind.NARRATE -> "Narrate"
        StudySetKind.CASES -> "Patient cases"
    }

    fun blurb(kind: StudySetKind): String = when (kind) {
        StudySetKind.MCQ -> "Multiple-choice questions, like the exam"
        StudySetKind.ANKI -> "Cards that come back just before you forget"
        StudySetKind.BOOK -> "Your lecture as easy pages to read"
        StudySetKind.OSCE -> "Step-by-step checklists for practical exams"
        StudySetKind.NARRATE -> "Your lecture written out to read along"
        StudySetKind.CASES -> "Patients to work up against the clock"
    }

    fun formatHelp(kind: StudySetKind): String = when (kind) {
        StudySetKind.MCQ -> "One question per line: Stem | OptA; OptB; OptC; OptD | correctLetter | Explanation. A table pasted from a spreadsheet works too: Question, A, B, C, D, Answer."
        StudySetKind.ANKI -> "One card per line: Front | bullet1; bullet2 | why (optional). A table pasted from Quizlet or a spreadsheet works too: term, tab, definition."
        StudySetKind.BOOK -> "Markdown. Every # or ## heading starts a new page."
        StudySetKind.OSCE -> "## Station title, then one step per line. Blank line or the next ## starts a new station."
        StudySetKind.NARRATE -> "One line per phrase. Prefix with \"ar|\" for Arabic reading pace, otherwise it reads at English pace."
        StudySetKind.CASES -> "Cases are written from a lecture file, or come in a set shared from another phone."
    }

    fun saveTitle(kind: StudySetKind): String = "Save ${kind.label} set"

    /** What one item of [kind] is called, for the readiness line. */
    fun noun(kind: StudySetKind): String = when (kind) {
        StudySetKind.MCQ -> "question"
        StudySetKind.ANKI -> "card"
        StudySetKind.BOOK -> "page"
        StudySetKind.OSCE -> "station"
        StudySetKind.NARRATE -> "line"
        StudySetKind.CASES -> "patient"
    }

    /** The line under Save: how much is ready, or what is missing. */
    fun readiness(kind: StudySetKind, count: Int, name: String): String {
        if (count == 0) return "Nothing readable yet — open “How to lay it out” to see what each line needs."
        val plural = if (count == 1) "" else "s"
        val ready = "$count ${noun(kind)}$plural ready."
        if (name.trim().isEmpty()) return "$ready Give the set a name to save it."
        return ready
    }

    /** The dock's hint while the material step cannot go on. */
    fun dockHint(step: NewSetStep, path: NewSetPath, canGoOn: Boolean): String? {
        if (step != NewSetStep.MATERIAL || path == NewSetPath.IMPORT_FILE || canGoOn) return null
        if (path == NewSetPath.TYPE) return "Type or paste something first"
        return "Add a lecture file or paste your notes first"
    }

    /** The note when a shared set came without some of its pictures. */
    fun missingPictures(count: Int): String {
        val plural = if (count == 1) "" else "s"
        return "$count picture$plural had not finished downloading on the phone this came from, so the picture cards that needed them were left out. Ask for the set again once that phone has synced to get them."
    }
}

/** StatsView's small formatters. */
object StatsWords {
    fun percent(fraction: Double): String = "${Math.round(fraction * 100).toInt()}%"
    fun counted(count: Int, noun: String): String = "$count $noun${if (count == 1) "" else "s"}"
    fun drillNote(subject: String): String =
        "Up to 20 questions from $subject: the ones you got wrong while sure first, then the rest you got wrong last time."
}

