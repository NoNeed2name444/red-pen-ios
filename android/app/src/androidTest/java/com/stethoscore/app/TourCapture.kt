package com.stethoscore.app

import android.content.Context
import android.os.SystemClock
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.stethoscore.app.data.AnswerEvent
import com.stethoscore.app.data.InsightExamples
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.learn.WardRoundClock
import com.stethoscore.app.ui.library.IncomingFiles
import com.stethoscore.app.ui.ward.WardPaperFrame
import com.stethoscore.app.ui.ward.WardSection
import com.stethoscore.app.ui.ward.wardFrameClearance
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.regex.Pattern

/** The two looks every tour row is shot in, and the word each puts at the end of a shot's name. */
enum class Mode(val word: String, val dark: Boolean) { LIGHT("light", false), DARK("dark", true) }

/**
 * The app tour's camera (T0126c): one composition per test, shown in each mode in turn,
 * and a still of each screen as `r<row>-<plain name>-<light|dark>.png` in [DIRECTORY].
 * The capture is ScreenshotTest's shot(), systemDialog() and dismissSystemDialogs(), with
 * the tour's own directory and names.
 */
class TourCapture(private val compose: ComposeContentTestRule) {
    val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val mode = mutableStateOf<Mode?>(null)

    // MARK: one composition, each mode in turn

    /**
     * Sets [content] once, then for each of [modes]: [before] (on the test thread, before
     * the mode is shown), the mode itself, and [then] (taps and shots). The mode is a key,
     * so remembered state starts afresh in each mode, as it would on a second visit.
     */
    fun inEachMode(modes: List<Mode> = Mode.entries, before: (Mode) -> Unit = {}, content: @Composable (Mode) -> Unit, then: (Mode) -> Unit) {
        compose.setContent { mode.value?.let { m -> key(m) { content(m) } } }
        for (m in modes) {
            before(m)
            compose.runOnIdle { mode.value = m }
            compose.waitForIdle()
            then(m)
        }
    }

    /** The app itself on [screen] (its initialScreen route), in the mode's look. */
    @Composable fun App(store: StudyStore, screen: String, m: Mode) = StethoscoreApp(store, initialScreen = screen, forceDark = m.dark)

    /** A screen shown on its own, framed as the app frames every page but home (StethoscoreApp's Surface and WardPaperFrame). */
    @Composable fun Page(m: Mode, section: WardSection, content: @Composable () -> Unit) {
        StethoscoreTheme(m.dark, section) {
            Box(Modifier.fillMaxSize()) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    // inside the frame's ring, as StethoscoreApp places every framed page (wardFrameClearance)
                    Box(Modifier.fillMaxSize().wardFrameClearance()) { content() }
                }
                WardPaperFrame(Modifier.fillMaxSize())
            }
        }
    }

    /** A sheet or dialog over whatever is behind it, in the mode's look. */
    @Composable fun Over(m: Mode, section: WardSection, content: @Composable () -> Unit) = StethoscoreTheme(m.dark, section, content)

    // MARK: waiting and tapping, with a message that says what was missing

    fun exists(matcher: SemanticsMatcher): Boolean = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()

    fun waitFor(what: String, timeoutMs: Long = 15_000, condition: () -> Boolean) {
        try {
            compose.waitUntil(timeoutMs, condition)
        } catch (e: ComposeTimeoutException) {
            throw AssertionError("Tour: $what did not show within ${timeoutMs / 1000} s", e)
        }
    }

    fun waitFor(what: String, matcher: SemanticsMatcher, timeoutMs: Long = 15_000) = waitFor(what, timeoutMs) { exists(matcher) }

    fun tap(what: String, matcher: SemanticsMatcher, timeoutMs: Long = 15_000) {
        waitFor(what, matcher, timeoutMs)
        compose.onAllNodes(matcher).onFirst().performClick()
        compose.waitForIdle()
    }

    /** Scrolls the one scrolling list on screen until [matcher] is in it, then waits for it. */
    fun scrollTo(what: String, matcher: SemanticsMatcher) {
        waitFor("a scrolling list (to find $what)", hasScrollToNodeAction())
        try {
            compose.onAllNodes(hasScrollToNodeAction()).onFirst().performScrollToNode(matcher)
        } catch (e: AssertionError) {
            throw AssertionError("Tour: $what is not in the screen's list", e)
        }
        compose.waitForIdle()
    }

    fun ui(block: () -> Unit) = InstrumentationRegistry.getInstrumentation().runOnMainSync(block)

    // MARK: what the tests start from

    /** The app's own examples (DemoData, as Settings > Load examples adds them). */
    fun store(): StudyStore = StudyStore(newDirectory()).also { it.loadExamples() }

    /** A library with nothing in it. */
    fun bareStore(): StudyStore = StudyStore(newDirectory())

    /** A library file that cannot be read, so the store opens with its loadError. */
    fun unreadableStore(): StudyStore {
        val directory = newDirectory().also { it.mkdirs() }
        File(directory, "stethoscore.json").writeText("{ \"library\": [ this is not JSON")
        return StudyStore(directory).also { check(it.loadError != null) { "Tour: the broken library file opened without an error" } }
    }

    /**
     * The examples plus InsightExamples' sets, with InsightExamples' answer history,
     * mistake reasons and rule sheet when [insightHistory], and the [extra] answers,
     * written into the library file the way StudyStore writes it, then opened.
     */
    fun historyStore(insightHistory: Boolean, extra: (library: List<StudySet>, now: Long) -> List<AnswerEvent> = { _, _ -> emptyList() }): StudyStore {
        val directory = newDirectory()
        val first = StudyStore(directory).also { it.loadExamples() }
        val now = System.currentTimeMillis()
        val seed = InsightExamples.make(first.library, now = now)
        first.addSets(seed.sets)
        val events = ((if (insightHistory) seed.events else emptyList()) + extra(first.library, now)).sortedBy { it.at }
        val root = JSONObject(first.exportJson())
        root.put("answerLog", JSONArray().also { array ->
            for (e in events) array.put(JSONObject().put("questionId", e.questionId).put("correct", e.correct).put("at", Instant.ofEpochMilli(e.at).toString())
                .also { o -> e.confidence?.let { o.put("confidence", it) }; e.isExample?.let { o.put("isExample", it) } })
        })
        root.put("answerHistory", JSONObject().also { o -> events.groupBy { it.questionId }.forEach { (id, list) -> o.put(id, JSONArray(list.map { it.correct })) } })
        if (insightHistory) {
            root.put("mistakeReasons", JSONObject().also { o ->
                seed.reasons.forEach { (id, n) -> o.put(id, JSONObject().put("reason", n.reason).put("at", Instant.ofEpochMilli(n.at).toString()).put("isExample", true)) }
            })
            root.put("ruleSheet", JSONObject().also { o -> seed.rules.forEach { (id, rule) -> o.put(id, rule.json()) } })
        }
        File(directory, "stethoscore.json").writeText(root.toString())
        return StudyStore(directory).also {
            check(it.loadError == null) { "Tour: the seeded library did not open: ${it.loadError}" }
            check(it.answerLog.size == events.size) { "Tour: the seeded history did not load (${it.answerLog.size} of ${events.size} answers)" }
        }
    }

    private fun newDirectory() = File(context.cacheDir, "tour-${System.nanoTime()}")

    /**
     * Every test starts and ends with nothing left over from another: the app's remembered
     * choices (not the AI model choice or its key), the ward round, files waiting to be
     * imported, and the mock exam's saved sitting and results.
     */
    fun reset() {
        for (name in listOf("appearance", "review", "audio", "reader", "ideas", "learn"))
            context.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear().commit()
        ui {
            LearnRouter.close()
            WardRoundClock.close()
            IncomingFiles.waiting.clear()
        }
        File(context.filesDir, "mock-sitting.json").delete()
        File(context.filesDir, "exam-mocks.json").delete()
    }

    // MARK: the still

    /** Shoots the screen as r<row>-<name>-<mode>.png. */
    fun shot(row: Int, name: String, m: Mode) {
        val file = "r%03d-%s-%s".format(row, name, m.word)
        require(file.matches(Regex("[a-z0-9-]+"))) { "Tour: shot name $file is not [a-z0-9-]+" }
        compose.waitForIdle()
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        device.waitForIdle()
        device.executeShellCommand("mkdir -p $DIRECTORY")
        for (attempt in 1..3) {
            dismissSystemDialogs(device)
            SystemClock.sleep(600) // Allow the compositor to present the settled Compose frame.
            if (systemDialog(device)) continue
            device.executeShellCommand("screencap -p $DIRECTORY/$file.png")
            if (!systemDialog(device)) {
                val size = device.executeShellCommand("stat -c %s $DIRECTORY/$file.png").trim().toLongOrNull()
                check(size != null && size > 0) { "Tour: screenshot was not written: $file" }
                return
            }
        }
        device.executeShellCommand("rm -f $DIRECTORY/$file.png")
        error("Tour: a system dialog covered the screen for $file")
    }

    private val dialogText = Pattern.compile(".*(isn.t responding|keeps stopping|has stopped).*", Pattern.CASE_INSENSITIVE)
    private fun systemDialog(device: UiDevice) =
        device.hasObject(By.res("android", "aerr_wait")) || device.hasObject(By.res("android", "aerr_close")) ||
            device.hasObject(By.text(dialogText))
    private fun dismissSystemDialogs(device: UiDevice) {
        repeat(3) {
            if (!systemDialog(device)) return
            // "Wait" keeps the launcher alive; "Close app" is the fallback for crash dialogs.
            val button = device.findObject(By.res("android", "aerr_wait")) ?: device.findObject(By.res("android", "aerr_close"))
            if (button != null) button.click() else device.executeShellCommand("am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS")
            device.wait(Until.gone(By.text(dialogText)), 3_000)
            device.waitForIdle()
        }
    }

    companion object {
        const val DIRECTORY = "/sdcard/Download/stethoscore-tour"
    }
}
