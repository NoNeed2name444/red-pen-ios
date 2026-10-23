package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import com.stethoscore.app.BuildConfig
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// Settings (the owner, 22 Oct): no AI models screen and no writer to choose.
// Stethoscore Cloud's status and, in the personal build, the owner key's spend
// against its $20.00 cap are plain rows in Settings itself, reached by
// scrolling Settings, with nothing sent to show them.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SettingsCloudRowsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun service(key: String, spent: Long = 0, server: FakeServer = FakeServer()) =
        LLMService(key, { null }, FakeServer.BASE, server, OwnerSpend(OwnerSpend.MemoryStore(spent)))

    private fun settings(llm: LLMService) = compose.setContent {
        StethoscoreTheme { SettingsScreen(false, {}, {}, {}, {}, {}, onExam = {}, cloud = llm) }
    }

    @Test fun theDefaultBuildSaysTheCloudIsProWithNoModelsScreen() {
        val server = FakeServer()
        settings(service(BuildConfig.OWNER_KEY, server = server))
        compose.onNodeWithTag("cloudRows").performScrollTo()
        compose.onNodeWithText("Stethoscore Cloud is part of Pro.", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Owner key spend", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("AI models", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag("aiModels").assertDoesNotExist()
        assertTrue(server.requests.isEmpty())
    }

    @Test fun thePersonalBuildShowsItsSpendAndCap() {
        settings(service(FakeServer.standInKey(), spent = 3_400_000))
        compose.onNodeWithTag("cloudRows").performScrollTo()
        compose.onNodeWithText("Owner key spend", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("$3.40 of $20.00", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Ready", useUnmergedTree = true).assertExists()
    }

    @Test fun atTheCapSettingsSaysTheModesAreStopped() {
        settings(service(FakeServer.standInKey(), spent = 20_000_000))
        compose.onNodeWithTag("cloudRows").performScrollTo()
        compose.onNodeWithText("$20.00 of $20.00", useUnmergedTree = true).assertExists()
        compose.onNodeWithText(OwnerSpend.CAP_REACHED, useUnmergedTree = true).assertExists()
    }
}
