package com.stethoscore.app

import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.safeDrawingPadding
import android.os.SystemClock
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
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
    private fun shot(name:String) {
        compose.waitForIdle()
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        require(name.matches(Regex("[a-z0-9-]+")))
        val device=UiDevice.getInstance(instrumentation)
        device.waitForIdle()
        val directory="/sdcard/Download/stethoscore-screenshots"
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
    @Test fun homeLight() { val store=store();compose.setContent {StethoscoreApp(store)};compose.onNodeWithText("Stethoscore").assertIsDisplayed();shot("01-home-light") }
    @Test fun homeDark() { val store=store();compose.setContent {StethoscoreApp(store,forceDark=true)};shot("02-home-dark") }
    @Test fun quizAnswerPersists() {
        val store=store();val set=store.library.first {it.kind==StudySetKind.MCQ}
        compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {QuizScreen(set,store,{},minReadSeconds=0)}}}}
        shot("03-questions")
        compose.onNodeWithText(set.questions.first().options[set.questions.first().correctIndex]).performScrollTo().performClick()
        compose.onNodeWithText("Check answer").performScrollTo().performClick()
        compose.onNodeWithText("Right!").performScrollTo().assertIsDisplayed()
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
        compose.onNodeWithContentDescription("Good").assertIsDisplayed().performClick()
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
        compose.waitUntil(120_000) { compose.onAllNodesWithText("1,000,000 nodes",substring=true).fetchSemanticsNodes().isNotEmpty() }
        compose.waitUntil(60_000) { compose.onAllNodesWithText(" fps · ",substring=true).fetchSemanticsNodes().any { node ->
            node.config.getOrElseNullable(androidx.compose.ui.semantics.SemanticsProperties.Text) { null }?.joinToString()?.trim()?.startsWith("0 fps")==false } }
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
