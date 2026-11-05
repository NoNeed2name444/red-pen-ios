package com.stethoscore.app

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

/** AppLink.parse as iOS's (AppLink.swift:39-70), checked as PlatformTests.swift:20-45 checks it. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AppLinkTest {
    private val id = UUID.randomUUID().toString()

    @Test fun dueLinks() {
        assertEquals(AppLink.ReviewDue, AppLink.parse("redpen://due"))
        assertEquals(AppLink.ReviewDue, AppLink.parse("stethoscore://due"))
        assertEquals(AppLink.ReviewDue, AppLink.parse("stethoscore://review"))
        assertEquals("scheme and host in any case", AppLink.ReviewDue, AppLink.parse("Stethoscore://DUE"))
    }

    @Test fun examLinks() {
        assertEquals(AppLink.ExamPlan, AppLink.parse("redpen://exam"))
        assertEquals(AppLink.ExamPlan, AppLink.parse("stethoscore://exam"))
        assertEquals(AppLink.ExamPlan, AppLink.parse("stethoscore://countdown"))
    }

    @Test fun setLinks() {
        assertEquals(AppLink.OpenSet(id), AppLink.parse("redpen://set/$id"))
        assertEquals(AppLink.OpenSet(id), AppLink.parse("stethoscore://set/$id"))
        assertEquals("by query", AppLink.OpenSet(id), AppLink.parse("redpen://open?id=$id"))
        assertEquals("iOS writes upper case", AppLink.OpenSet(id), AppLink.parse("redpen://set/${id.uppercase()}"))
        assertEquals("the path before the query", AppLink.OpenSet(id), AppLink.parse("redpen://set/$id?id=not-a-uuid"))
    }

    @Test fun badLinksAreNotRouted() {
        listOf(
            "redpen://set/not-a-uuid", "redpen://set", "redpen://open?id=", "redpen://set/1-1-1-1-1",
            "redpen://auth?code=abc", "https://example.com/due", "redpen://somewhere", "redpen://",
            "stethoscore:due", "stethoscore:///due", "", "not a link", "redpen://due path with spaces",
            // iOS routes these; Android does not yet
            "redpen://quiz?subject=cardiology", "redpen://search?q=murmur", "redpen://new", "redpen://item/card/$id/-",
        ).forEach { assertNull(it, AppLink.parse(it)) }
    }

    @Test fun roundTrip() {
        listOf(AppLink.ReviewDue, AppLink.OpenSet(id), AppLink.ExamPlan).forEach { assertEquals(it.url, it, AppLink.parse(it.url)) }
    }

    @Test fun intents() {
        val due = Intent(Intent.ACTION_VIEW, Uri.parse("stethoscore://due"))
        assertEquals(AppLink.ReviewDue, AppLink.from(due))
        assertTrue(AppLink.isLink(due))
        assertNull("only VIEW", AppLink.from(Intent(Intent.ACTION_SEND, Uri.parse("stethoscore://due"))))
        assertNull(AppLink.from(null))
        val file = Intent(Intent.ACTION_VIEW, Uri.parse("content://downloads/deck.csv"))
        assertNull(AppLink.from(file))
        assertFalse("a file is still a file", AppLink.isLink(file))
        assertTrue("an unrouted link is not taken as a file", AppLink.isLink(Intent(Intent.ACTION_VIEW, Uri.parse("redpen://quiz"))))
    }

    @Test fun coldStartFollowsTheLinkOnce() {
        val due = Intent(Intent.ACTION_VIEW, Uri.parse("stethoscore://due"))
        assertEquals(AppLink.ReviewDue, MainActivity.coldLink(due, restored = false))
        assertNull("a recreated activity has had it", MainActivity.coldLink(due, restored = true))
        val fromRecents = Intent(due).addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)
        assertNull("reopened from Recents: not played again", MainActivity.coldLink(fromRecents, restored = false))
        assertNull(MainActivity.coldLink(null, restored = false))
    }

    @Test fun coldStartScreen() {
        assertEquals("due", AppLink.initialScreen(AppLink.ReviewDue))
        assertEquals("home", AppLink.initialScreen(AppLink.ExamPlan))
        assertEquals("home", AppLink.initialScreen(AppLink.OpenSet(id)))
        assertEquals("home", AppLink.initialScreen(null))
    }
}
