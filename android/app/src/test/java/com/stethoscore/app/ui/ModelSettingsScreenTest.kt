package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.stethoscore.app.BuildConfig
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMChoice
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ModelSettingsScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun service(key: String, spent: Long = 0, server: FakeServer = FakeServer()) =
        LLMService(LLMService.MemoryPrefs(), key, { null }, FakeServer.BASE, server, OwnerSpend(OwnerSpend.MemoryStore(spent)))

    @Test fun theDefaultBuildShowsNoSpendAndSaysTheCloudIsPro() {
        val server = FakeServer()
        val llm = service(BuildConfig.OWNER_KEY, server = server)
        compose.setContent { StethoscoreTheme { ModelSettingsScreen({}, llm) } }
        compose.onNodeWithText("Off").assertExists()
        compose.onNodeWithText("Stethoscore Cloud · Pro").performClick()
        assertEquals(LLMChoice.cloud, llm.choice())
        // the status line, and the note under the choice
        assertEquals(2, compose.onAllNodesWithText("Stethoscore Cloud is part of Pro.", useUnmergedTree = true).fetchSemanticsNodes().size)
        compose.onNodeWithText("Owner key spend", useUnmergedTree = true).assertDoesNotExist()
        assertTrue(server.requests.isEmpty())
    }

    @Test fun thePersonalBuildShowsItsSpendAndCap() {
        val llm = service(FakeServer.standInKey(), spent = 3_400_000)
        compose.setContent { StethoscoreTheme { ModelSettingsScreen({}, llm) } }
        compose.onNodeWithText("Owner key spend", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("$3.40 of $20.00", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Ready", useUnmergedTree = true).assertExists()
    }

    @Test fun atTheCapTheScreenSaysTheModesAreStopped() {
        val llm = service(FakeServer.standInKey(), spent = 20_000_000)
        compose.setContent { StethoscoreTheme { ModelSettingsScreen({}, llm) } }
        compose.onNodeWithText("$20.00 of $20.00", useUnmergedTree = true).assertExists()
        compose.onNodeWithText(OwnerSpend.CAP_REACHED, useUnmergedTree = true).assertExists()
    }
}
