package com.stethoscore.app.ui.learn

import org.junit.rules.ExternalResource

/**
 * Every test that drives the app starts, and ends, with the learning sheet shut.
 *
 * LearnRouter is one object for the whole app (iOS LearnRouter.shared), and the
 * test classes share the JVM: a sheet one test leaves open (opening a textbook
 * for the first time puts Guess first over it) lies over the next test's
 * screens, with its Back and Done in front of theirs.
 */
class LearnRouterClosed : ExternalResource() {
    override fun before() = LearnRouter.close()
    override fun after() = LearnRouter.close()
}
