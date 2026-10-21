package com.stethoscore.app.ui.mock

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Error
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.exam.ExamBlueprint
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.exam.ExamDomain
import com.stethoscore.app.exam.ExamMock
import com.stethoscore.app.exam.ExamMockEntry
import com.stethoscore.app.exam.TargetExam
import com.stethoscore.app.exam.papers
import com.stethoscore.app.quiz.MockRandom
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MockAssembler
import com.stethoscore.app.quiz.MockCandidate
import com.stethoscore.app.quiz.MockFormat
import com.stethoscore.app.quiz.MockMarking
import com.stethoscore.app.quiz.MockPaperSpec
import com.stethoscore.app.quiz.MockRecord
import com.stethoscore.app.quiz.MockRecords
import com.stethoscore.app.quiz.MockSectionSpec
import com.stethoscore.app.quiz.MockSittingSave
import com.stethoscore.app.quiz.MockSittingStore
import com.stethoscore.app.ui.QuizPrefs
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTile
import com.stethoscore.app.ui.ward.WardTileLabel
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import java.io.File
import java.text.DateFormat
import java.util.Date

// Port of upstream/ios/RedPen/Features/Mock/MockPaperView.swift.
//
// Questions → Practise → Mock paper: the real paper for the student's exam,
// its length and its clock, drawn from their own library. Says honestly when
// the library is too small to fill it.
//
// With an exam chosen (ExamChoice), the paper is that exam's: its papers and
// blocks, its clock, its pass mark and negative marking, and questions drawn
// in its blueprint's proportions (ExamMock); with none, the exam track's.
//
// Not ported: the accuracy holds that keep a question out (AccuracyHolds).

/** One question and the set it is in (iOS QuestionPick). */
data class QuestionPick(val set: StudySet, val question: MCQQuestion)

/** A paper ready to sit: its sections and their questions. */
data class MockSitting(
    val title: String,
    val specs: List<MockSectionSpec>,
    val picks: List<List<QuestionPick>>,
    val wanted: Int,
    val track: ExamTrack,
    /** The chosen exam's pass mark, when there is one. */
    val passMark: Double? = null,
    /** A wrong answer's cost against a right one's (MockMarking.penalty). */
    val penalty: Double = 0.0,
    val id: String = java.util.UUID.randomUUID().toString(),
)

/** The library's question picks, the subject names and the temporary quiz (iOS Store, StoreStudy.swift). */
internal object MockLibrary {
    /** Every MCQ question in the library that passes [keep], once per id. */
    fun mcqPicks(library: List<StudySet>, keep: (QuestionPick) -> Boolean = { true }): List<QuestionPick> {
        val seen = HashSet<String>()
        val out = ArrayList<QuestionPick>()
        for (set in library) {
            if (set.kind != StudySetKind.MCQ) continue
            for (question in set.questions) {
                if (question.id in seen) continue
                val pick = QuestionPick(set, question)
                if (!keep(pick)) continue
                seen.add(question.id)
                out.add(pick)
            }
        }
        return out
    }

    /** A set's subject as the Progress screen groups it: blank is "General". */
    fun subjectName(set: StudySet): String = set.subject.trim().ifEmpty { "General" }

    /** A quiz made on the spot from [picks], each question's picture carried over with its set's pictures. */
    fun temporaryQuiz(name: String, subject: String, picks: List<QuestionPick>): StudySet {
        val images = ArrayList<String>()
        val bases = HashMap<String, Int>()
        val questions = picks.map { pick ->
            val q = pick.question
            val i = q.imageIndex ?: return@map q
            if (i in pick.set.images.indices) {
                val base = bases.getOrPut(pick.set.id) { images.size.also { images.addAll(pick.set.images) } }
                q.copy(imageIndex = i + base)
            } else q.copy(imageIndex = null)
        }
        return StudySet(name = name, subject = subject, kind = StudySetKind.MCQ, questions = questions, images = images)
    }

    fun sittingFile(dir: File): File = MockSittingStore.defaultFile(dir)
    fun recordsFile(dir: File): File = MockRecords.defaultFile(dir)
}

/** "3 h", "1 h 40 min", "45 min". */
internal fun mockHours(minutes: Int): String {
    val h = minutes / 60
    val m = minutes % 60
    if (h == 0) return "$m min"
    return if (m == 0) "$h h" else "$h h $m min"
}

/** The Questions page's way in: Mock paper, "Your exam's real paper". */
@Composable
fun MockPaperTile(onOpen: () -> Unit, modifier: Modifier = Modifier) {
    WardTile(onOpen, modifier.fillMaxWidth().semantics { contentDescription = "Mock paper, Your exam’s real paper" }) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(vertical = 8.dp)) {
            WardTileLabel("Mock paper", Icons.Rounded.Description)
            Text("Your exam’s real paper", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}

@Composable
fun MockPaperScreen(store: StudyStore, onBack: () -> Unit) {
    val context = LocalContext.current
    val dir = context.filesDir
    val track = remember { QuizPrefs.track(context) }
    /** The chosen exam: its own papers, clock and blueprint, when there is one. */
    val target: TargetExam? = remember { ExamChoice.current(context) }
    val secondary: TargetExam? = remember { ExamChoice.currentSecondary(context) }
    var usmleBlocks by rememberSaveable { mutableIntStateOf(2) }
    var paperId by rememberSaveable { mutableStateOf("") }
    var sitting by remember { mutableStateOf<MockSitting?>(null) }
    var resuming by remember { mutableStateOf<MockSittingSave?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    /** A sitting left part way, offered to resume. */
    var saved by remember { mutableStateOf(MockSittingStore.load(MockLibrary.sittingFile(dir))) }
    val mocks = remember(revision) { MockRecords.load(MockLibrary.recordsFile(dir)) }

    val open = sitting
    if (open != null) {
        MockSittingScreen(open, store, resuming, onDone = {
            sitting = null
            resuming = null
            saved = MockSittingStore.load(MockLibrary.sittingFile(dir))
            revision++
        })
        return
    }

    val papers = if (target != null) MockFormat.papers(target, usmleBlocks) else MockFormat.papers(track, usmleBlocks)
    val paper = papers.firstOrNull { it.id == paperId } ?: papers[0]
    val pool = remember(revision) {
        MockLibrary.mcqPicks(store.library).map { MockCandidate(it.question.id, MockLibrary.subjectName(it.set)) }
    }
    val available = MockAssembler.dedupe(pool).size

    fun resume(save: MockSittingSave) {
        val byId = MockLibrary.mcqPicks(store.library).associateBy { it.question.id }
        val sections = save.questionIds.map { ids -> ids.mapNotNull { byId[it] } }
        if (sections.none { it.isNotEmpty() }) {
            MockSittingStore.clear(MockLibrary.sittingFile(dir))
            saved = null
            return
        }
        resuming = save
        sitting = MockSitting(save.title, save.specs, sections, save.wanted, ExamTrack.from(save.track), save.passMark,
            MockMarking.penalty(target?.negativeMarking))
    }

    /**
     * With an exam chosen, the paper's questions are drawn in its
     * blueprint's proportions (ExamMock), each question filed under the
     * area its set's subject or its stem is about.
     */
    fun weightedPool(spec: MockPaperSpec): List<MockCandidate> {
        val exam = target ?: return pool
        val plan = ExamBlueprint.plan(exam, secondary)
        val within = plan.map { it.domain }.toSet()
        val filed = MockLibrary.mcqPicks(store.library).map { pick ->
            val subject = MockLibrary.subjectName(pick.set)
            val domain: ExamDomain? = ExamBlueprint.domain(subject, within) ?: ExamBlueprint.domain(pick.question.stem, within)
            ExamMockEntry(MockCandidate(pick.question.id, subject), domain)
        }
        return ExamMock.select(filed, spec.questionCount, plan, MockRandom.system())
    }

    fun start() {
        val spec: MockPaperSpec = paper
        val made = MockAssembler.assemble(spec, weightedPool(spec)) ?: return
        val byId = MockLibrary.mcqPicks(store.library).associateBy { it.question.id }
        val sections = made.questionIds.map { ids -> ids.mapNotNull { byId[it] } }
        // a new paper replaces one left part way
        MockSittingStore.clear(MockLibrary.sittingFile(dir))
        saved = null
        resuming = null
        sitting = MockSitting(spec.title, made.sections, sections, made.wanted, track, target?.passMark,
            MockMarking.penalty(target?.negativeMarking))
    }


    BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        StudyTitleBar("Mock paper", onBack)
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.readableColumn().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)) {
                saved?.let { ResumeCard(it, { resume(it) }, { MockSittingStore.clear(MockLibrary.sittingFile(dir)); saved = null }) }
                // the exam, and how the paper is sat
                ContentCard(spacing = 6.dp) {
                    Text(target?.name ?: (if (track == ExamTrack.general) "General revision" else track.title),
                        style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk))
                    Text("Sit it like the real thing: the paper’s length and clock, and nothing about right or wrong until the end.",
                        style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                }
                PaperChoice(papers, paper, { paperId = it }, track, target, usmleBlocks, { usmleBlocks = it; paperId = "" })
                LibraryNote(available, paper, target)
                ContentCard(spacing = 8.dp) {
                    WardSectionLabel("How it runs")
                    listOf(
                        "The clock is strict: when a section’s time is up it closes, answered or not.",
                        "Flag and jump between questions within a section; a closed section can’t be reopened.",
                        "Cross out options, highlight the stem, and open lab values or the calculator from More.",
                        "Your score, by subject, comes at the end with every answer explained.",
                    ).forEach { line ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Rounded.Check, null, Modifier.size(18.dp), tint = wardColor(WardToken.primaryInk))
                            Text(line, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
                        }
                    }
                }
                if (mocks.isNotEmpty()) ContentCard(spacing = 10.dp) {
                    WardSectionLabel("Past sittings")
                    mocks.take(6).forEach { HistoryRow(it) }
                }
            }
        }
        StudyActionBar {
            BigButton("Start mock", Icons.Rounded.Timer, BigKind.primary, ::start, Modifier.fillMaxWidth(),
                enabled = available >= MockAssembler.minimumQuestions)
        }
    }
}

/** The sitting left part way: where it was, and the way back to it. */
@Composable private fun ResumeCard(save: MockSittingSave, onResume: () -> Unit, onDiscard: () -> Unit) {
    val part = if (save.onBreak) "between sections" else "section ${minOf(save.section + 1, save.specs.size)} of ${save.specs.size}"
    WardCardFace(Modifier.fillMaxWidth(), spacing = 10.dp) {
        Text("${save.title}, unfinished", style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
        Text("${save.answered} of ${save.total} answered, $part. The clock waits until you go back.",
            style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            WardButtonBox(onResume, kind = WardButtonKind.primary, fills = false) {
                Icon(Icons.Rounded.PlayArrow, null, Modifier.size(20.dp))
                Text("Resume")
            }
            WardButtonBox(onDiscard, kind = WardButtonKind.compact) {
                Text("Discard", color = wardColor(WardToken.danger))
            }
        }
    }
}

@Composable private fun PaperChoice(papers: List<MockPaperSpec>, paper: MockPaperSpec, onPaper: (String) -> Unit, track: ExamTrack,
                                    target: TargetExam?, blocks: Int, onBlocks: (Int) -> Unit) {
    ContentCard(spacing = 12.dp) {
        if (papers.size > 1) {
            var menu by remember { mutableStateOf(false) }
            Box {
                ChipBox(false, { menu = true }) {
                    Text(paper.title, style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
                    Icon(Icons.Rounded.ExpandMore, null, Modifier.size(18.dp), tint = wardColor(WardToken.primaryInk))
                }
                DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.raised)) {
                    papers.forEach { p ->
                        DropdownMenuItem(text = { Text(p.title) }, onClick = { menu = false; onPaper(p.id) },
                            leadingIcon = if (p.id == paper.id) ({ Icon(Icons.Rounded.Check, null) }) else null)
                    }
                }
            }
        } else {
            Text(paper.title, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
        }
        // a blockwise exam's blocks (USMLE, COMLEX, SMLE, IFOM), or the USMLE track's with no exam chosen
        val per = if (target != null && target.sitsBlockwise) target.sections.firstOrNull()?.questions ?: 40 else 40
        val most = when {
            target != null && target.sitsBlockwise -> maxOf(1, target.sections.size)
            target == null && track == ExamTrack.usmle -> MockFormat.usmleMaxBlocks
            else -> 0
        }
        if (most > 0) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("$blocks block" + (if (blocks == 1) "" else "s") + " of $per", Modifier.weight(1f),
                    style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                WardCircleButton(Icons.Rounded.Remove, "Fewer blocks", { onBlocks(blocks - 1) }, enabled = blocks > 1)
                Spacer(Modifier.width(8.dp))
                WardCircleButton(Icons.Rounded.Add, "More blocks", { onBlocks(blocks + 1) }, enabled = blocks < most)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Rounded.Timer, null, Modifier.size(18.dp), tint = wardColor(WardToken.primaryInk))
            Text("${paper.questionCount} questions · ${mockHours(paper.minutes)}",
                style = WardTextStyle.subheadline.textStyle(WardWeight.semibold).copy(fontFamily = FontFamily.Monospace),
                color = wardColor(WardToken.ink))
        }
        Text(paper.note, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}

@Composable private fun LibraryNote(available: Int, paper: MockPaperSpec, target: TargetExam?) {
    val wanted = paper.questionCount
    when {
        available < MockAssembler.minimumQuestions -> WardBanner(WardTone.Warning, Icons.Rounded.Warning,
            "A mock needs at least ${MockAssembler.minimumQuestions} questions in your library. Make a question set first.")
        available < wanted -> {
            val sections = MockAssembler.fitted(paper.sections, available)
            NoteCard(Icons.Rounded.Info, MockAssembler.shortfall(available, paper, sections))
        }
        else -> {
            val spread = target?.let { "weighted by the ${it.shortName} blueprint" } ?: "spread across your subjects"
            NoteCard(Icons.Rounded.CheckCircle, "Drawn from $available questions in your library, $spread.")
        }
    }
}

@Composable private fun NoteCard(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    ContentCard {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, null, Modifier.size(18.dp), tint = wardColor(WardToken.inkSecondary))
            Text(text, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}

@Composable private fun HistoryRow(record: MockRecord) {
    val percent = Math.round(record.fraction * 100).toInt()
    val whenText = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(record.date))
    val passed = record.fraction >= record.passMark
    val tone = if (passed) wardColor(WardToken.success) else wardColor(WardToken.warning)
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(record.title, style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
            Text("${record.correct} of ${record.total} · $whenText", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
        Icon(if (passed) Icons.Rounded.CheckCircle else Icons.Rounded.Error,
            if (passed) "Above the pass mark" else "Below the pass mark", tint = tone)
        Text("$percent%", style = WardTextStyle.body.textStyle(WardWeight.semibold, mono = true), color = tone)
    }
}
