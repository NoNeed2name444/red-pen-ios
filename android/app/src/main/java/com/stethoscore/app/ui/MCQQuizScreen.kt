package com.stethoscore.app.ui

import android.content.Context
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.MCQAnswer
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.QuizProgress
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.*
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardChipButton
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardTimerPill
import com.stethoscore.app.ui.mock.StudyTitleBar
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardTypeSpec
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.llm.mcqStyle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

// A port of ios/RedPen/Features/MCQ/MCQQuizView.swift: the question
// screen. Pick an option, check it (the right one in the section's colour, a
// wrong pick faded grey), read the explanation, then Next question / See
// results. The same flow and words as iOS: resuming a saved place, the timed
// paper, crossing out, the highlighter, the attending's hint, Flag, How sure?,
// Why did you miss it?, and a re-test a few questions on. What each part
// says is decided, and tested, in quiz/ (ChartQuiz, OptionOrder, TwinRetest,
// SpokenText).
//
// Check accuracy is in the More menu (iOS studyMoreMenu, T0115b2), opening
// AccuracyWhySheet. Not here yet, because their batches have not come: the
// accuracy badge, Turn into, Report a problem, Save to Ideas, How to reach
// it (Reasoning), and the keyboard shortcuts. Android has no question writer,
// so the hint is always the attending's own (AttendingHint.fallback) and
// Write a twin writes one with the writer New set uses (TwinWriter), or
// says that none is set up.

/** Settings the question screen reads (iOS @AppStorage), from the app's one preferences file. */
internal object QuizPrefs {
    private fun prefs(context: Context) = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
    fun track(context: Context): ExamTrack = ExamTrack.from(prefs(context).getString(ExamTrack.storageKey, null))
    fun asksConfidence(context: Context): Boolean = prefs(context).getBoolean(ConfidenceSetting.key, true)
}

private fun <T> List<T>.replacing(i: Int, f: (T) -> T): List<T> = mapIndexed { j, v -> if (j == i) f(v) else v }

/** Keys at or past [slot] moved one along, for a question slotted in. */
private fun shifted(marks: Map<Int, Set<Int>>, slot: Int): Map<Int, Set<Int>> =
    marks.entries.associate { (key, value) -> (if (key >= slot) key + 1 else key) to value }

private fun letter(idx: Int): String = ('A' + idx).toString()

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun QuizScreen(
    set: StudySet, store: StudyStore, onBack: () -> Unit,
    /** Opens another set - the Mistakes set the results just made. */
    onOpen: (StudySet) -> Unit = {},
    /** False for a quiz put together on the spot, which has no place in the library to be resumed from. */
    keepsProgress: Boolean = true,
    /** Seconds each question must be on screen before it can be answered - the slow reading drill. */
    minReadSeconds: Int = 0,
    /** Opens straight into timed exam mode - the timed drill. */
    startsTimed: Boolean = false,
    /** A just-made set not in the library yet, with its own Save button. */
    isUnsaved: Boolean = false,
    onSave: (() -> Unit)? = null,
) {
    // a different set starts afresh
    key(set.id) { QuizBody(set, store, onBack, onOpen, keepsProgress, minReadSeconds, startsTimed, isUnsaved, onSave) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun QuizBody(set: StudySet, store: StudyStore, onBack: () -> Unit, onOpen: (StudySet) -> Unit, keepsProgress: Boolean,
                     minReadSeconds: Int, startsTimed: Boolean, isUnsaved: Boolean, onSave: (() -> Unit)?) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val track = remember { QuizPrefs.track(context) }
    val llm = com.stethoscore.app.ui.editors.rememberLLMService()
    val twinStyle = remember { com.stethoscore.app.exam.ExamChoice.currentTrack(com.stethoscore.app.exam.ExamChoice.defaults(context)).mcqStyle }
    val asksConfidence = remember { QuizPrefs.asksConfidence(context) }
    val readSeconds = maxOf(0, minReadSeconds)

    // Where the student is and what they chose live through a rotation, a fold
    // and a window resize, each of which recreates the activity (T0139): the
    // place, every answer, the option orders they were given, the marks, the
    // timed paper's end and the sheet that was open.
    var current by rememberSaveable { mutableIntStateOf(0) }
    var answers by rememberSaveable(stateSaver = StudySavers.answers) { mutableStateOf(List(set.questions.size) { MCQAnswer() }) }
    // per-question option order: displayed slot i shows the original option orders[q][i]
    var orders by rememberSaveable(stateSaver = StudySavers.orders) { mutableStateOf(set.questions.map { OptionOrder.make(it.options.size, shuffle = true) }) }
    var showSummary by rememberSaveable { mutableStateOf(false) }
    // the resume offer, asked once per quiz opened; on a rotation the offer itself is read again from the store
    var resumeAsked by rememberSaveable { mutableStateOf(false) }
    var pendingResume by rememberSaveable(stateSaver = Saver<QuizProgress?, Boolean>({ it != null }, { if (it) store.quizProgress[set.id] else null })) { mutableStateOf<QuizProgress?>(null) }
    var examMode by rememberSaveable { mutableStateOf(false) }
    var examEndsAt by rememberSaveable { mutableStateOf<Long?>(null) }
    var confidences by rememberSaveable(stateSaver = StudySavers.enumMap(AnswerConfidence::valueOf)) { mutableStateOf(mapOf<String, AnswerConfidence>()) }
    var reasons by rememberSaveable(stateSaver = StudySavers.enumMap(MistakeReason::valueOf)) { mutableStateOf(mapOf<String, MistakeReason>()) }
    var holding by remember { mutableStateOf(false) }
    // a re-test slotted in, kept as the questions' ids in order
    var reordered by rememberSaveable(stateSaver = Saver<List<MCQQuestion>?, ArrayList<String>>({ it?.mapTo(ArrayList()) { q -> q.id } },
        { ids -> val byId = set.questions.associateBy { it.id }; ids.map { byId[it] }.takeIf { all -> all.none { it == null } }?.filterNotNull() })) { mutableStateOf<List<MCQQuestion>?>(null) }
    var retested by rememberSaveable(stateSaver = StudySavers.stringSet) { mutableStateOf(setOf<String>()) }
    var struck by rememberSaveable(stateSaver = StudySavers.marks) { mutableStateOf(mapOf<Int, Set<Int>>()) }
    var highlights by rememberSaveable(stateSaver = StudySavers.marks) { mutableStateOf(mapOf<Int, Set<Int>>()) }
    var highlighting by rememberSaveable { mutableStateOf(false) }
    var toolSheet by rememberSaveable { mutableStateOf<ExamToolSheet?>(null) }
    // the Ward pocket (batch 16), from More while no timed exam runs
    var pocketOpen by rememberSaveable { mutableStateOf(false) }
    var hints by rememberSaveable(stateSaver = StudySavers.stringMap) { mutableStateOf(mapOf<String, String>()) }
    var twinNotes by rememberSaveable(stateSaver = StudySavers.stringMap) { mutableStateOf(mapOf<String, String>()) }
    var flagged by remember { mutableStateOf(store.flagged) }
    var saved by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    // the item Check accuracy shows (iOS StudyMoreMenu's verifying)
    var verifying by remember { mutableStateOf<com.stethoscore.app.accuracy.AccuracyItem?>(null) }
    // the set whose "Turn into…" picker is up (iOS StudyMoreMenu's turning)
    var turning by remember { mutableStateOf<StudySet?>(null) }

    if (set.questions.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(WardSpace.gutter.wardDp)) {
            ScreenHeader(ChartQuiz.title(set.subject, set.name), "", onBack)
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.QuestionMark, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(12.dp))
                Text("No questions", style = WardType.title.textStyle(), modifier = Modifier.semantics { heading() })
                Text("This set has no questions yet.", color = wardColor(WardToken.inkSecondary))
            }
        }
        return
    }

    val questions = reordered ?: set.questions
    // What Check accuracy looks at: the question on screen, and only once it
    // has been answered, because the check shows the answer (iOS MCQQuizView accuracyAsk)
    val accuracyAsk = AccuracyAsk("Write a single-best-answer medical exam question, with its answer and explanation, from the source.",
        item = { questions.getOrNull(current)?.let { com.stethoscore.app.accuracy.AccuracyItem.mcq(it) } }) {
        val q = questions.getOrNull(current)
        if (examMode || q == null || answers.getOrNull(current)?.checked != true) null
        else (listOf(q.stem) + q.options.mapIndexed { i, o -> "${letter(minOf(i, 5))}. $o" } +
            listOf("Answer: " + letter(q.correctIndex.coerceIn(0, 5)), "Explanation: " + q.explanation)).joinToString("\n")
    }
    if (current !in questions.indices) current = questions.lastIndex
    val q = questions[current]
    val a = answers.getOrElse(current) { MCQAnswer() }

    fun order(qi: Int): List<Int> = OptionOrder.valid(orders.getOrNull(qi), questions[qi].options.size)
    fun correctSlot(qi: Int): Int = OptionOrder.slot(questions[qi].correctIndex, order(qi)) ?: -1
    fun isRight(qi: Int): Boolean =
        qi in answers.indices && OptionOrder.isCorrect(answers[qi].selected, questions[qi].correctIndex, order(qi))
    fun optionText(qi: Int, slot: Int): String =
        OptionOrder.original(slot, order(qi))?.let { questions[qi].options.getOrNull(it) } ?: ""
    fun isRetest(index: Int): Boolean {
        if (reordered == null || index !in questions.indices) return false
        val id = questions[index].id
        return questions.take(index).any { it.id == id }
    }
    fun inLibrary(id: String): Boolean = store.library.any { s -> s.kind == StudySetKind.MCQ && s.questions.any { it.id == id } }

    // Whether persist() really writes: never for a quiz with no place in the
    // library, and never in exam mode (a timed paper is sat in one go).
    val keepsPosition = keepsProgress && !examMode
    fun forgetPlace() { if (keepsProgress) store.clearQuizProgress(set.id) }
    fun persist() {
        if (!keepsPosition) return
        // a re-test slotted in is left out, so the place saved is the set's own
        val kept = TwinRetest.collapse(questions.map { it.id }, answers, orders, current)
        store.saveQuizProgress(set.id, QuizProgress(kept.current, kept.answers, set.questions.map { it.id }, kept.orders))
    }
    // the answers to the set's own questions, in the options' own indices, re-tests taken out
    fun setAnswers(): List<MCQAnswer> {
        val original = answers.mapIndexed { qi, ans ->
            if (qi < questions.size) ans.copy(selected = OptionOrder.original(ans.selected, order(qi))) else ans
        }
        return TwinRetest.collapse(questions.map { it.id }, original, orders, 0).answers
    }

    // MARK: resume / retake
    LaunchedEffect(Unit) {
        if (resumeAsked) return@LaunchedEffect
        resumeAsked = true
        val p = store.quizProgress[set.id]
        if (keepsProgress && p != null && p.questionIds == set.questions.map { it.id }
            && p.optionOrders.size == set.questions.size && p.answers.size == set.questions.size
            && p.optionOrders.zip(set.questions).all { (o, sq) -> o.size == sq.options.size }
            && p.answers.any { it.checked }) pendingResume = p
    }
    fun resume(p: QuizProgress) {
        answers = p.answers; orders = p.optionOrders
        current = minOf(p.current, maxOf(0, set.questions.size - 1))
        pendingResume = null
    }
    fun startAgain() { forgetPlace(); pendingResume = null }
    fun retake() {
        answers = List(set.questions.size) { MCQAnswer() }
        orders = set.questions.map { OptionOrder.make(it.options.size, shuffle = true) }
        current = 0; examMode = false; examEndsAt = null
        confidences = emptyMap(); reasons = emptyMap(); reordered = null; retested = emptySet()
        struck = emptyMap(); highlights = emptyMap(); hints = emptyMap()
        forgetPlace()
    }

    // MARK: timed exam mode
    val canStartExam = !examMode && answers.none { it.checked }
    val examSeconds = track.secondsPerQuestion * set.questions.size
    fun startExam() {
        forgetPlace()
        pendingResume = null; examMode = true
        examEndsAt = System.currentTimeMillis() + examSeconds * 1000L
    }

    // MARK: checking
    fun commit(qi: Int): Boolean {
        answers = answers.replacing(qi) { it.copy(checked = true) }
        val right = isRight(qi)
        // a re-test answered right minutes after the miss is not recorded,
        // or it would wipe the miss from every follow-up queue
        if (!isRetest(qi)) {
            val question = questions[qi]
            store.recordAnswer(question.id, right, confidence = confidences[question.id]?.rawValue,
                picked = OptionOrder.original(answers[qi].selected, order(qi)),
                hinted = hints[question.id] != null, saving = !keepsPosition)
            // a twin answered here moves along its own queue (iOS ExamStore.twinAnswered); a mock paper's do not
            store.twinShelf.answered(question.id, right)
        }
        return right
    }
    fun finish() {
        forgetPlace()
        // the paper is over: coming back from the results shows the answers it was holding back
        examEndsAt = null; examMode = false; showSummary = true
    }
    fun handIn() {
        for (qi in answers.indices) if (!answers[qi].checked && answers[qi].selected != null) commit(qi)
        finish()
    }
    fun advance() { if (current < questions.size - 1) { current += 1; persist() } else finish() }
    fun announceResult(right: Boolean) {
        val slot = correctSlot(current)
        @Suppress("DEPRECATION")
        view.announceForAccessibility(SpokenText.answerResult(right, if (slot >= 0) letter(slot) else "", if (slot >= 0) optionText(current, slot) else ""))
    }
    fun onCheckOrNext() {
        if (examMode && !a.checked) {
            // a paper: one tap moves on, picked or skipped; the answer stays open until handed in
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            if (current < questions.size - 1) current += 1 else handIn()
            return
        }
        if (!a.checked) {
            val right = commit(current)
            haptic.performHapticFeedback(if (right) HapticFeedbackType.Confirm else HapticFeedbackType.Reject)
            announceResult(right)
            persist()
            return
        }
        advance()
    }

    // MARK: crossing out
    fun isStruck(slot: Int): Boolean = OptionOrder.original(slot, order(current))?.let { struck[current]?.contains(it) } ?: false
    fun toggleStrike(slot: Int) {
        if (a.checked) return
        val original = OptionOrder.original(slot, order(current)) ?: return
        val marks = struck[current] ?: emptySet()
        val on = original in marks
        struck = struck + (current to (if (on) marks - original else marks + original))
        if (!on && answers[current].selected == slot) answers = answers.replacing(current) { it.copy(selected = null) }
    }
    val struckTheAnswer = struck[current]?.contains(q.correctIndex) ?: false

    // MARK: the attending's hint
    val canHint = !a.checked && !examMode && pendingResume == null
    fun askHint() {
        if (hints[q.id] != null) return
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        val answer = q.options.getOrNull(q.correctIndex) ?: ""
        // Android has no question writer: the attending's own hint, from the reasoning when there is one
        hints = hints + (q.id to AttendingHint.fallback(answer, q.stem, q.options, DifferentialTiers.fromQuestionJson(q.rawJson)))
    }

    // MARK: fixing a miss
    fun insertRetest() {
        val question = q
        if (question.id in retested) return
        val slot = TwinRetest.slot(current, questions.size)
        reordered = questions.toMutableList().apply { add(slot, question) }
        answers = answers.toMutableList().apply { add(slot, MCQAnswer()) }
        orders = orders.toMutableList().apply { add(slot, OptionOrder.make(question.options.size, shuffle = true)) }
        struck = shifted(struck, slot); highlights = shifted(highlights, slot)
        retested = retested + question.id
        confidences = confidences - question.id
    }
    // Write a twin (T0133): the writer New set uses, or the no-writer line
    fun writeTwin() {
        val id = q.id
        if (id in twinNotes) return
        // one twin per miss: not while one is written or waiting for this question
        if (!store.twinShelf.canWrite(id)) { twinNotes = twinNotes + (id to TwinBook.alreadyOnTheWay); return }
        // sure but wrong as iOS decides it: the question's latest answer, wrong, said sure (confidentMistakeIds)
        val request = PendingTwin(id, OptionOrder.original(a.selected, order(current)), reasons[id]?.title,
            confident = id in store.confidentMistakeIds, guessed = confidences[id] == AnswerConfidence.guess)
        twinNotes = twinNotes + (id to "Writing a twin\u2026")
        scope.launch {
            val outcome = TwinWriter.write(request, store, llm.backend(), twinStyle)
            twinNotes = twinNotes + (id to outcome.note)
        }
    }
    // twins asked for while offline are written now, quietly (iOS MCQQuizView's .task)
    LaunchedEffect(Unit) {
        if (store.twinShelf.book.pending.isNotEmpty()) TwinWriter.retryPending(store, llm.backend(), twinStyle)
    }

    // the timed paper: wakes once, when its time is up
    LaunchedEffect(examEndsAt) {
        val ends = examEndsAt ?: return@LaunchedEffect
        val wait = ends - System.currentTimeMillis()
        if (wait > 0) delay(wait)
        if (examEndsAt == ends) { haptic.performHapticFeedback(HapticFeedbackType.Reject); handIn() }
    }
    // the slow reading drill: the answer waits until the question has been on screen long enough
    LaunchedEffect(current) {
        if (readSeconds <= 0 || current !in answers.indices || answers[current].checked) { holding = false; return@LaunchedEffect }
        holding = true
        delay(readSeconds * 1000L)
        holding = false
    }
    LaunchedEffect(Unit) { if (startsTimed && canStartExam) startExam() }

    if (showSummary) {
        BackHandler { showSummary = false }
        QuizSummaryScreen(set, store, setAnswers(), onDone = { showSummary = false }, onRetake = { retake(); showSummary = false },
            onOpen = onOpen, isUnsaved = isUnsaved, saved = saved, onSave = { onSave?.invoke(); saved = true })
        return
    }

    val scroll = rememberScrollState()
    val explain = remember { BringIntoViewRequester() }
    // with animations off a new question simply starts at the top
    val reduce = com.stethoscore.app.ui.ward.wardReduceMotion()
    LaunchedEffect(current) { if (reduce) scroll.scrollTo(0) else scroll.animateScrollTo(0) }

    // the chart's words as iOS sets them: their face, with 3 points more between the lines (lineSpacing(3))
    val chartInk = wardColor(WardToken.ink)
    fun chartStyle(face: WardTypeSpec) = face.textStyle().copy(color = chartInk, lineHeight = (face.line + 3).sp)
    val accent = wardColor(WardToken.primaryInk)
    // a stem's text when nothing is being marked: in the slow reading drill, the key words in the accent and bold
    fun plainText(text: String): AnnotatedString = if (readSeconds <= 0) AnnotatedString(text) else buildAnnotatedString {
        append(text)
        StemKeyWords.ranges(text).forEach { addStyle(SpanStyle(color = accent, fontWeight = FontWeight.Bold), it.first, it.last + 1) }
    }

    Column(Modifier.fillMaxSize()) {
        // the title bar (StudyTitleBar): back, the subject, Save for a set not yet saved, and More
        StudyTitleBar(ChartQuiz.title(set.subject, set.name), onBack) {
            // iOS's .wardCompact: one fixed style, and disabled once saved (Biro Grey)
            if (isUnsaved) WardButtonBox({ onSave?.invoke(); saved = true }, kind = WardButtonKind.compact, enabled = !saved) {
                Icon(if (saved) Icons.Rounded.Check else Icons.Rounded.Download, null, Modifier.size(18.dp))
                Text(if (saved) "Saved" else "Save", maxLines = 1)
            }
            Box {
                WardCircleButton(Icons.Rounded.MoreHoriz, "More", { menuOpen = true })
                DropdownMenu(menuOpen, { menuOpen = false }, containerColor = wardColor(WardToken.raised)) {
                    if (canStartExam) {
                        val pace = if (track == ExamTrack.general) "revision" else track.title
                        MenuSection("${track.secondsPerQuestion} seconds a question ($pace pace). Answers wait until the end.")
                        DropdownMenuItem(text = { Text("Start timed exam · ${ChartQuiz.clock(examSeconds)}") },
                            leadingIcon = { Icon(Icons.Rounded.Timer, null) }, onClick = { menuOpen = false; startExam() })
                        HorizontalDivider()
                    }
                    ExamToolMenuItems(track, highlighting, onSheet = { menuOpen = false; toolSheet = it },
                        onHighlight = { menuOpen = false; highlighting = !highlighting })
                    HorizontalDivider()
                    CheckAccuracyMenuItem(accuracyAsk, set, { menuOpen = false }) { verifying = it }
                    // not for a quiz that is not saved yet, nor in the middle of a timed paper
                    if (!isUnsaved && examEndsAt == null) com.stethoscore.app.ui.library.TurnIntoMenuItem({ menuOpen = false }) { turning = set }
                    if (examEndsAt == null) {
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("Clinical reference") }, leadingIcon = { Icon(Icons.Rounded.MedicalServices, null) },
                            onClick = { menuOpen = false; pocketOpen = true }, modifier = Modifier.testTag("wardPocket"))
                    }
                }
            }
        }

        // the header: "Question 3 of 20", the running score, the clock or Timed, the amber strip
        val score = run {
            var correct = 0; var checked = 0
            answers.forEachIndexed { i, ans -> if (ans.checked && !isRetest(i)) { checked += 1; if (isRight(i)) correct += 1 } }
            correct to checked
        }
        val picked = answers.count { it.selected != null }
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                    Text(ChartQuiz.status(current, questions.size), style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                    Text(ChartQuiz.detail(examMode, pendingResume != null, score.first, if (examMode) picked else score.second),
                        style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
                val ends = examEndsAt
                if (ends != null) ExamClock(ends)
                else if (canStartExam && pendingResume == null) WardChipButton("Timed", ::startExam,
                    Modifier.semantics { contentDescription = "Start a timed exam, ${ChartQuiz.clock(examSeconds)}" },
                    icon = Icons.Rounded.Timer, role = Role.Button)
            }
            Box(Modifier.clearAndSetSemantics {}) { QuizStrip(ChartQuiz.fraction(current, questions.size)) }
        }

        Column(Modifier.weight(1f).verticalScroll(scroll).padding(horizontal = 12.dp).padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            pendingResume?.let { p ->
                val done = p.answers.count { it.checked }
                val whenText = DateUtils.getRelativeTimeSpanString(p.savedAt, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString().lowercase()
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.History, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
                    Text("You left off $whenText · $done of ${set.questions.size} answered", style = WardTextStyle.subheadline.textStyle(WardWeight.medium),
                        color = wardColor(WardToken.inkSecondary))
                }
            }

            // the question as a patient's chart
            val layout = remember(q.stem) { ChartQuiz.layout(q.stem) }
            val marks = highlights[current] ?: emptySet()
            WardCardFace(Modifier.fillMaxWidth()) {
                val again = isRetest(current)
                val flaggable = inLibrary(q.id)
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.align(Alignment.CenterVertically), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        WardSmallCapsText("Single best answer", Modifier.semantics { heading() })
                        ChartQuiz.kindChip(again)?.let { WardChip(it, tone = if (again) WardTone.Warning else WardTone.Blue) }
                    }
                    Spacer(Modifier.weight(1f))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (canHint) HintChip(used = hints[q.id] != null, action = ::askHint)
                        if (flaggable) {
                            val on = q.id in flagged
                            WardChipButton(if (on) "Flagged" else "Flag",
                                { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); store.toggleFlag(q.id); flagged = store.flagged },
                                Modifier.semantics { contentDescription = if (on) "Remove flag" else "Flag this question" },
                                on = on, tone = WardTone.Warning, icon = if (on) Icons.Rounded.Flag else Icons.Outlined.Flag, role = Role.Button)
                        }
                    }
                }
                if (layout.plain) {
                    HighlightableStem(q.stem, plainText(q.stem), marks, { highlights = highlights + (current to it) }, highlighting,
                        chartStyle(WardType.title))
                } else {
                    if (layout.chips.isNotEmpty()) ChartChipsRow(layout.chips)
                    if (layout.vitals.isNotEmpty()) ChartVitalsGrid(layout.vitals)
                    if (layout.story.isNotEmpty()) HighlightableStem(layout.story, plainText(layout.story), ChartQuiz.marks(marks, question = false),
                        { highlights = highlights + (current to ChartQuiz.merging(it, question = false, into = highlights[current] ?: emptySet())) },
                        highlighting, chartStyle(WardType.body))
                    if (layout.labs.isNotEmpty()) ChartLabsTable(layout.labs)
                    if (layout.question.isNotEmpty()) HighlightableStem(layout.question, plainText(layout.question), ChartQuiz.marks(marks, question = true),
                        { highlights = highlights + (current to ChartQuiz.merging(it, question = true, into = highlights[current] ?: emptySet())) },
                        highlighting, chartStyle(WardType.headline), prompt = layout.story.isEmpty())
                }
                if (readSeconds > 0 && !a.checked) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.Visibility, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
                    Text("Slow reading: the key words are marked, and you can answer after $readSeconds seconds.", style = WardTextStyle.subheadline.textStyle(),
                        color = wardColor(WardToken.inkSecondary))
                }
                q.imageIndex?.takeIf { it in set.images.indices }?.let { Box(Modifier.heightIn(max = 220.dp)) { CardImage(set, it) } }
            }

            hints[q.id]?.takeIf { !examMode }?.let { AttendingHintCard(it.ifEmpty { null }) }

            // the options
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                q.options.indices.forEach { idx ->
                    OptionButton(idx, optionText(current, idx),
                        ChartQuiz.mark(idx, a.selected, correctSlot(current), a.checked, examMode), isStruck(idx), !a.checked,
                        SpokenText.optionState(checked = a.checked && !examMode, isCorrect = idx == correctSlot(current), isChosen = idx == a.selected),
                        chosen = idx == a.selected,
                        onPick = { if (!a.checked && !isStruck(idx)) answers = answers.replacing(current) { it.copy(selected = idx) } },
                        onStrike = { haptic.performHapticFeedback(HapticFeedbackType.LongPress); toggleStrike(idx) })
                }
            }

            if (pendingResume == null) {
                val explains = ChartQuiz.explains(a.checked, examMode)
                val waiting = !a.checked && (holding || (a.selected == null && !examMode))
                val title = ChartQuiz.primaryTitle(a.checked, a.selected != null, holding, examMode, current == questions.size - 1)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    QuizBigButton(if (explains) null else "Back", Icons.AutoMirrored.Rounded.ArrowBack, QuizButtonKind.companion,
                        onClick = { if (current > 0) current -= 1 }, enabled = current > 0, label = "Previous question")
                    if (explains) QuizBigButton("Explain", null, QuizButtonKind.secondary,
                        onClick = { scope.launch { explain.bringIntoView() } })
                    QuizBigButton(title, if (a.checked) Icons.AutoMirrored.Rounded.ArrowForward else Icons.Rounded.Check, QuizButtonKind.primary,
                        onClick = ::onCheckOrNext, modifier = Modifier.weight(1f), enabled = !waiting)
                }
            }

            // in exam mode the explanation waits for the results, as it would in the real paper
            if (a.checked && !examMode) {
                val correct = isRight(current)
                WardCardFace(Modifier.fillMaxWidth().bringIntoViewRequester(explain)) {
                    Row(Modifier.semantics(mergeDescendants = true) { heading() }, verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val tint = if (correct) wardColor(WardToken.success) else wardColor(WardToken.danger)
                        Icon(if (correct) Icons.Rounded.Verified else Icons.Rounded.Info, null, tint = tint, modifier = Modifier.size(20.dp))
                        val key = correctSlot(current)
                        Text(if (correct) "Correct" else if (key >= 0) "Incorrect: ${letter(key)} is the answer" else "Incorrect", style = WardType.headline.textStyle(), color = tint)
                    }
                    if (struckTheAnswer) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Rounded.HorizontalRule, null, tint = wardColor(WardToken.warning), modifier = Modifier.size(18.dp))
                        Text("You crossed out the right answer. What made you rule it out?", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold),
                            color = wardColor(WardToken.warning))
                    }
                    Text(q.explanation, style = chartStyle(WardType.body))
                }
            }

            if (a.checked && !examMode && !isRight(current) && inLibrary(q.id)) {
                // Why did you miss it? One tap files the mistake under a reason; skippable.
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Skippable("Why did you miss it?")
                    Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val chosen = reasons[q.id]
                        MistakeReason.entries.forEach { reason ->
                            val on = chosen == reason
                            WardChipButton(reason.title, {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                reasons = if (on) reasons - q.id else reasons + (q.id to reason)
                                store.noteMistake(if (on) null else reason.rawValue, q.id)
                            }, on = on, icon = reasonIcon(reason), role = Role.Button)
                        }
                    }
                }
                // a re-test now, a twin later
                val id = q.id
                val canRetest = id !in retested && !isRetest(current)
                val note = twinNotes[id]
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Skippable(if (confidences[id] == AnswerConfidence.sure)
                        "You were sure, so this is the kind of mistake that comes back. Fix it now:" else "Fix it while it’s fresh:")
                    Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (canRetest) WardChipButton("Re-test me soon", ::insertRetest,
                            Modifier.semantics { onClick("Asks this question again, re-shuffled, a few questions from now") { insertRetest(); true } },
                            icon = Icons.Rounded.Redo, role = Role.Button)
                        if (note == null) WardChipButton("Write a twin", ::writeTwin,
                            Modifier.semantics { onClick("A new question on the same point, in a different patient, for a day or two from now") { writeTwin(); true } },
                            icon = Icons.Rounded.ContentCopy, role = Role.Button)
                    }
                    if (id in retested && !isRetest(current)) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Redo, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
                        Text("It comes back, re-shuffled, a few questions from now.", style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
                    }
                    if (note != null) Text(note, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
            }
        }

        // the bar: Start again and Resume while a saved place waits, or How sure? before checking,
        // on the one study deck (iOS studyBar(folds: true, shown:)): it folds away, and hidden it
        // keeps its fold for the next question
        val p = pendingResume
        StudyActionBar(folds = true, shown = p != null || (!a.checked && asksConfidence)) {
            if (p != null) {
                val done = p.answers.count { it.checked }
                val total = set.questions.size
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    QuizBigButton("Start again", null, QuizButtonKind.companion, onClick = ::startAgain, label = "Start again instead")
                    QuizBigButton("Resume ($done of $total)", Icons.Rounded.History, QuizButtonKind.primary, onClick = { resume(p) },
                        modifier = Modifier.weight(1f), label = "Resume, $done of $total answered")
                }
            } else {
                val chosen = confidences[q.id]
                // iOS's confidencePicker: Sure, Maybe and Guess on the label's line wherever they fit, the
                // optional tag dropped first to make room (TalkBack still says it)
                @Composable fun SureLabel(tagged: Boolean) =
                    Row(Modifier.clearAndSetSemantics { contentDescription = "How sure are you? Optional" },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("How sure?", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.inkSecondary))
                        if (tagged) WardChip("optional", tone = WardTone.Grey)
                    }
                @Composable fun SureChips() = AnswerConfidence.entries.forEach { level ->
                    WardChipButton(level.title, {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        confidences = if (chosen == level) confidences - q.id else confidences + (q.id to level)
                    }, on = chosen == level, role = Role.Button)
                }
                FirstThatFits(
                    { Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { SureLabel(true); SureChips() } },
                    { Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { SureLabel(false); SureChips() } },
                    // past that, as before: the label and chips flow onto as many lines as they need, so no
                    // chip is clipped at a large text size or on a narrow window
                    { FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.align(Alignment.CenterVertically)) { SureLabel(true) }
                        SureChips()
                    } },
                )
            }
        }
    }
    ExamToolSheets(toolSheet, track) { toolSheet = null }
    if (pocketOpen) com.stethoscore.app.ui.exam.ExamSheet({ pocketOpen = false }) {
        com.stethoscore.app.ui.exam.WardPocketScreen(track, { pocketOpen = false }, { made -> runCatching { store.addSet(made) } }, store = store)
    }
    verifying?.let { AccuracyWhySheet(it, checksWhenUnchecked = true) { verifying = null } }
    com.stethoscore.app.ui.library.TurnIntoPickerHost(turning, store) { turning = null }
}

/**
 * The first of [choices] that fits the width at its own natural width
 * (SwiftUI's ViewThatFits in .horizontal); the last, laid out in the width
 * given, when none does. A choice is tried in a probe kept out of TalkBack and
 * never placed; only the one chosen is composed where it is shown.
 */
@Composable internal fun FirstThatFits(vararg choices: @Composable () -> Unit, modifier: Modifier = Modifier) {
    androidx.compose.ui.layout.SubcomposeLayout(modifier) { constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val wide = loose.copy(maxWidth = androidx.compose.ui.unit.Constraints.Infinity)
        val chosen = choices.indices.firstOrNull { i ->
            i == choices.lastIndex || subcompose("probe" to i) {
                Box(Modifier.clearAndSetSemantics {}) { choices[i]() }
            }.all { it.measure(wide).width <= constraints.maxWidth }
        } ?: return@SubcomposeLayout layout(constraints.minWidth, constraints.minHeight) {}
        val parts = subcompose("shown" to chosen, choices[chosen]).map { it.measure(if (chosen == choices.lastIndex) loose else wide) }
        val width = (parts.maxOfOrNull { it.width } ?: 0).coerceIn(constraints.minWidth, constraints.maxWidth)
        val height = (parts.maxOfOrNull { it.height } ?: 0).coerceIn(constraints.minHeight, constraints.maxHeight)
        layout(width, height) { parts.forEach { it.placeRelative(0, 0) } }
    }
}

/** A skippable question's lead line, tagged optional. */
@Composable private fun Skippable(lead: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(lead, Modifier.weight(1f, fill = false), style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.inkSecondary))
        WardChip("optional", tone = WardTone.Grey)
    }
}

private fun reasonIcon(reason: MistakeReason) = when (reason) {
    MistakeReason.didntKnow -> Icons.Rounded.QuestionMark
    MistakeReason.misread -> Icons.Rounded.Visibility
    MistakeReason.changedAnswer -> Icons.Rounded.SwapHoriz
    MistakeReason.outOfTime -> Icons.Rounded.Timer
    MistakeReason.lookalikes -> Icons.Rounded.ContentCopy
}

/**
 * One option as a Ward row: a tap chooses it; a long press offers Cross out
 * option or Restore option, and a sideways swipe of 70 points does the same
 * (iOS strikeOutGestures).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable private fun OptionButton(idx: Int, text: String, mark: ChartQuiz.Mark, struck: Boolean, enabled: Boolean, spoken: String,
                                     chosen: Boolean, onPick: () -> Unit, onStrike: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val title = if (struck) "Restore option" else "Cross out option"
    val swipe = with(LocalDensity.current) { 70.dp.toPx() }
    Box {
        WardOptionRow(letter(idx), text, mark, struck, Modifier
            .combinedClickable(interactionSource = remember { MutableInteractionSource() }, indication = null,
                onLongClick = { if (enabled) menu = true }, onClick = onPick)
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                var dx = 0f
                detectHorizontalDragGestures(onDragStart = { dx = 0f }, onDragEnd = { if (abs(dx) > swipe) onStrike() }) { _, amount -> dx += amount }
            }
            .semantics(mergeDescendants = true) {
                contentDescription = "Answer ${letter(idx)}: $text" + (if (struck) ", crossed out" else "")
                stateDescription = spoken
                selected = chosen
                if (enabled) customActions = listOf(CustomAccessibilityAction(title) { onStrike(); true })
            })
        DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.raised)) {
            DropdownMenuItem(text = { Text(title) }, leadingIcon = { Icon(if (struck) Icons.Rounded.Undo else Icons.Rounded.HorizontalRule, null) },
                onClick = { menu = false; onStrike() })
        }
    }
}

/** Time left, ticking once a second, Resus Red for the last minute (WardTimerPill). */
@Composable private fun ExamClock(endsAt: Long) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(endsAt) { while (true) { now = System.currentTimeMillis(); delay(1000) } }
    val left = maxOf(0, ((endsAt - now + 999) / 1000).toInt())
    WardTimerPill(left, Modifier.clearAndSetSemantics { contentDescription = ChartQuiz.spokenClock(left) }, warnBelow = 61)
}


/**
 * How a study screen's state is kept across the activity being recreated (a
 * rotation, a fold, a window resize): each as plain arrays and strings a
 * Bundle holds, read back as it was.
 */
internal object StudySavers {
    /** Each answer as its slot (-1 for none) and whether it was checked. */
    val answers: Saver<List<MCQAnswer>, IntArray> = Saver(
        { list -> IntArray(list.size * 2).also { a -> list.forEachIndexed { i, x -> a[2 * i] = x.selected ?: -1; a[2 * i + 1] = if (x.checked) 1 else 0 } } },
        { a -> (0 until a.size / 2).map { i -> MCQAnswer(a[2 * i].takeIf { it >= 0 }, a[2 * i + 1] == 1) } })
    /** Each order as its length then its indices. */
    val orders: Saver<List<List<Int>>, IntArray> = Saver(
        { list -> list.flatMap { listOf(it.size) + it }.toIntArray() },
        { a -> val out = ArrayList<List<Int>>(); var i = 0; while (i < a.size) { val n = a[i]; out.add(a.slice(i + 1..i + n)); i += n + 1 }; out })
    /** Marks by question index: the index, how many, then the marks. */
    val marks: Saver<Map<Int, Set<Int>>, IntArray> = Saver(
        { m -> m.entries.flatMap { (k, v) -> listOf(k, v.size) + v }.toIntArray() },
        { a -> val out = LinkedHashMap<Int, Set<Int>>(); var i = 0; while (i + 1 < a.size) { val n = a[i + 1]; out[a[i]] = a.slice(i + 2 until i + 2 + n).toSet(); i += n + 2 }; out })
    /** Marks by question id: the id, then the marks joined by commas. */
    val idMarks: Saver<Map<String, Set<Int>>, ArrayList<String>> = Saver(
        { m -> m.entries.flatMapTo(ArrayList()) { (k, v) -> listOf(k, v.joinToString(",")) } },
        { a -> a.chunked(2).filter { it.size == 2 }.associate { (k, v) -> k to (if (v.isEmpty()) emptySet() else v.split(",").map(String::toInt).toSet()) } })
    val idInts: Saver<Map<String, Int>, ArrayList<String>> = Saver(
        { m -> m.entries.flatMapTo(ArrayList()) { (k, v) -> listOf(k, v.toString()) } },
        { a -> a.chunked(2).filter { it.size == 2 }.associate { (k, v) -> k to v.toInt() } })
    val stringMap: Saver<Map<String, String>, ArrayList<String>> = Saver(
        { m -> m.entries.flatMapTo(ArrayList()) { (k, v) -> listOf(k, v) } },
        { a -> a.chunked(2).filter { it.size == 2 }.associate { (k, v) -> k to v } })
    val stringSet: Saver<Set<String>, ArrayList<String>> = Saver({ ArrayList(it) }, { it.toSet() })
    fun <E : Enum<E>> enumMap(parse: (String) -> E): Saver<Map<String, E>, ArrayList<String>> = Saver(
        { m -> m.entries.flatMapTo(ArrayList()) { (k, v) -> listOf(k, v.name) } },
        { a -> a.chunked(2).filter { it.size == 2 }.mapNotNull { (k, v) -> runCatching { k to parse(v) }.getOrNull() }.toMap() })
}
