package com.stethoscore.app

import org.junit.After
import org.junit.Assert.assertSame
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.Callable
import java.util.concurrent.Executors

class ProcessStoreTest {
    @get:Rule val folder = TemporaryFolder()

    @After fun tearDown() = ProcessStore.forget()

    @Test fun twoStartsShareOneStore() {
        val dir = folder.newFolder()
        val first = ProcessStore.get(dir)
        val second = ProcessStore.get(dir)
        assertSame(first, second)
    }

    @Test fun startsAtOnceShareOneStore() {
        val dir = folder.newFolder()
        val pool = Executors.newFixedThreadPool(8)
        try {
            val stores = pool.invokeAll(List(32) { Callable { ProcessStore.get(dir) } }).map { it.get() }
            stores.forEach { assertSame(stores.first(), it) }
        } finally {
            pool.shutdown()
        }
    }
}
