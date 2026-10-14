package com.stethoscore.app

import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

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
        val directory="/sdcard/Download/stethoscore-screenshots"
        device.executeShellCommand("mkdir -p $directory")
        device.executeShellCommand("screencap -p $directory/$name.png")
        val size = device.executeShellCommand("stat -c %s $directory/$name.png").trim().toLongOrNull()
        check(size != null && size > 0) { "Screenshot was not written: $name" }
    }
    @Test fun homeLight() { val store=store();compose.setContent {StethoscoreApp(store)};compose.onNodeWithText("Stethoscore").assertIsDisplayed();shot("01-home-light") }
    @Test fun homeDark() { val store=store();compose.setContent {StethoscoreApp(store,forceDark=true)};shot("02-home-dark") }
    @Test fun quizAnswerPersists() {
        val store=store();val set=store.library.first {it.kind==StudySetKind.MCQ}
        compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {QuizScreen(set,store,{})}}}
        shot("03-questions")
        compose.onNodeWithText(set.questions.first().options[set.questions.first().correctIndex]).performScrollTo().performClick()
        compose.onNodeWithText("Check answer").performScrollTo().performClick()
        compose.onNodeWithText("Well reasoned.").performScrollTo().assertIsDisplayed()
        check(store.answerHistory[set.questions.first().id]?.last()==true)
        shot("04-answer-explanation")
    }
    @Test fun cardsRevealAndSchedule() {
        val store=store();val set=store.library.first {it.kind==StudySetKind.ANKI}
        compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {CardsScreen(set,store,{})}}}
        shot("05-cards")
        compose.onNodeWithText("Reveal answer").performScrollTo().performClick()
        shot("06-card-revealed")
        compose.onNodeWithText("Good").performScrollTo().performClick()
        check(store.reviews.isNotEmpty())
    }
    @Test fun osce() { val store=store();val set=store.library.first {it.kind==StudySetKind.OSCE};compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {ClinicalScreen(set,store,{})}}};shot("07-osce") }
    @Test fun cases() { val store=store();val set=store.library.first {it.kind==StudySetKind.CASES};compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {ClinicalScreen(set,store,{})}}};shot("08-cases") }
    @Test fun ideas() { val store=store();compose.setContent {StethoscoreApp(store,initialScreen="ideas")};shot("09-ideas") }
    @Test fun textbook() { val store=store();val set=store.library.first {it.kind==StudySetKind.BOOK};compose.setContent {StethoscoreTheme {Surface(Modifier.fillMaxSize()) {ClinicalScreen(set,store,{})}}};shot("10-textbook") }
}
