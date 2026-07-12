// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * On-disk schema for the custom film library — a thin wrapper around
 * `[FilmIdentity]` (every custom entry is by construction a single
 * `.userDefined` profile, the same domain shape preset films use, so there
 * is no translation step). (iOS: PersistentCustomFilmLibrarySnapshot.)
 */
@Serializable
data class PersistentCustomFilmLibrarySnapshot(
    val films: List<FilmIdentity> = emptyList(),
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
) {
    companion object {
        const val CURRENT_SCHEMA_VERSION: Int = 1
    }
}

/** Persistence boundary for the custom film library. */
interface CustomFilmLibraryStoring {
    fun loadSnapshot(): PersistentCustomFilmLibrarySnapshot?
    fun saveSnapshot(snapshot: PersistentCustomFilmLibrarySnapshot)
    fun clearSnapshot()
}

class NoOpCustomFilmLibraryStore : CustomFilmLibraryStoring {
    override fun loadSnapshot(): PersistentCustomFilmLibrarySnapshot? = null
    override fun saveSnapshot(snapshot: PersistentCustomFilmLibrarySnapshot) {}
    override fun clearSnapshot() {}
}

/**
 * Pure JSON codec for the custom film library. Encoding is total. Decoding is
 * per-record and version-gated (PTIMER-215): one film carrying an unknown enum
 * value or rule kind is dropped and the rest of the library survives; a
 * missing version is accepted as the legacy v1; a version mismatch or a
 * malformed root rejects the whole payload. [decodeWithDiagnostics] reports the
 * outcome so the store can quarantine; [decode] is the fail-safe wrapper.
 */
object CustomFilmLibraryCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(snapshot: PersistentCustomFilmLibrarySnapshot): String = json.encodeToString(snapshot)

    fun decodeWithDiagnostics(text: String): SnapshotDecodeResult<PersistentCustomFilmLibrarySnapshot> {
        val result = VersionedCollectionDecoder.decodeRecords(
            json = json,
            text = text,
            recordsKey = "films",
            expectedSchemaVersion = PersistentCustomFilmLibrarySnapshot.CURRENT_SCHEMA_VERSION,
            idOf = { it.id },
            decodeRecord = { json.decodeFromJsonElement<FilmIdentity>(it) },
        )
        return SnapshotDecodeResult(
            snapshot = PersistentCustomFilmLibrarySnapshot(films = result.records),
            outcome = result.outcome,
            droppedRecordCount = result.droppedRecordCount,
        )
    }

    fun decode(text: String): PersistentCustomFilmLibrarySnapshot? {
        val result = decodeWithDiagnostics(text)
        return when (result.outcome) {
            PersistenceLoadOutcome.malformed, PersistenceLoadOutcome.versionRejected -> null
            else -> result.snapshot
        }
    }
}
