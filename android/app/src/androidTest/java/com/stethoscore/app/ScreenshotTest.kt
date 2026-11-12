package com.stethoscore.app

import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.safeDrawingPadding
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.stethoscore.app.quiz.ChartQuiz
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.*
import com.stethoscore.app.ui.map.MapDrawn
import com.stethoscore.app.ui.map.MapDrawnKey
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import org.junit.runner.RunWith
import java.io.File
import java.util.regex.Pattern

@RunWith(AndroidJUnit4::class)
class ScreenshotTest {
    @get:Rule val compose = createComposeRule()
    // textbook() opens a textbook for the first time, which puts Guess first over the app:
    // the one learning sheet must not stay over the tests that run after it
    @get:Rule val learnClosed = LearnRouterClosed()
    private fun store(): StudyStore {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        return StudyStore(File(context.cacheDir,"preview-${System.nanoTime()}")).also {it.loadExamples()}
    }
    private fun shot(name:String) = still(compose,"/sdcard/Download/stethoscore-screenshots",name)
    companion object {
        /** One still of the screen, as [name].png in [directory] (WindowShots takes its stills the same way). */
        internal fun still(compose:androidx.compose.ui.test.junit4.ComposeTestRule,directory:String,name:String) {
        compose.waitForIdle()
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        require(name.matches(Regex("[a-z0-9-]+")))
        val device=UiDevice.getInstance(instrumentation)
        device.waitForIdle()
        device.executeShellCommand("mkdir -p $directory")
        // A slow emulator can raise a system "isn't responding" dialog over the app at any
        // moment. Dismiss it, shoot, and shoot again if one appeared meanwhile; a screen that
        // stays covered fails the test instead of passing with the dialog in the picture.
        for (attempt in 1..3) {
            dismissSystemDialogs(device)
            SystemClock.sleep(600) // Allow the compositor to present the settled Compose frame.
            if (systemDialog(device)) continue
            device.executeShellCommand("screencap -p $directory/$name.png")
            if (!systemDialog(device)) {
                val size = device.executeShellCommand("stat -c %s $directory/$name.png").trim().toLongOrNull()
                check(size != null && size > 0) { "Screenshot was not written: $name" }
                return
            }
        }
        device.executeShellCommand("rm -f $directory/$name.png")
        error("A system dialog covered the screen for $name")
    }
    private val dialogText=Pattern.compile(".*(isn.t responding|keeps stopping|has stopped).*",Pattern.CASE_INSENSITIVE)
    private fun systemDialog(device:UiDevice)=
        device.hasObject(By.res("android","aerr_wait")) || device.hasObject(By.res("android","aerr_close")) ||
            device.hasObject(By.text(dialogText))
    private fun dismissSystemDialogs(device:UiDevice) {
        repeat(3) {
            if (!systemDialog(device)) return
            // "Wait" keeps the launcher alive; "Close app" is the fallback for crash dialogs.
            val button=device.findObject(By.res("android","aerr_wait")) ?: device.findObject(By.res("android","aerr_close"))
            if (button!=null) button.click() else device.executeShellCommand("am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS")
            device.wait(Until.gone(By.text(dialogText)),3_000)
            device.waitForIdle()
        }
    }
    }
    @Test fun homeLight() { val store=store();compose.setContent {StethoscoreApp(store)};compose.onNodeWithText("Stethoscore").assertIsDisplayed();shot("01-home-light") }
    @Test fun homeDark() { val store=store();compose.setContent {StethoscoreApp(store,forceDark=true)};shot("02-home-dark") }
    @Test fun quizAnswerPersists() {
        val store=store();val set=store.library.first {it.kind==StudySetKind.MCQ}
        compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {QuizScreen(set,store,{},minReadSeconds=0)}}}}
        shot("03-questions")
        compose.onNodeWithText(set.questions.first().options[set.questions.first().correctIndex]).performScrollTo().performClick()
        compose.onNodeWithText("Check answer").performClick()  // on the deck, always in view (T0211 A2)
        compose.onNodeWithText("Correct").performScrollTo().assertIsDisplayed()
        check(store.answerHistory[set.questions.first().id]?.last()==true)
        shot("04-answer-explanation")
    }
    @Test fun cardsRevealAndSchedule() {
        val store=store();val set=store.library.first {it.kind==StudySetKind.ANKI}
        compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {AnkiReviewScreen(set,store,{})}}}}
        shot("05-cards")
        // Reveal and the ratings sit in the review's fixed bottom bar (StudyBar), outside the
        // card's scroll: they are tapped where they stand, and must be on screen to be tapped
        compose.onNodeWithText("Reveal").assertIsDisplayed().performClick()
        shot("06-card-revealed")
        compose.onNodeWithContentDescription("Good, back in", substring = true).assertIsDisplayed().performClick()
        check(store.reviews.isNotEmpty())
    }
    @Test fun osce() { val store=store();val set=store.library.first {it.kind==StudySetKind.OSCE};compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {ClinicalScreen(set,store,{})}}}};shot("07-osce") }
    @Test fun cases() { val store=store();val set=store.library.first {it.kind==StudySetKind.CASES};compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {ClinicalScreen(set,store,{})}}}};shot("08-cases") }
    @Test fun narrate() { val store=store();val set=store.library.first {it.kind==StudySetKind.NARRATE};compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {ClinicalScreen(set,store,{})}}}};compose.onNodeWithText("Line 1 of ${set.narrateSegments.size}").assertIsDisplayed();shot("13-narrate") }
    @Test fun ideas() {
        val store=store()
        // Linked ideas so the screenshot shows the list and the map, not the empty state.
        val heart=Note(title="Heart failure",tags=listOf("cardio"))
        val bnp=Note(title="BNP",body="Rises with ventricular stretch.",links=listOf(heart.id),tags=listOf("labs"))
        val edema=Note(title="Pulmonary oedema",links=listOf(heart.id,bnp.id),tags=listOf("cardio"))
        val diuretics=Note(title="Loop diuretics",links=listOf(edema.id),tags=listOf("drugs"))
        listOf(heart,bnp,edema,diuretics).forEach(store::saveNote)
        ideasPrefs {}
        compose.setContent {StethoscoreApp(store,initialScreen="ideas")}
        compose.onNodeWithText("Loop diuretics").assertIsDisplayed()
        shot("09-ideas")
        compose.onNodeWithTag("ideasMode-space").performClick()
        compose.waitUntil(30_000) { compose.onAllNodesWithContentDescription("Space of ideas: 4 notes, 4 links",substring=true).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("Space of ideas: 4 notes, 4 links",substring=true).assertIsDisplayed()
        // until the map says its bodies are drawn: a fifth of a second on a phone, seconds on the CI
        // emulator's software GL, where the 3 s pause that stood here sampled the frame before them
        awaitMapFrames("Space of ideas: 4 notes, 4 links",bodies=true)
        shot("11-ideas-map") // kept even when the check below fails, to see why
        try { requireMapDrawn("Space of ideas: 4 notes, 4 links",bodies=true) } finally { ideasPrefs {} }
    }
    @Test fun millionNodeDemo() {
        val store=store()
        // Ideas' Space, in the Performance theme, showing the million-note demo map
        ideasPrefs { putString("vignette.ideas.mode","space"); putString("vignette.space.theme","performance"); putInt("vignette.space.perfDemo",1_000_000) }
        compose.setContent {StethoscoreApp(store,initialScreen="ideas")}
        // building a million nodes and their octree takes a few seconds on a CI emulator
        // the map itself, not the debug readout (a debug build's tool, not always shown)
        compose.waitUntil(120_000) { compose.onAllNodesWithContentDescription("demo of 1,000,000 synthetic notes",substring=true).fetchSemanticsNodes().isNotEmpty() }
        SystemClock.sleep(6_000) // the adaptive budget settles on what this emulator can draw at its refresh rate
        awaitMapFrames("demo of 1,000,000 synthetic notes",bodies=false)
        shot("12-ideas-million") // kept even when the check below fails, to see why
        try { requireMapDrawn("demo of 1,000,000 synthetic notes",bodies=false) } finally { ideasPrefs {} }
    }
    /** Ideas' remembered choices (the "ideas" preferences), cleared, then set as [block] says. */
    private fun ideasPrefs(block: android.content.SharedPreferences.Editor.() -> Unit) {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("ideas",android.content.Context.MODE_PRIVATE).edit().clear().apply(block).commit()
    }
    /** The map's own record of what it has drawn (Map3DView's MapDrawnKey); null before its node is there. */
    private fun mapDrawn(description:String):MapDrawn? =
        compose.onAllNodesWithContentDescription(description,substring=true).fetchSemanticsNodes().firstOrNull()?.config?.getOrElseNullable(MapDrawnKey) { null }
    private fun framed(drawn:MapDrawn?,bodies:Boolean)=
        drawn!=null && drawn.frames>=MapDrawn.ENOUGH && (!bodies || drawn.bodyFrames>=MapDrawn.ENOUGH)
    /**
     * Waits, up to a minute, until the map reports MapDrawn.ENOUGH finished frames, with its Space
     * bodies when [bodies]. The CI emulator draws GL in software, which builds each shader on its
     * first draw: the Space map's first frame with bodies takes seconds there, and until it is
     * shown the map holds only its summary star, a point that renderer allows 1 px. The wait is
     * on the map's word, never on the screen: requireMapDrawn still looks once, as strictly as
     * before, and fails with the record if the wait ran out.
     */
    private fun awaitMapFrames(description:String,bodies:Boolean) {
        try { compose.waitUntil(60_000) { framed(mapDrawn(description),bodies) } } catch (timeout:ComposeTimeoutException) {}
    }
    /**
     * The GL surface really drew: the map reports finished frames (with its bodies, in Space), and
     * the middle of the map (below the readout, above the zoom buttons) holds bright, coloured
     * points. The readout and labels are near-white text, so only saturated colour counts.
     */
    private fun requireMapDrawn(description:String,bodies:Boolean) {
        val drawn=mapDrawn(description)
        check(framed(drawn,bodies)) {"The 3D map has not finished ${MapDrawn.ENOUGH} frames${if (bodies) " with its bodies" else ""} (waited up to a minute) for $description: $drawn"}
        val bounds=compose.onNodeWithContentDescription(description,substring=true).fetchSemanticsNode().boundsInRoot
        val screen=checkNotNull(InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()) {"No screenshot for $description"}
        val left=(bounds.left+bounds.width*0.08f).toInt().coerceIn(0,screen.width-1)
        val right=(bounds.right-bounds.width*0.08f).toInt().coerceIn(left+1,screen.width)
        val top=(bounds.top+bounds.height*0.3f).toInt().coerceIn(0,screen.height-1)
        val bottom=(bounds.bottom-bounds.height*0.2f).toInt().coerceIn(top+1,screen.height)
        var coloured=0; var samples=0
        // for the message: the most saturated and the brightest sample, whether they counted or not
        var vivid=-1; var vividAt=""; var bright=-1; var brightAt=""
        for (y in top until bottom step 2) for (x in left until right step 2) {
            val c=screen.getPixel(x,y)
            val r=(c shr 16) and 255; val g=(c shr 8) and 255; val b=c and 255
            if (r+g+b>220 && maxOf(r,g,b)-minOf(r,g,b)>45) coloured++
            samples++
            if (maxOf(r,g,b)-minOf(r,g,b)>vivid) { vivid=maxOf(r,g,b)-minOf(r,g,b); vividAt="rgb($r,$g,$b) at ($x,$y)" }
            if (r+g+b>bright) { bright=r+g+b; brightAt="rgb($r,$g,$b) at ($x,$y)" }
        }
        val seen="$coloured coloured of $samples samples in x $left-$right, y $top-$bottom of the ${screen.width}x${screen.height} screen; " +
            "most coloured $vividAt, brightest $brightAt; the map reports $drawn"
        android.util.Log.i("ScreenshotTest","$description: $seen")
        check(coloured>25) {"The 3D map drew nothing visible ($seen) for $description"}
    }
    @Test fun textbook() {
        val store=store()
        val set=store.library.first {it.kind==StudySetKind.BOOK}
        compose.setContent {StethoscoreApp(store)}
        // a textbook lives under Cards, as on iOS (StudyCategory.cards: Flashcards and Textbooks)
        compose.onNode(hasText("Cards") and hasClickAction()).performClick()
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText(set.name))
        // home's list runs on behind New set and the dock (T0112): bring the
        // row to the list's top, clear of them, before tapping it
        val list=compose.onNode(hasScrollToNodeAction())
        val rise=compose.onNodeWithText(set.name).fetchSemanticsNode().boundsInRoot.top-list.fetchSemanticsNode().boundsInRoot.top
        list.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.ScrollBy) { it(0f,rise) }
        compose.waitForIdle()
        compose.onNodeWithText(set.name).performClick()
        compose.onNodeWithContentDescription("Contents").assertIsDisplayed()
        shot("10-textbook")
    }
}

/**
 * The rotation, the display and the top activity at one moment (T0245), on one line tagged ROT-DIAG: in
 * the instrumentation output, so in the CI step's log between the test lines (INSTRUMENTATION_STATUS:
 * ROT-DIAG=...), and in logcat. [level] 0 is the two rotation settings and the display size; 1 adds the
 * window manager's rotation lines, the resumed activity, wakefulness and the device state; 2 (a failure)
 * adds the keyguard and the displays' states. capture-screenshots.sh prints the same fields between passes.
 */
internal object RotDiag {
    private const val TAG = "ROT-DIAG"
    fun snapshot(label: String, level: Int = 1) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        fun sh(command: String): String = try { device.executeShellCommand(command) } catch (e: Exception) { "error ${e.javaClass.simpleName}" }
        fun pick(text: String, pattern: String, max: Int = 10, separator: String = " ") =
            Regex(pattern).findAll(text).map { it.value.trim().take(160) }.distinct().take(max).joinToString(separator).ifEmpty { "-" }
        val parts = mutableListOf(
            "user_rotation=${sh("settings get system user_rotation").trim()} accelerometer_rotation=${sh("settings get system accelerometer_rotation").trim()}",
            "display=${device.displayWidth}x${device.displayHeight} orientation=${instrumentation.targetContext.resources.configuration.orientation}")
        if (level >= 1) {
            parts += "window: " + pick(sh("dumpsys window displays"),
                """\b(?:mCurrentRotation|mRotation|mUserRotationMode|mUserRotation|mLastOrientation|mFixedToUserRotation)=\S+|cur=\d+x\d+ app=\d+x\d+""")
            parts += "resumed: " + pick(sh("dumpsys activity activities"), """[A-Za-z]*ResumedActivity[^\n]*""", 4, " | ")
            parts += pick(sh("dumpsys power"), """mWakefulness=\w+""")
            parts += "device_state: " + sh("cmd device_state state").lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.take(3).joinToString(" | ").ifEmpty { "-" }
        }
        if (level >= 2) {
            parts += "keyguard: " + pick(sh("dumpsys window policy"), """\w*[Kk]eyguard\w*[Ss]howing\w*=\w+|mAwake=\w+""")
            parts += "displays: " + pick(sh("dumpsys display"), """\bmState=\w+""")
        }
        val line = "$label: ${parts.joinToString("; ")}".take(1800)
        Log.i(TAG, line)
        instrumentation.sendStatus(2, Bundle().apply { putString(TAG, line) })
    }
}

/**
 * The device turn capture-screenshots.sh set for this WindowShots pass: arguments rotation (the
 * user_rotation value, 0, 1 or 3), orient and naturalTall (whether the screen in use stands tall in its
 * natural way up). None of them when the class is run by hand, and then nothing here acts.
 */
internal object PassTurn {
    private val args get() = InstrumentationRegistry.getArguments()
    val rotation: Int? get() = args.getString("rotation")?.toIntOrNull()
    private val turned get() = (args.getString("orient") ?: "natural") != "natural"
    private val naturalTall get() = (args.getString("naturalTall") ?: "true") == "true"

    /** Whether the display stands as the pass wants: wide where a tall natural screen is turned (or a wide one is not), and the other way round. */
    fun holds(device: UiDevice) = (device.displayWidth > device.displayHeight) == (naturalTall == turned)

    /** The script's own two settings, again: a locked user rotation. */
    fun apply(device: UiDevice) {
        val r = rotation ?: return
        device.executeShellCommand("settings put system accelerometer_rotation 0")
        device.executeShellCommand("settings put system user_rotation $r")
    }

    /** Polls until [holds], for at most [millis]; whether it does. */
    fun await(device: UiDevice, millis: Long): Boolean {
        val end = SystemClock.uptimeMillis() + millis
        while (!holds(device)) {
            if (SystemClock.uptimeMillis() > end) return false
            SystemClock.sleep(100)
        }
        return true
    }
}

/**
 * Before every WindowShots test, outside the compose rule so before its activity starts: the device awake
 * with the keyguard away (a folded foldable sleeps), and the pass's turn set again. The script sets the turn
 * once, before the pass; on a phone only the first test kept it (T0245), so each test now starts from the
 * state the pass was meant to start from, and the activity launches into it. Logs the ROT-DIAG lines.
 */
class PassDisplay : TestWatcher() {
    override fun starting(description: Description) {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        device.executeShellCommand("input keyevent KEYCODE_WAKEUP")
        device.executeShellCommand("wm dismiss-keyguard")
        val end = SystemClock.uptimeMillis() + 5_000
        while (!device.executeShellCommand("dumpsys power").contains("mWakefulness=Awake") && SystemClock.uptimeMillis() < end) SystemClock.sleep(250)
        if (PassTurn.rotation == null) return
        PassTurn.apply(device)
        // a launcher that turns with the user rotation (a tablet's) has turned within this; a phone's stays natural until an activity is up
        val turned = PassTurn.await(device, 1_500)
        RotDiag.snapshot("${description.methodName} before launch (display as the pass wants: $turned)", 0)
    }
    override fun failed(e: Throwable, description: Description) = RotDiag.snapshot("${description.methodName} FAILED ${e.javaClass.simpleName}", 2)
    override fun finished(description: Description) = RotDiag.snapshot("${description.methodName} finished", 1)
}

/**
 * The window matrix's stills (T0139), named for the run's profile, posture and orientation,
 * which capture-screenshots.sh sets before it starts this class (the device turned, folded or
 * not), so a turn never recreates the composition under a still. Six key screens (home, the
 * library's Cards page, a checked quiz answer, a mock sitting with its "Part n", a revealed card,
 * settings; the tour has no draw-recall row on Android yet), each through the whole app, so the
 * frame, the dock or the rail and the hinge's clearance are the app's own.
 *
 * Arguments: profile, posture, orient (the names in each still), modes ("light" or "light,dark"),
 * and sizes ("WxH,..." in dp: each screen again at that window size by ForcedSize, for split
 * screen and free-form windows; none for the plain pass).
 */
@RunWith(AndroidJUnit4::class)
class WindowShots {
    // the pass's display first (the outer rule), then the activity: order 0 runs outside order 1
    @get:Rule(order = 0) val passDisplay = PassDisplay()
    @get:Rule(order = 1) val compose = createComposeRule()
    @get:Rule(order = 1) val learnClosed = LearnRouterClosed()
    private val args get() = InstrumentationRegistry.getArguments()
    private fun arg(name:String,default:String)=args.getString(name)?.takeIf { it.isNotBlank() } ?: default
    private val directory="/sdcard/Download/stethoscore-screenshots/window"
    private val dark=androidx.compose.runtime.mutableStateOf(false)
    private val size=androidx.compose.runtime.mutableStateOf<androidx.compose.ui.unit.DpSize?>(null)

    private fun store():StudyStore {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        return StudyStore(File(context.cacheDir,"window-${System.nanoTime()}")).also { s ->
            s.loadExamples()
            // a mock needs ten questions at least
            s.addSet(StudySet(name="Renal drill",subject="Nephrology",kind=StudySetKind.MCQ,
                questions=List(12) { i -> MCQQuestion(stem="Drill question ${i+1}?",options=listOf("One","Two","Three","Four"),correctIndex=i%4) }))
        }
    }

    private fun waitFor(what:String,matcher:SemanticsMatcher) {
        try { compose.waitUntil(20_000) { compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() } }
        catch (e:ComposeTimeoutException) { throw AssertionError("no $what",e) }
    }
    private fun tap(what:String,matcher:SemanticsMatcher) {
        waitFor(what,matcher)
        val node=compose.onAllNodes(matcher).onFirst()
        try { node.performScrollTo() } catch (_:AssertionError) {}
        node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick)
        compose.waitForIdle()
    }
    private fun tab(name:String)=hasText(name) and SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.Role,androidx.compose.ui.semantics.Role.Tab)

    /** Sizes from "412x302,302x412" (dp). */
    private fun sizes():List<androidx.compose.ui.unit.DpSize?> {
        val listed=arg("sizes","").split(',').map { it.trim() }.filter { it.isNotEmpty() }.map { s ->
            val (w,h)=s.split('x').map { it.toFloat() }
            androidx.compose.ui.unit.DpSize(w.dp,h.dp)
        }
        return listed.ifEmpty { listOf(null) }
    }

    /**
     * [screen] in each mode and each size, the app composed afresh for each, [steps] bringing it
     * to the state shot. A turned still must be wider than tall where the screen's natural way is tall,
     * and taller than wide where it is wide (naturalTall, the script's measure for this pass).
     */
    private fun shoot(screen:String,initial:String="home",steps:(StudyStore) -> Unit={}) {
        val modes=arg("modes","light").split(',').map { it.trim() }
        val profile=arg("profile","device"); val posture=arg("posture","open"); val orient=arg("orient","natural")
        val stores=HashMap<Pair<Boolean,androidx.compose.ui.unit.DpSize?>,StudyStore>()
        val device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        // The turn is set before the activity starts (PassDisplay). If it is gone anyway, put it back before
        // the content is set: a turn after setContent recreates the activity and drops the content.
        if (orient!="natural" && PassTurn.rotation!=null && !PassTurn.holds(device)) {
            PassTurn.apply(device)
            val back=PassTurn.await(device,8_000)
            SystemClock.sleep(1_000) // the activity the turn recreates
            compose.waitForIdle()
            RotDiag.snapshot("$screen $orient: not turned after launch, turn set again (display now as the pass wants: $back)")
        }
        compose.setContent {
            val d=dark.value; val z=size.value
            androidx.compose.runtime.key(d,z) {
                val s=stores.getOrPut(d to z) { store() }
                if(z==null) StethoscoreApp(s,initialScreen=initial,forceDark=d)
                else androidx.compose.ui.test.DeviceConfigurationOverride(androidx.compose.ui.test.DeviceConfigurationOverride.ForcedSize(z)) {
                    StethoscoreApp(s,initialScreen=initial,forceDark=d)
                }
            }
        }
        for (z in sizes()) for (m in modes) {
            compose.runOnIdle { dark.value=m=="dark"; size.value=z }
            compose.waitForIdle()
            InstrumentationRegistry.getInstrumentation().runOnMainSync { com.stethoscore.app.ui.learn.LearnRouter.close() }
            RotDiag.snapshot("$screen $m size ${z?.let { "${it.width.value.toInt()}x${it.height.value.toInt()}" } ?: orient} start")
            steps(stores.getValue((m=="dark") to z))
            // a still of a screen with no compose root on it (no activity up, the device asleep) is a still of nothing:
            // every step above that reads the tree fails then, but "settings" has none, so this does for it (throws "No compose hierarchies found")
            check(compose.onAllNodes(isRoot()).fetchSemanticsNodes().isNotEmpty()) { "$screen $orient: no compose root to shoot" }
            val where=z?.let { "${it.width.value.toInt()}x${it.height.value.toInt()}" } ?: orient
            ScreenshotTest.still(compose,directory,"w-$profile-$posture-$where-$screen-$m")
            // the script measures the screen in use for each pass (a fold's cover screen stands tall, its open screen wide)
            if (z==null && orient!="natural") {
                val tall=arg("naturalTall","true")=="true"
                if ((device.displayWidth>device.displayHeight)!=tall) RotDiag.snapshot("$screen $orient: the display is not as the pass wants",2)
                check((device.displayWidth>device.displayHeight)==tall) {
                    "$screen $orient: the still is ${device.displayWidth}x${device.displayHeight}, not ${if(tall) "wider than tall" else "taller than wide"}" }
            }
        }
    }

    @Test fun home() = shoot("home") { waitFor("home's account menu",hasContentDescription("Account and settings")) }
    @Test fun library() = shoot("library") { tap("the Cards tab",tab("Cards")) }
    @Test fun quizChecked() = shoot("quiz-checked") { s ->
        val set=s.library.first { it.kind==StudySetKind.MCQ }
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText(set.name))
        tap("the set's row",hasText(set.name) and hasClickAction())
        val q=set.questions.first()
        tap("the right answer",hasClickAction() and hasContentDescription(": "+q.options[q.correctIndex],substring=true))
        tap("Check answer",hasText(ChartQuiz.primaryTitle(false,true,false,false,false)) and hasClickAction())
        waitFor("Next question",hasText(ChartQuiz.primaryTitle(true,true,false,false,false)))
    }
    @Test fun mockSitting() = shoot("mock-sitting","mock") {
        tap("Start mock",hasText("Start mock") and hasClickAction())
        waitFor("the sitting's first question",hasText("Question 1 of",substring=true))
        check(compose.onAllNodes(hasText("Block",substring=true)).fetchSemanticsNodes().isEmpty()) { "the mock says Part, never Block" }
    }
    @Test fun ankiRevealed() = shoot("anki-revealed") { s ->
        tap("the Cards tab",tab("Cards"))
        val set=s.library.first { it.kind==StudySetKind.ANKI }
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText(set.name))
        tap("the deck's row",hasText(set.name) and hasClickAction())
        tap("Reveal",hasText("Reveal") and hasClickAction())
        waitFor("the ratings",hasContentDescription("Good, back in", substring = true))
    }
    @Test fun settings() = shoot("settings","settings")
}
