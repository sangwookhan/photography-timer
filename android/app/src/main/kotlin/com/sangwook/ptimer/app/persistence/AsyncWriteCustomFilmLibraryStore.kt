// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import com.sangwook.ptimer.core.persistence.CustomFilmLibraryStoring
import com.sangwook.ptimer.core.persistence.PersistentCustomFilmLibrarySnapshot

/**
 * Decorates a [CustomFilmLibraryStoring] so writes are handed to a
 * [PersistenceWriter] instead of blocking the caller (PTIMER-217).
 * `CustomFilmLibrary` (core) persists synchronously on every mutation, and its
 * create/edit/delete mutations happen in main-thread UI callbacks — this seam
 * keeps the core type and the concrete DataStore adapter unchanged while taking
 * the blocking write off the main thread.
 *
 * The default writer is the process-wide single writer, shared with the
 * workspace store, so writes are serialized in submission order across
 * configuration-change recreations of the composition and no per-instance scope
 * leaks. The write is asynchronous, so it commits shortly after the mutation
 * rather than before it returns.
 *
 * Reads pass through untouched: the only production read is the library's
 * constructor load, which already runs on IO during app bootstrap.
 */
class AsyncWriteCustomFilmLibraryStore(
    private val inner: CustomFilmLibraryStoring,
    private val writer: PersistenceWriter = AppPersistenceWriter,
) : CustomFilmLibraryStoring {

    override fun loadSnapshot(): PersistentCustomFilmLibrarySnapshot? = inner.loadSnapshot()

    override fun saveSnapshot(snapshot: PersistentCustomFilmLibrarySnapshot) {
        writer.submit { inner.saveSnapshot(snapshot) }
    }

    override fun clearSnapshot() {
        writer.submit { inner.clearSnapshot() }
    }
}
