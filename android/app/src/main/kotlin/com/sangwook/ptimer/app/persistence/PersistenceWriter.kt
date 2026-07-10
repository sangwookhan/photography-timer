// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Runs a persistence write off the calling thread (PTIMER-217). The concrete
 * DataStore stores keep their synchronous, blocking contracts (needed by their
 * round-trip tests); callers hand the blocking write to a writer so it never
 * runs on the main thread.
 */
fun interface PersistenceWriter {
    /** Submit [write] to run on the writer. Returns immediately. */
    fun submit(write: () -> Unit)
}

/**
 * A [PersistenceWriter] backed by an explicit single-worker [dispatcher], so
 * writes and ordered reads share one serial queue. Writes launched via [submit]
 * and reads run via [readOrdered] execute one at a time on [dispatcher] in the
 * order they were dispatched. Production uses [AppPersistenceWriter]; tests pass
 * a dispatcher they own (real single-thread IO, or a test dispatcher) so they
 * can await and assert ordering.
 */
class ScopePersistenceWriter(private val dispatcher: CoroutineDispatcher) : PersistenceWriter {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    override fun submit(write: () -> Unit) {
        scope.launch { write() }
    }

    /**
     * Runs [read] on the same serial worker as writes and returns its result,
     * suspending the caller (off-main) until it completes. Because it shares the
     * write queue, it runs after every write submitted before this call — so a
     * read never observes state behind a write that was already submitted. Used
     * for configuration-change bootstrap/restore reads, which must not run ahead
     * of a pending write from the generation being replaced.
     */
    suspend fun <T> readOrdered(read: () -> T): T = withContext(dispatcher) { read() }
}

/**
 * The process-wide single writer for the DataStore-backed stores (PTIMER-217).
 *
 * One `limitedParallelism(1)` IO worker owned for the whole process — mirroring
 * the process-singleton alarm player — rather than a fresh scope per store or
 * view-model instance. This matters across configuration-change recreations of
 * the composition:
 *
 * - Exactly one writer exists no matter how many times the composition is
 *   recreated, so a stale per-instance writer can never linger and race a fresh
 *   one; there is no scope to leak.
 * - Writes and ordered reads run one at a time on the shared worker in dispatch
 *   order (FIFO, no coalescing): the latest write commits last, and a
 *   configuration-change [readOrdered] observes every write submitted before it
 *   — closing the write-then-read gap that a bypassing IO read would leave.
 *
 * The write is asynchronous: `submit` returns before the store commits, so this
 * does not reproduce the old blocking write's commit-on-return durability. It
 * narrows the loss window to the interval between submission and commit (a few
 * milliseconds for these small payloads) while keeping the main thread free.
 */
object AppPersistenceWriter : PersistenceWriter {
    @OptIn(ExperimentalCoroutinesApi::class)
    private val delegate = ScopePersistenceWriter(Dispatchers.IO.limitedParallelism(1))

    override fun submit(write: () -> Unit) = delegate.submit(write)

    /** Ordered read on the shared writer; see [ScopePersistenceWriter.readOrdered]. */
    suspend fun <T> readOrdered(read: () -> T): T = delegate.readOrdered(read)
}
