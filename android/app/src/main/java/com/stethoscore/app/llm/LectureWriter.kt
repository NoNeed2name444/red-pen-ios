package com.stethoscore.app.llm

import com.stethoscore.app.data.CardStyle
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.TextSlicing
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.reading.BookFigure
import com.stethoscore.app.reading.BookFigures
import com.stethoscore.app.reading.BookPages
import kotlinx.coroutines.withContext
import org.json.JSONArray
import kotlin.coroutines.coroutineContext

/**
 * Cards and textbook pages written from a lecture, through the writer route
 * only (LLMService.backend(); the owner, 23 Oct: "Lock it"). Port of iOS
 * Shared/LLM/LectureWriter.swift: the same prompts, in the line formats
 * PlainTextImport reads, so what a model writes and what a student types go
 * through one parser. With Stethoscore Cloud the server writes the whole set
 * as one job; any other backend is asked a batch at a time (BatchWriting).
 *
 * A cloud job keeps its recipe with it (CloudRecipe), so a run the app is
 * closed on is collected as these cards or this textbook: the screen's, when
 * it set one (a textbook's figures; the image occlusion cards that go with the
 * cards), else one made here from what the writer is given.
 */
object LectureWriter {

    /** What a run wrote, and what it could not. */
    data class Draft(
        /** The lines written, or a textbook's pages in order with a gap for each one missing. */
        val text: String,
        /** A textbook's pages by part, to fill their gaps on a second try. */
        val pages: Map<Int, String> = emptyMap(),
        /** What was not written; null when everything was, and always for a cloud job (the server's). */
        val shortfall: BatchWriting.Shortfall? = null,
    )

    /**
     * Writes [count] cards or pages. A second try at what a run left out:
     * [already], the draft's lines, never written again; for a textbook,
     * [parts], the pages to write of the [count] the lecture was cut into.
     */
    suspend fun draft(
        kind: StudySetKind, source: String, count: Int, subject: String, using: LLMBackend,
        figures: List<BookFigure> = emptyList(), style: CardStyle = CardStyle.mixed,
        exam: ExamTrack = ExamTrack.general,
        already: List<String> = emptyList(), parts: List<Int>? = null,
        store: CloudJobs.PendingStore = CloudJobs.store,
        pause: suspend (Long) -> Unit = { kotlinx.coroutines.delay(it) },
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Draft {
        if (kind == StudySetKind.BOOK) {
            return book(source, count, subject, using, figures, exam, parts, store, pause, onProgress)
        }
        val perCall = if (using.isOnDevice) 6 else 12
        // a long lecture is taken a window at a time, round and round
        val budget = maxOf(2_000, using.promptBudgetChars)
        val windows = if (source.length <= budget) listOf(source)
            else TextSlicing.slice(source, (source.length + budget - 1) / budget, budget).ifEmpty { listOf(source) }
        val cloud = CloudJobs.endpoint(using)
        if (cloud != null) {
            val cloudPerCall = 12
            val rounds = minOf(60, maxOf(windows.size, 1))
            val steps = (0 until rounds).map { r ->
                CloudJobs.Step(cardPrompt(cloudPerCall, subject, listOf("{{ALREADY}}"), "{{SOURCE}}", style),
                    "Write the $cloudPerCall lines now.", r % windows.size, 160 * cloudPerCall, 0.6)
            }
            val spec = CloudJobs.Spec(
                title = "Writing $count cards", mode = "loop", extract = "lines", count = count,
                sources = windows, steps = steps, minFields = 2, keyFields = 1, cloze = kind == StudySetKind.ANKI,
                patience = minOf(12, maxOf(3, windows.size + 2)), perReply = cloudPerCall,
            )
            val replies = withRecipe(CloudRecipe(kind, "", subject, count)) {
                CloudJobs.run(spec, cloud, store, pause = pause, onProgress = onProgress)
            }
            val collected = collectLines(replies, kind, count)
            if (collected.isEmpty()) throw LLMError.EmptyReply()
            return Draft(collected.joinToString("\n"))
        }
        val earlier = already.map { it.trim() }.filter { it.isNotEmpty() }
        val seen = earlier.map { it.lowercase() }.toMutableSet()
        val run = BatchWriting.items(count, perCall, maxOf(3, windows.size + 2),
            pause = { n -> if (!using.isOnDevice) pause(BatchWriting.waitMillis(n)) }, onProgress = onProgress) { round, batch, written ->
            val promptSource = windows[(round - 1) % windows.size]
            // what has been written: each line's first field
            val asked = (earlier + written).map { it.split("|").first().trim().take(140) }
            val prompt = cardPrompt(batch, subject, asked, promptSource, style)
            val reply = using.complete(listOf(ChatTurn.system(prompt), ChatTurn.user("Write the $batch lines now.")), 160 * batch, 0.6)
            freshLines(reply, kind, seen)
        }
        // nothing at all: the failure itself, not "nothing usable"
        if (run.items.isEmpty()) throw run.lastError ?: LLMError.EmptyReply()
        return Draft(run.items.joinToString("\n"),
            shortfall = BatchWriting.shortfall(count, run.items.size, run.tally))
    }

    fun cardPrompt(count: Int, subject: String, already: List<String>, source: String, style: CardStyle = CardStyle.mixed): String {
        val qa = "Question cards, one per line, exactly: Front | answer point 1; answer point 2 | why it matters (optional). The front is a question; answers are one to three short points; wrap the single tested word or number in **double asterisks**."
        val cloze = "Cloze cards, one per line, exactly: one sentence stating the fact with the tested word or number hidden as {{c1::that word}} | why it matters (optional). Hide the one thing worth remembering, never a filler word; one hidden part per card."
        val rules = mutableListOf("Write $count flashcards for a medical student revising ${subject.ifEmpty { "medicine" }}. One fact per card.")
        when (style) {
            CardStyle.qa -> rules += qa
            CardStyle.cloze -> rules += cloze
            CardStyle.mixed, CardStyle.image -> rules += listOf("Mix the two kinds, about half each:", "- $qa", "- $cloze")
        }
        rules += listOf("Use only what the source supports.", "No numbering, no headings, no blank lines, nothing but the lines.")
        if (already.isNotEmpty()) {
            rules += "Already written - do not repeat these:"
            rules += already.takeLast(60).map { "- $it" }
        }
        return (rules + listOf("", "SOURCE:", source)).joinToString("\n")
    }

    private val listMark = Regex("""^(\d+[.)]|[-*•])\s*""")

    /** A reply's usable lines that are new against [seen] and within this reply; a cloze line needs no second field. */
    fun freshLines(reply: String, kind: StudySetKind, seen: MutableSet<String>): List<String> =
        reply.split("\n").map { it.trim() }.map { it.replace(listMark, "") }.filter { line ->
            (line.split("|").size >= 2 || (kind == StudySetKind.ANKI && line.contains("{{c"))) && seen.add(line.lowercase())
        }

    /** The lines of a cloud job's replies, as the batch loop would have kept them. */
    fun collectLines(replies: List<String>, kind: StudySetKind, count: Int): List<String> {
        val seen = mutableSetOf<String>()
        return replies.flatMap { freshLines(it, kind, seen) }.take(count)
    }

    /** A cloud job's pages, tidied, each with its figures placed. */
    fun assembleBook(replies: List<String>, placement: List<List<Int>>): String =
        replies.mapIndexed { i, reply -> BookPages.tidyPage(reply, "Part ${i + 1}", placement.getOrElse(i) { emptyList() }) }
            .joinToString("\n\n")

    /**
     * Runs a cloud job with its recipe set, so a run the app is closed on is
     * collected as the set it was for (CloudJobCollector): the screen's own,
     * when it set one around this call, else [fallback]. The screen's
     * delivery, if any, is kept.
     */
    private suspend fun <T> withRecipe(fallback: CloudRecipe, work: suspend () -> T): T {
        val outer = coroutineContext[CloudJobs.Context]
        return withContext(CloudJobs.Context(outer?.recipe ?: fallback.json(), outer?.delivery)) { work() }
    }

    /** A textbook, a page at a time from its own slice of the lecture, so a long lecture is covered end to end. */
    suspend fun book(
        source: String, pages: Int, subject: String, using: LLMBackend,
        figures: List<BookFigure> = emptyList(), exam: ExamTrack = ExamTrack.general, parts: List<Int>? = null,
        store: CloudJobs.PendingStore = CloudJobs.store,
        pause: suspend (Long) -> Unit = { kotlinx.coroutines.delay(it) },
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Draft {
        val slices = TextSlicing.slice(source, pages, using.promptBudgetChars)
        val placement = BookFigures.assign(figures, slices)
        fun mine(i: Int): List<Int> = placement.getOrElse(i) { emptyList() }
        val cloud = CloudJobs.endpoint(using)
        if (cloud != null) {
            val steps = slices.indices.map { i ->
                CloudJobs.Step("", bookPrompt("{{SOURCE}}", subject, exam, mine(i).map { it to figures[it] }), i, 3_000, 0.3)
            }
            val spec = CloudJobs.Spec("Writing ${slices.size} textbook pages", "each", "pages", slices.size, slices, steps)
            val extra = JSONArray(placement.map { JSONArray(it) }).toString()
            // the figures go with the job, in the order the placement counts them, so the
            // textbook is still made with its pictures if the app is closed first
            val recipe = CloudRecipe(StudySetKind.BOOK, "", subject, pages, figures = figures.map { it.imageBase64 })
            val replies = withRecipe(recipe) {
                CloudJobs.run(spec, cloud, store, pause = pause, onProgress = onProgress, extra = extra)
            }
            if (replies.isEmpty()) throw LLMError.EmptyReply()
            return Draft(assembleBook(replies, placement))
        }
        // every page, or only the ones a run before this one left out
        val wanted = (parts ?: slices.indices.toList()).filter { it in slices.indices }
        val run = BatchWriting.pages(wanted, 3,
            pause = { n -> if (!using.isOnDevice) pause(BatchWriting.waitMillis(n)) }, onProgress = onProgress) { i ->
            val prompt = bookPrompt(slices[i], subject, exam, mine(i).map { it to figures[it] })
            val reply = using.complete(listOf(ChatTurn.user(prompt)), if (using.isOnDevice) 1_600 else 3_000, 0.3)
            BookPages.tidyPage(reply, "Part ${i + 1}", mine(i))
        }
        if (run.pages.isEmpty()) throw run.lastError ?: LLMError.EmptyReply()
        val text = wanted.joinToString("\n\n") { run.pages[it] ?: BatchWriting.gap(it) }
        return Draft(text, run.pages,
            BatchWriting.shortfall(wanted.size, run.pages.size, run.tally, run.missing))
    }

    fun bookPrompt(source: String, subject: String, exam: ExamTrack, figures: List<Pair<Int, BookFigure>>): String {
        val lines = mutableListOf(
            "You are writing one page of a medical revision textbook for medical students${if (subject.isEmpty()) "" else " studying $subject"}${if (exam == ExamTrack.general) "" else ", preparing for ${exam.title}"}.",
            "Turn the source below into that page, in Markdown, laid out like a good clinical textbook chapter.",
            "",
            "LAYOUT",
            "- The first line is the page title: exactly one \"## \" heading naming the topic. Every other heading uses \"### \".",
            "- Then these sections, in this order, but ONLY the ones the source actually covers: ### Definition, ### Epidemiology, ### Causes and risk factors, ### Pathophysiology, ### Clinical features, ### Investigations, ### Diagnosis, ### Differential diagnosis, ### Management, ### Complications, ### Prognosis. A topic that is not a disease (anatomy, a drug, a procedure) uses the headings that fit it instead.",
            "- Short paragraphs and bullet lists. Bold the terms a student must remember. Clinical features as bullets, the classic ones in bold. Investigations: first-line first, and name the gold standard. Management stepwise: first-line, then second-line, then when to escalate or refer.",
            "",
            "VISUAL AIDS - use them wherever they make the topic clearer:",
            "- A table (header row, then a |---| line, then the rows) for any comparison: types or classifications, differentials (| Condition | Key distinguishing feature |), drug classes, staging.",
            "- A flowchart for any pathway: a diagnostic work-up, a management algorithm, or a cause-to-effect cascade. Write it as a fenced block that starts with ```flow, one step per line, a branch as \"If ... → ...\", and ends with ```.",
            "- Callout lines where they earn their place: \"> **Key point:** ...\", \"> **Exam tip:** ...\", \"> **Red flag:** ...\", \"> **Mnemonic:** ...\".",
        )
        if (figures.isNotEmpty()) {
            lines += "- These diagrams from the lecture belong on this page. Put each one on its own line where it fits the text, exactly as ![a one-line caption saying what it shows](image:N):"
            lines += figures.map { (index, figure) ->
                "  - image:$index${figure.page?.let { " (page $it)" } ?: ""} labelled: ${figure.labels.take(12).joinToString(", ")}"
            }
        }
        lines += listOf(
            "",
            "ACCURACY",
            "- Every fact, number, dose and threshold must come from the source. Do not add drugs, doses, criteria or statistics it does not give.",
            "- You may explain in plain words how the source's facts connect (why a mechanism causes a finding), but add no new facts.",
            "- Where the source is unclear, keep its meaning rather than guessing.",
            "- No introduction, no closing remarks, no notes to the reader - just the page.",
            "",
            "SOURCE:",
            source,
        )
        return lines.joinToString("\n")
    }
}
