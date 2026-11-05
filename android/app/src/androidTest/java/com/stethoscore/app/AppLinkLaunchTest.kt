package com.stethoscore.app

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * stethoscore://due, the Due cards widget's tap, reaches the due screen when it
 * starts the app (cold) and when the app is already open on home (warm: the same
 * activity takes it in onNewIntent, as the widgets' SINGLE_TOP | CLEAR_TOP intents will).
 * The library is empty, so the due screen says it has nothing due, words home never shows.
 */
@RunWith(AndroidJUnit4::class)
class AppLinkLaunchTest {
    @get:Rule val compose = createEmptyComposeRule()
    @get:Rule val learnClosed = LearnRouterClosed()
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val dueScreen: SemanticsMatcher = hasText("Nothing due today")

    @Before fun emptyLibrary() {
        ProcessStore.forget()
        instrumentation.targetContext.filesDir.listFiles()?.forEach { it.deleteRecursively() }
        AppLinks.pending = null
    }

    private fun link(flags: Int = 0) = Intent(Intent.ACTION_VIEW, Uri.parse("stethoscore://due"))
        .setClassName(instrumentation.targetContext, MainActivity::class.java.name).addFlags(flags)

    private fun shown(matcher: SemanticsMatcher) = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()

    private fun waitForDue(how: String) {
        try { compose.waitUntil(20_000) { shown(dueScreen) } } catch (e: androidx.compose.ui.test.ComposeTimeoutException) { throw AssertionError("$how: no due screen", e) }
    }

    @Test fun coldStartOpensDue() {
        ActivityScenario.launch<MainActivity>(link()).use { waitForDue("cold") }
    }

    @Test fun linkWhileOpenOpensDue() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            compose.waitForIdle()
            assertFalse("home first", shown(dueScreen))
            var before: MainActivity? = null
            scenario.onActivity { before = it }
            instrumentation.targetContext.startActivity(link(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP))
            waitForDue("warm")
            var after: MainActivity? = null
            scenario.onActivity { after = it }
            // the open activity took the link (onNewIntent), not a second one started cold
            assertNotNull(before)
            assertSame("the same activity", before, after)
        }
    }
}
