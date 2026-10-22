package com.stethoscore.app.exam

import com.stethoscore.app.data.StudySetKind

// The words of the exam screens (iOS ExamPickerView.detail, ExamDashboardCard's
// percent, why and sourceNote, BlueprintBar's lines) and New set's presets
// from the exam and the Ward pocket (iOS NewSetPreset's blueprintArea and
// wardPocket initialisers). Pure Kotlin, so the screens only lay them out.

/** New set, ready to write questions on something the exam screens offer (iOS NewSetPreset). */
data class NewSetPreset(val kind: StudySetKind, val name: String, val subject: String, val notes: String) {
    companion object {
        /** New set, ready to write MCQs on one area of the chosen exam's blueprint. */
        fun blueprintArea(title: String, exam: TargetExam): NewSetPreset =
            NewSetPreset(StudySetKind.MCQ, "${exam.shortName}: $title", title,
                "Write ${exam.name} questions on $title, in its format and at its level.")

        /** New set, ready to write MCQs on one Ward pocket calculator or score. */
        fun wardPocket(title: String, notes: String): NewSetPreset =
            NewSetPreset(StudySetKind.MCQ, "Ward pocket: $title", title, notes)
    }
}

object ExamWords {
    /** "3 h", "1 h 40 min", "45 min" (iOS MockPaperView.hours). */
    fun hours(minutes: Int): String {
        val h = minutes / 60
        val m = minutes % 60
        if (h == 0) return "$m min"
        return if (m == 0) "$h h" else "$h h $m min"
    }

    /** The picker's line under an exam's name: "200 questions · 4 options · 3 h 30 min". */
    fun detail(exam: TargetExam): String {
        val q = exam.sections.sumOf { it.questions }
        val m = exam.sections.sumOf { it.minutes }
        val parts = arrayListOf("$q questions", "${exam.options} options", hours(m))
        if (!exam.formatConfirmed) parts.add("format unconfirmed")
        return parts.joinToString(" · ")
    }

    /** "T-23", "Today", or "No date" on the dashboard's pill. */
    fun countdown(days: Int?): String = days?.let { if (it <= 0) "Today" else "T-$it" } ?: "No date"

    fun percent(x: Double): String = "${swiftRounded(x * 100).toInt()}%"

    /** The dashboard's score line under the bar. */
    fun scoreLine(predicted: Double, passMark: Double, covered: Double): String =
        "Predicted ~${percent(predicted)} · pass mark ~${percent(passMark)} · blueprint covered ${percent(covered)}"

    /** "12% of the exam · 40% covered · 3 of 9 right". */
    fun why(s: BlueprintStanding): String {
        val parts = ArrayList<String>()
        if (s.area.percent > 0) parts.add("${swiftRounded(s.area.percent).toInt()}% of the exam")
        else parts.add("second exam")
        parts.add("${percent(s.coverage)} covered")
        if (s.answered > 0) parts.add("${s.correct} of ${s.answered} right")
        return parts.joinToString(" · ")
    }

    fun sourceNote(exam: TargetExam): String {
        val kind = if (exam.blueprintIsApproximate) "Approximate weights" else "Weights"
        return "$kind from ${exam.blueprintSource}. Readiness is an estimate from your own library and answers. ${exam.passNote}"
    }

    /** BlueprintBar's share: "12%". */
    fun share(s: BlueprintStanding): String = "${swiftRounded(s.area.percent).toInt()}%"

    /** BlueprintBar, read aloud. */
    fun spoken(s: BlueprintStanding): String =
        "${s.area.title}, ${share(s)} of the exam, ${percent(s.coverage)} covered, readiness ${percent(s.readiness)}"
}
