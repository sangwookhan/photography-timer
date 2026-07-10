// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * PTIMER-217: behavioral contract for the shared persistence writer. These
 * exercise real deferral and real concurrency (no `Dispatchers.Unconfined`),
 * because the writer's whole point is off-thread, ordered execution.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PersistenceWriterTest {

    private fun writer() = ScopePersistenceWriter(Dispatchers.IO.limitedParallelism(1))

    /** Drains every write submitted so far by running an ordered no-op behind them. */
    private fun ScopePersistenceWriter.drain() = runBlocking { readOrdered { } }

    @Test
    fun submitDefersTheWriteInsteadOfRunningItInline() {
        // Hold the single worker busy, so a freshly submitted write cannot have
        // run by the time submit() returns.
        val gate = CountDownLatch(1)
        val writer = writer()
        val ran = AtomicInteger(0)

        writer.submit { gate.await(); ran.incrementAndGet() } // occupies the worker
        writer.submit { ran.incrementAndGet() }               // queued behind it

        assertEquals(0, ran.get()) // not inline while the worker is blocked
        gate.countDown()
        writer.drain()
        assertEquals(2, ran.get())
    }

    @Test
    fun writesRunOneAtATimeInSubmissionOrder() {
        // Distinct payloads (0..19) recorded as they execute; a slow body makes
        // any lost serialization show up as reordering or overlap.
        val writer = writer()
        val recorded = Collections.synchronizedList(mutableListOf<Int>())
        val inFlight = AtomicInteger(0)
        val maxConcurrent = AtomicInteger(0)

        repeat(20) { i ->
            writer.submit {
                val c = inFlight.incrementAndGet()
                maxConcurrent.updateAndGet { m -> maxOf(m, c) }
                Thread.sleep(2)
                recorded.add(i)
                inFlight.decrementAndGet()
            }
        }
        writer.drain()

        assertEquals((0 until 20).toList(), recorded.toList())
        assertEquals(1, maxConcurrent.get())
    }

    @Test
    fun writersSharingOneWorkerStaySerialAcrossAGenerationSwap() {
        // A configuration-change swap: an "old" and a "new" writer over the SAME
        // worker. Because they share it, the old generation's queued write cannot
        // overtake or run concurrently with the new one — last submitted, last run.
        val dispatcher = Dispatchers.IO.limitedParallelism(1)
        val oldGen = ScopePersistenceWriter(dispatcher)
        val newGen = ScopePersistenceWriter(dispatcher)
        val recorded = Collections.synchronizedList(mutableListOf<String>())

        oldGen.submit { Thread.sleep(4); recorded.add("old") }
        newGen.submit { recorded.add("new") }
        runBlocking { newGen.readOrdered { } } // drain both

        assertEquals(listOf("old", "new"), recorded.toList())
    }

    @Test
    fun readOrderedRunsAfterAPendingWriteAndObservesItsEffect() {
        // The configuration-change gap: a write is submitted but slow to commit,
        // then a fresh generation reads. The ordered read must run AFTER the
        // pending write and see its value, never the stale one.
        val writer = writer()
        val committed = AtomicReference("stale")

        writer.submit { Thread.sleep(50); committed.set("latest") } // old gen, slow commit
        val seen = runBlocking { writer.readOrdered { committed.get() } } // new gen read

        assertEquals("latest", seen)
    }
}
