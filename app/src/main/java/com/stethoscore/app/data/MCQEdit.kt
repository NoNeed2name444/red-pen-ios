package com.stethoscore.app.data

// A port of upstream/ios/RedPen/Shared/MCQEdit.swift (fed0105): what editing a
// question is allowed to do to it. `correctIndex` is a POSITION, and every
// edit that removes an option shifts the positions after it, so the key is
// remembered by its place before anything moves and found again afterwards.
// Pure Kotlin (MCQEditTest: SlideTests' "editing without moving the answer").

object MCQEdit {

    /** Swift's `.whitespaces`: spaces and tabs, not line breaks. */
    private fun trimmedLine(text: String): String = text.trim { it.isWhitespace() && it != '\n' && it != '\r' && it != ' ' && it != ' ' }

    /**
     * Removing options. When the keyed option itself goes, nothing is marked
     * correct (`correctIndex` -1) until the student picks again; it is never
     * quietly moved to option A, and [tidied] will not save it so.
     */
    fun removing(offsets: Set<Int>, question: MCQQuestion): MCQQuestion {
        val keyed = question.correctIndex
        var moved = -1
        val kept = mutableListOf<String>()
        question.options.forEachIndexed { index, option ->
            if (index in offsets) return@forEachIndexed
            if (index == keyed) moved = kept.size
            kept += option
        }
        return question.copy(options = kept, correctIndex = moved)
    }

    /** Whether an option with words in it is marked correct. */
    fun hasKey(question: MCQQuestion): Boolean {
        if (question.correctIndex !in question.options.indices) return false
        return trimmedLine(question.options[question.correctIndex]).isNotEmpty()
    }

    /**
     * The question as it is saved: blank options dropped, the key moved with
     * its option. Null when it cannot be saved: fewer than two options with
     * words, or no option with words marked correct.
     */
    fun tidied(question: MCQQuestion): MCQQuestion? {
        var moved = -1
        val kept = mutableListOf<String>()
        question.options.forEachIndexed { index, option ->
            val trimmed = trimmedLine(option)
            if (trimmed.isEmpty()) return@forEachIndexed
            if (index == question.correctIndex) moved = kept.size
            kept += trimmed
        }
        if (kept.size < 2 || moved < 0) return null
        return question.copy(options = kept, correctIndex = moved)
    }
}
