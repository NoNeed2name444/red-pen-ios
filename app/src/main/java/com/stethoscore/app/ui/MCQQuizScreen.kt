package com.stethoscore.app.ui

import android.content.Context
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
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
import com.stethoscore.app.ui.ward.WardToken
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

// A port of upstream/ios/RedPen/Features/MCQ/MCQQuizView.swift: the question
// screen. Pick an option, check it (the right one in the section's colour, a
// wrong pick faded grey), read the explanation, then Next patient / See
// results. The same flow and words as iOS: resuming a saved place, the timed
// paper, crossing out, the highlighter, the attending's hint, Flag, How sure?,
// Why did you miss it?, and a re-test a few questions on. What each part
// says is decided, and tested, in quiz/ (ChartQuiz, OptionOrder, TwinRetest,
// SpokenText).
//
// Not here yet, because their batches have not come: the accuracy badge,
// Check accuracy and Turn into in the More menu, Save to Ideas, How to reach
// it (Reasoning), and the keyboard shortcuts. Android has no question writer,
// so the hint is always the attending's own (AttendingHint.fallback) and
// Write a twin says that none is set up. The Ward controls are plain Compose
// stand-ins (ChartQuizViews.kt) until batches 2 and 3 land.

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
    val asksConfidence = remember { QuizPrefs.asksConfidence(context) }
    val readSeconds = maxOf(0, minReadSeconds)

    var current by remember { mutableIntStateOf(0) }
    var answers by remember { mutableStateOf(List(set.questions.size) { MCQAnswer() }) }
    // per-question option order: displayed slot i shows the original option orders[q][i]
    var orders by remember { mutableStateOf(set.questions.map { OptionOrder.make(it.options.size, shuffle = true) }) }
    var showSummary by remember { mutableStateOf(false) }
    var pendingResume by remember { mutableStateOf<QuizProgress?>(null) }
    var examMode by remember { mutableStateOf(false) }
    var examEndsAt by remember { mutableStateOf<Long?>(null) }
    var confidences by remember { mutableStateOf(mapOf<String, AnswerConfidence>()) }
    var reasons by remember { mutableStateOf(mapOf<String, MistakeReason>()) }
    var holding by remember { mutableStateOf(false) }
    var reordered by remember { mutableStateOf<List<MCQQuestion>?>(null) }
    var retested by remember { mutableStateOf(setOf<String>()) }
    var struck by remember { mutableStateOf(mapOf<Int, Set<Int>>()) }
    var highlights by remember { mutableStateOf(mapOf<Int, Set<Int>>()) }
    var highlighting by remember { mutableStateOf(false) }
    var toolSheet by remember { mutableStateOf<ExamToolSheet?>(null) }
    // the Ward pocket (batch 16), from More while no timed exam runs
    var pocketOpen by remember { mutableStateOf(false) }
    var hints by remember { mutableStateOf(mapOf<String, String>()) }
    var twinNotes by remember { mutableStateOf(mapOf<String, String>()) }
    var flagged by remember { mutableStateOf(store.flagged) }
    var saved by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }

    if (set.questions.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            ScreenHeader(ChartQuiz.title(set.subject, set.name), "", onBack)
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.QuestionMark, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(12.dp))
                Text("No questions", fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                Text("This set has no questions yet.", color = wardColor(WardToken.inkSecondary))
            }
        }
        return
    }

    val questions = reordered ?: set.questions
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
    fun writeTwin() {
        twinNotes = twinNotes + (q.id to "Twins are written by a question writer, and none is set up on this phone yet.")
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
    LaunchedEffect(current) { scroll.animateScrollTo(0) }

    val inkStyle = TextStyle(color = wardColor(WardToken.ink), lineHeight = 24.sp)
    val accent = wardColor(WardToken.primaryInk)
    // a stem's text when nothing is being marked: in the slow reading drill, the key words in the accent and bold
    fun plainText(text: String): AnnotatedString = if (readSeconds <= 0) AnnotatedString(text) else buildAnnotatedString {
        append(text)
        StemKeyWords.ranges(text).forEach { addStyle(SpanStyle(color = accent, fontWeight = FontWeight.Bold), it.first, it.last + 1) }
    }

    Column(Modifier.fillMaxSize()) {
        // the title bar: back, the subject, Save for a set not yet saved, and More
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back") }
            Text(ChartQuiz.title(set.subject, set.name), Modifier.weight(1f).semantics { heading() }, fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold, maxLines = 1, color = wardColor(WardToken.ink))
            if (isUnsaved) QuizChip(if (saved) "Saved" else "Save", if (saved) Icons.Rounded.Check else Icons.Rounded.Download, on = false,
                onClick = { onSave?.invoke(); saved = true }, enabled = !saved)
            Box {
                IconButton(onClick = { menuOpen = true }) { Icon(Icons.Rounded.MoreHoriz, contentDescription = "More") }
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
                    if (examEndsAt == null) {
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("Ward pocket") }, leadingIcon = { Icon(Icons.Rounded.MedicalServices, null) },
                            onClick = { menuOpen = false; pocketOpen = true }, modifier = Modifier.testTag("wardPocket"))
                    }
                }
            }
        }

        // the header: "Patient 3 of 20", the running score, the clock or Timed, the amber strip
        val score = run {
            var correct = 0; var checked = 0
            answers.forEachIndexed { i, ans -> if (ans.checked && !isRetest(i)) { checked += 1; if (isRight(i)) correct += 1 } }
            correct to checked
        }
        val picked = answers.count { it.selected != null }
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                    Text(ChartQuiz.status(current, questions.size), fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = wardColor(WardToken.ink))
                    Text(ChartQuiz.detail(examMode, pendingResume != null, score.first, if (examMode) picked else score.second),
                        fontSize = 15.sp, color = wardColor(WardToken.inkSecondary))
                }
                val ends = examEndsAt
                if (ends != null) ExamClock(ends)
                else if (canStartExam && pendingResume == null) QuizChip("Timed", Icons.Rounded.Timer, on = false, onClick = ::startExam,
                    label = "Start a timed exam, ${ChartQuiz.clock(examSeconds)}")
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
                    Text("You left off $whenText · $done of ${set.questions.size} answered", fontSize = 15.sp, fontWeight = FontWeight.Medium,
                        color = wardColor(WardToken.inkSecondary))
                }
            }

            // the question as a patient's chart
            val layout = remember(q.stem) { ChartQuiz.layout(q.stem) }
            val marks = highlights[current] ?: emptySet()
            QuizCard {
                val again = isRetest(current)
                val flaggable = inLibrary(q.id)
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.align(Alignment.CenterVertically), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        QuizSmallCaps("Patient chart")
                        QuizTag(ChartQuiz.kindChip(again), if (again) QuizTone.warning else QuizTone.blue)
                    }
                    Spacer(Modifier.weight(1f))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (canHint) HintChip(used = hints[q.id] != null, action = ::askHint)
                        if (flaggable) {
                            val on = q.id in flagged
                            QuizChip(if (on) "Flagged" else "Flag", if (on) Icons.Rounded.Flag else Icons.Outlined.Flag, on = on, warning = true,
                                label = if (on) "Remove flag" else "Flag this question",
                                onClick = { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); store.toggleFlag(q.id); flagged = store.flagged })
                        }
                    }
                }
                if (layout.plain) {
                    HighlightableStem(q.stem, plainText(q.stem), marks, { highlights = highlights + (current to it) }, highlighting,
                        inkStyle.copy(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, lineHeight = 28.sp))
                } else {
                    if (layout.chips.isNotEmpty()) ChartChipsRow(layout.chips)
                    if (layout.vitals.isNotEmpty()) ChartVitalsGrid(layout.vitals)
                    if (layout.story.isNotEmpty()) HighlightableStem(layout.story, plainText(layout.story), ChartQuiz.marks(marks, question = false),
                        { highlights = highlights + (current to ChartQuiz.merging(it, question = false, into = highlights[current] ?: emptySet())) },
                        highlighting, inkStyle.copy(fontSize = 17.sp))
                    if (layout.labs.isNotEmpty()) ChartLabsTable(layout.labs)
                    if (layout.question.isNotEmpty()) HighlightableStem(layout.question, plainText(layout.question), ChartQuiz.marks(marks, question = true),
                        { highlights = highlights + (current to ChartQuiz.merging(it, question = true, into = highlights[current] ?: emptySet())) },
                        highlighting, inkStyle.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold), prompt = layout.story.isEmpty())
                }
                if (readSeconds > 0 && !a.checked) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.Visibility, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
                    Text("Slow reading: the key words are marked, and you can answer after $readSeconds seconds.", fontSize = 15.sp,
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
                QuizCard(Modifier.bringIntoViewRequester(explain)) {
                    Row(Modifier.semantics(mergeDescendants = true) { heading() }, verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val tint = if (correct) wardColor(WardToken.success) else wardColor(WardToken.danger)
                        Icon(if (correct) Icons.Rounded.Verified else Icons.Rounded.Info, null, tint = tint, modifier = Modifier.size(20.dp))
                        Text(if (correct) "Right!" else "Not quite", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = tint)
                    }
                    if (struckTheAnswer) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Rounded.HorizontalRule, null, tint = wardColor(WardToken.warning), modifier = Modifier.size(18.dp))
                        Text("You crossed out the right answer. What made you rule it out?", fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                            color = wardColor(WardToken.warning))
                    }
                    Text(q.explanation, style = inkStyle.copy(fontSize = 17.sp))
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
                            QuizChip(reason.title, reasonIcon(reason), on = on, onClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                reasons = if (on) reasons - q.id else reasons + (q.id to reason)
                                store.noteMistake(if (on) null else reason.rawValue, q.id)
                            })
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
                        if (canRetest) QuizChip("Re-test me soon", Icons.Rounded.Redo, on = false, onClick = ::insertRetest,
                            modifier = Modifier.semantics { onClick("Asks this question again, re-shuffled, a few questions from now") { insertRetest(); true } })
                        if (note == null) QuizChip("Write a twin", Icons.Rounded.ContentCopy, on = false, onClick = ::writeTwin,
                            modifier = Modifier.semantics { onClick("A new question on the same point, in a different patient, for a day or two from now") { writeTwin(); true } })
                    }
                    if (id in retested && !isRetest(current)) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Redo, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
                        Text("It comes back, re-shuffled, a few questions from now.", fontSize = 13.sp, color = wardColor(WardToken.inkSecondary))
                    }
                    if (note != null) Text(note, fontSize = 13.sp, color = wardColor(WardToken.inkSecondary))
                }
            }
        }

        // the bar: Start again and Resume while a saved place waits, or How sure? before checking
        val p = pendingResume
        if (p != null || (!a.checked && asksConfidence)) {
            Column(Modifier.fillMaxWidth().background(wardColor(WardToken.raised)).padding(horizontal = 16.dp, vertical = 12.dp)) {
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
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(Modifier.align(Alignment.CenterVertically).clearAndSetSemantics { contentDescription = "How sure are you? Optional" },
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("How sure?", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.inkSecondary))
                            QuizTag("optional", QuizTone.grey)
                        }
                        AnswerConfidence.entries.forEach { level ->
                            QuizChip(level.title, null, on = chosen == level, onClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                confidences = if (chosen == level) confidences - q.id else confidences + (q.id to level)
                            })
                        }
                    }
                }
            }
        }
    }
    ExamToolSheets(toolSheet, track) { toolSheet = null }
    if (pocketOpen) com.stethoscore.app.ui.exam.ExamSheet({ pocketOpen = false }) {
        com.stethoscore.app.ui.exam.WardPocketScreen(track, { pocketOpen = false }, { made -> runCatching { store.addSet(made) } })
    }
}

/** A skippable question's lead line, tagged optional. */
@Composable private fun Skippable(lead: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(lead, Modifier.weight(1f, fill = false), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.inkSecondary))
        QuizTag("optional", QuizTone.grey)
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
    val ink = if (left < 61) wardColor(WardToken.danger) else wardColor(WardToken.ink)
    Row(Modifier.quizFace(QuizFace.pressed, CircleShape, 20f).padding(horizontal = 12.dp, vertical = 8.dp)
        .clearAndSetSemantics { contentDescription = ChartQuiz.spokenClock(left) },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.Rounded.Timer, null, tint = ink, modifier = Modifier.size(16.dp))
        Text(ChartQuiz.clock(left), color = ink, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}

