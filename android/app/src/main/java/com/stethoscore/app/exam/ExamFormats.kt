package com.stethoscore.app.exam

import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MockCandidate
import com.stethoscore.app.quiz.MockFormat
import com.stethoscore.app.quiz.MockPaperSpec
import com.stethoscore.app.quiz.MockRandom
import com.stethoscore.app.quiz.MockSectionSpec
import com.stethoscore.app.quiz.PassMark

// A port of ios/RedPen/Shared/Exam/ExamFormats.swift: the chosen
// exam's paper - the mock paper's sections and clock, the exam-day kit's
// pacing, and a mock drawn in the blueprint's proportions. Kept apart from
// quiz/MockPaper.kt and data/BedPlan.kt so those stay as they were for a
// student with no exam chosen. Pure Kotlin (ExamCatalogTest).

/**
 * The papers an exam offers. A blockwise exam (USMLE, COMLEX, SMLE, IFOM) is
 * sat as the number of blocks chosen; one whose sections are sat apart (MRCP's
 * two papers, MRCS A, FMGE's parts) offers each on its own; anything else is
 * one paper.
 */
fun MockFormat.papers(exam: TargetExam, blocks: Int = 2): List<MockPaperSpec> {
    if (exam.sections.isEmpty()) return emptyList()
    if (exam.sitsBlockwise) {
        val n = minOf(maxOf(blocks, 1), exam.sections.size)
        val chosen = exam.sections.take(n)
        val unit = chosen[0].title.split(" ").filter { it.isNotEmpty() }.dropLast(1).joinToString(" ").lowercase()
        val noun = unit.ifEmpty { "block" }
        return listOf(MockPaperSpec("${exam.id}-$n", "${exam.shortName}, $n $noun" + (if (n == 1) "" else "s"), chosen, exam.paperNote))
    }
    if (exam.sitsSeparately) {
        return exam.sections.mapIndexed { i, section ->
            MockPaperSpec("${exam.id}-p${i + 1}", "${exam.shortName}, ${section.title}", listOf(section), exam.paperNote)
        }
    }
    return listOf(MockPaperSpec(exam.id, "${exam.shortName} paper", exam.sections, exam.paperNote))
}

/**
 * The paper the exam-day kit paces (iOS's ExamWeekPlanner.Paper).
 * [published]: the exam's own format rather than a pace from its track.
 */
data class ExamPaper(val name: String, val questions: Int, val minutes: Int, val published: Boolean)

/**
 * The paper the exam-day kit paces: one block of a blockwise exam, one paper
 * of one sat in parts, else the whole paper. "Published" only when the exam's
 * format is confirmed.
 */
fun ExamWeekPlanner.paper(exam: TargetExam): ExamPaper {
    val first = exam.sections.firstOrNull() ?: MockSectionSpec(exam.shortName, 60, 60)
    if (exam.sitsBlockwise || exam.sitsSeparately) {
        return ExamPaper("${exam.shortName} ${first.title.lowercase()}", first.questions, first.minutes, exam.formatConfirmed)
    }
    return ExamPaper(exam.shortName, exam.sections.sumOf { it.questions }, exam.sections.sumOf { it.minutes }, exam.formatConfirmed)
}

/** The chosen exam's rough pass mark, or the track's. */
fun PassMark.typical(exam: TargetExam?, track: ExamTrack): Double = exam?.passMark ?: typical(track)

/** One question offered to [ExamMock.select], with the blueprint area it was filed under. */
data class ExamMockEntry(val candidate: MockCandidate, val domain: ExamDomain?)

/**
 * A mock drawn in the blueprint's proportions: each area gets its share of
 * the paper from the questions filed under it, an area the library is short on
 * gives its places to the others, and questions no area claims fill what is
 * left.
 */
object ExamMock {

    fun select(pool: List<ExamMockEntry>, wanted: Int, plan: List<BlueprintArea>, rng: MockRandom): List<MockCandidate> {
        val seen = HashSet<String>()
        // iOS keeps these in a Dictionary, whose order is the hash's; here the
        // order is the pool's, so a seeded draw is the same every run
        val byDomain = LinkedHashMap<ExamDomain, MutableList<MockCandidate>>()
        var loose = ArrayList<MockCandidate>()
        for (entry in pool) {
            if (!seen.add(entry.candidate.id)) continue
            val d = entry.domain
            if (d != null && plan.any { it.domain == d }) byDomain.getOrPut(d) { ArrayList() }.add(entry.candidate)
            else loose.add(entry.candidate)
        }
        for (key in byDomain.keys.toList()) byDomain[key] = rng.shuffled(byDomain.getValue(key)).toMutableList()
        loose = ArrayList(rng.shuffled(loose))
        val target = minOf(wanted, seen.size)
        val picked = ArrayList<MockCandidate>()
        // rounds of quotas: what one area cannot fill goes to the others
        var remaining = plan.filter { !byDomain[it.domain].isNullOrEmpty() }
        while (picked.size < target && remaining.isNotEmpty()) {
            val need = target - picked.size
            val quotas = ExamBlueprint.quotas(need, remaining)
            var progressed = false
            for (row in quotas) {
                val list = byDomain[row.area.domain] ?: mutableListOf()
                val take = minOf(row.questions, list.size)
                if (take > 0) {
                    picked.addAll(list.take(take))
                    byDomain[row.area.domain] = list.drop(take).toMutableList()
                    progressed = true
                }
            }
            remaining = remaining.filter { !byDomain[it.domain].isNullOrEmpty() }
            if (!progressed) break
        }
        if (picked.size < target) picked.addAll(loose.take(target - picked.size))
        return picked.take(target)
    }
}
