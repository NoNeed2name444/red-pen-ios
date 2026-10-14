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
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.regex.Pattern

@RunWith(AndroidJUnit4::class)
class ScreenshotTest {
    @get:Rule val compose = createComposeRule()
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
        compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {QuizScreen(set,store,{})}}}}
        shot("03-questions")
        compose.onNodeWithText(set.questions.first().options[set.questions.first().correctIndex]).performScrollTo().performClick()
        compose.onNodeWithText("Check answer").performScrollTo().performClick()
        compose.onNodeWithText("Well reasoned.").performScrollTo().assertIsDisplayed()
        check(store.answerHistory[set.questions.first().id]?.last()==true)
        shot("04-answer-explanation")
    }
    @Test fun cardsRevealAndSchedule() {
        val store=store();val set=store.library.first {it.kind==StudySetKind.ANKI}
        compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {CardsScreen(set,store,{})}}}}
        shot("05-cards")
        compose.onNodeWithText("Reveal answer").performScrollTo().performClick()
        shot("06-card-revealed")
        compose.onNodeWithText("Good").performScrollTo().performClick()
        check(store.reviews.isNotEmpty())
    }
    @Test fun osce() { val store=store();val set=store.library.first {it.kind==StudySetKind.OSCE};compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {ClinicalScreen(set,store,{})}}}};shot("07-osce") }
    @Test fun cases() { val store=store();val set=store.library.first {it.kind==StudySetKind.CASES};compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {Box(Modifier.fillMaxSize().safeDrawingPadding()) {ClinicalScreen(set,store,{})}}}};shot("08-cases") }
    @Test fun ideas() {
        val store=store()
        // Linked ideas so the screenshot shows the list and the map, not the empty state.
        val heart=Note(title="Heart failure",tags=listOf("cardio"))
        val bnp=Note(title="BNP",body="Rises with ventricular stretch.",links=listOf(heart.id),tags=listOf("labs"))
        val edema=Note(title="Pulmonary oedema",links=listOf(heart.id,bnp.id),tags=listOf("cardio"))
        val diuretics=Note(title="Loop diuretics",links=listOf(edema.id),tags=listOf("drugs"))
        listOf(heart,bnp,edema,diuretics).forEach(store::saveNote)
        compose.setContent {StethoscoreApp(store,initialScreen="ideas")}
        compose.onNodeWithText("4 ideas · 4 links").assertIsDisplayed()
        shot("09-ideas")
        compose.onNodeWithText("2D map").performClick()
        compose.onNodeWithContentDescription("2D map of 4 ideas",substring=true).assertIsDisplayed()
        shot("11-ideas-map")
    }
    @Test fun textbook() {
        val store=store()
        val set=store.library.first {it.kind==StudySetKind.BOOK}
        compose.setContent {StethoscoreApp(store)}
        compose.onNodeWithText(set.name).performScrollTo().performClick()
        compose.onNodeWithText("Table of contents").assertIsDisplayed()
        shot("10-textbook")
    }
}
