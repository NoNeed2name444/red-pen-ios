package com.stethoscore.app.quiz

import com.stethoscore.app.data.MCQAnswer
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet

// The results screen's sums, from ios/RedPen/Features/MCQ/MCQSummaryView.swift
// (the score, the verdict, which button leads, the Mistakes set's name) and
// Shared/SetPictures.swift (a Mistakes set topped up with each question's
// picture). Plain Kotlin, so QuizSummaryTest runs it on the JVM.
object QuizSummary {
    /**
     * Whether question [i] was answered right: checked, and the option chosen
     * (an index into the question's own options) is the key. The same test as
     * the running score and the answer history.
     */
    fun isRight(questions: List<MCQQuestion>, answers: List<MCQAnswer>, i: Int): Boolean {
        if (i !in answers.indices || i !in questions.indices) return false
        return answers[i].isCorrect(questions[i])
    }

    fun correctCount(questions: List<MCQQuestion>, answers: List<MCQAnswer>): Int = questions.indices.count { isRight(questions, answers, it) }

    fun fraction(correct: Int, total: Int): Double = if (total == 0) 0.0 else correct.toDouble() / total

    fun verdict(fraction: Double): String = when {
        fraction >= 0.9 -> "Excellent — exam ready."
        fraction >= 0.7 -> "Solid. A few to revisit."
        fraction >= 0.5 -> "Getting there — review the misses."
        else -> "Worth another pass before moving on."
    }

    /** The questions answered wrongly, for a set of their own; one re-tested in the same sitting is listed once. */
    fun mistakes(questions: List<MCQQuestion>, answers: List<MCQAnswer>): List<MCQQuestion> {
        val seen = HashSet<String>()
        return questions.indices.filter { !isRight(questions, answers, it) }.map { questions[it] }.filter { seen.add(it.id) }
    }

    /** "Mistakes – Cardiology": one per set, topped up each time. */
    fun mistakesName(setName: String): String = "Mistakes – " + setName.replace("Mistakes – ", "")

    /** The one big thing to do next: saving a quiz not yet in the library, then practising what went wrong, then Done. */
    enum class Next { save, practise, done }

    fun next(isUnsaved: Boolean, saved: Boolean, hasMistakes: Boolean, mistakesSaved: Boolean): Next = when {
        isUnsaved && !saved -> Next.save
        hasMistakes && !isUnsaved && !mistakesSaved -> Next.practise
        else -> Next.done
    }

    /**
     * [target] topped up with [questions] not already in it (by stem), each
     * with its picture: one already there is pointed at rather than copied
     * again. The source's documents come too, so citations still open.
     */
    fun addMistakes(target: StudySet, questions: List<MCQQuestion>, source: StudySet): StudySet {
        val images = target.images.toMutableList()
        val kept = target.questions.toMutableList()
        val known = kept.map { it.stem }.toMutableSet()
        for (q in questions) {
            if (q.stem in known) continue
            val picture = q.imageIndex?.let { source.images.getOrNull(it) }
            val at = picture?.let { p -> images.indexOf(p).takeIf { it >= 0 } ?: run { images += p; images.size - 1 } }
            kept += q.copy(imageIndex = at)
            known += q.stem
        }
        val sources = target.sources.toMutableList()
        for (doc in source.sources) if (sources.none { it.id == doc.id }) sources += doc
        return target.copy(questions = kept, images = images, sources = sources)
    }
}
