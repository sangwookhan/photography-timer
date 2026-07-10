// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import com.sangwook.ptimer.core.persistence.CustomFilmLibraryStoring
import com.sangwook.ptimer.core.persistence.PersistentCustomFilmLibrarySnapshot
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.FilmProductionStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PTIMER-217: the async-write decorator delegates reads inline and hands writes
 * to its injected [PersistenceWriter]. A manually-pumped writer stands in for
 * the process writer so the tests verify real deferral (writes do not run until
 * pumped) and submission-order delivery — without `Dispatchers.Unconfined`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AsyncWriteCustomFilmLibraryStoreTest {

    /** Records writes and runs them only when [pump] is called, in FIFO order. */
    private class ManualWriter : PersistenceWriter {
        private val queued = ArrayDeque<() -> Unit>()
        val pending: Int get() = queued.size
        override fun submit(write: () -> Unit) { queued.addLast(write) }
        fun pump() { while (queued.isNotEmpty()) queued.removeFirst().invoke() }
    }

    /** Commits slowly, so a bypassing read could observe the pre-write value. */
    private class SlowStore : CustomFilmLibraryStoring {
        @Volatile var current: PersistentCustomFilmLibrarySnapshot? = null
        override fun loadSnapshot() = current
        override fun saveSnapshot(snapshot: PersistentCustomFilmLibrarySnapshot) {
            Thread.sleep(50); current = snapshot
        }
        override fun clearSnapshot() { current = null }
    }

    private class RecordingStore : CustomFilmLibraryStoring {
        var toLoad: PersistentCustomFilmLibrarySnapshot? = null
        val saved = mutableListOf<PersistentCustomFilmLibrarySnapshot>()
        var cleared = false
        override fun loadSnapshot() = toLoad
        override fun saveSnapshot(snapshot: PersistentCustomFilmLibrarySnapshot) { saved += snapshot }
        override fun clearSnapshot() { cleared = true }
    }

    /** A structurally-distinct snapshot keyed by [id] so ordering is observable. */
    private fun snapshot(id: String) = PersistentCustomFilmLibrarySnapshot(
        films = listOf(
            FilmIdentity(
                id = id,
                kind = FilmIdentityKind.custom,
                canonicalStockName = id,
                aliases = emptyList(),
                iso = 100,
                productionStatus = FilmProductionStatus.current,
                profiles = emptyList(),
            ),
        ),
    )

    @Test
    fun loadDelegatesToTheInnerStoreInline() {
        val inner = RecordingStore()
        val store = AsyncWriteCustomFilmLibraryStore(inner, ManualWriter())
        assertNull(store.loadSnapshot())

        inner.toLoad = snapshot("a")
        assertEquals(snapshot("a"), store.loadSnapshot())
    }

    @Test
    fun savesAreDeferredUntilTheWriterRuns() {
        val inner = RecordingStore()
        val writer = ManualWriter()
        val store = AsyncWriteCustomFilmLibraryStore(inner, writer)

        store.saveSnapshot(snapshot("a"))

        // Deferred: nothing reached the inner store yet.
        assertTrue(inner.saved.isEmpty())
        assertEquals(1, writer.pending)

        writer.pump()
        assertEquals(listOf(snapshot("a")), inner.saved)
    }

    @Test
    fun writesFromTwoGenerationsSharingOneWriterArriveInSubmissionOrder() {
        // A configuration-change swap: old + new decorator over the SAME writer.
        val inner = RecordingStore()
        val writer = ManualWriter()
        val oldGen = AsyncWriteCustomFilmLibraryStore(inner, writer)
        val newGen = AsyncWriteCustomFilmLibraryStore(inner, writer)

        oldGen.saveSnapshot(snapshot("old"))
        newGen.saveSnapshot(snapshot("new"))
        writer.pump()

        // The newer snapshot lands last, so it wins in the store.
        assertEquals(listOf(snapshot("old"), snapshot("new")), inner.saved)
    }

    @Test
    fun aFreshBootstrapReadObservesAPendingLibraryWrite() {
        // The configuration-change gap end-to-end: the replaced generation's
        // library write is slow to commit; the fresh generation's bootstrap-style
        // ordered read (through the SAME writer) must return the latest snapshot,
        // never the stale one — a just-created/deleted film cannot revert.
        val writer = ScopePersistenceWriter(Dispatchers.IO.limitedParallelism(1))
        val inner = SlowStore()
        val store = AsyncWriteCustomFilmLibraryStore(inner, writer)

        store.saveSnapshot(snapshot("latest"))                                  // old gen
        val loaded = runBlocking { writer.readOrdered { inner.loadSnapshot() } } // new gen bootstrap

        assertEquals(snapshot("latest"), loaded)
    }

    @Test
    fun clearIsDeferredThenReachesTheInnerStore() {
        val inner = RecordingStore()
        val writer = ManualWriter()
        val store = AsyncWriteCustomFilmLibraryStore(inner, writer)

        store.clearSnapshot()
        assertTrue(!inner.cleared)

        writer.pump()
        assertTrue(inner.cleared)
    }
}
