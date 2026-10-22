package com.stethoscore.app

import androidx.test.platform.app.InstrumentationRegistry
import com.stethoscore.app.ui.learn.LearnRouter
import org.junit.rules.ExternalResource

/**
 * Every test that drives the app starts, and ends, with the learning sheet shut.
 *
 * LearnRouter is one object for the whole app (iOS LearnRouter.shared), and an
 * instrumented run keeps one process for all its tests: a sheet one test leaves
 * open (ScreenshotTest.textbook opens a textbook for the first time, which puts
 * Guess first over it) covers every later test's screens and screenshots.
 */
class LearnRouterClosed : ExternalResource() {
    private fun close() = InstrumentationRegistry.getInstrumentation().runOnMainSync { LearnRouter.close() }
    override fun before() = close()
    override fun after() = close()
}
