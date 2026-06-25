package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

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
 * Pure JSON codec for the custom film library. Encoding is total; decoding
 * fails safe to null on malformed payloads or an unrecognized future schema
 * version so a corrupt store reads as an empty library.
 */
object CustomFilmLibraryCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(snapshot: PersistentCustomFilmLibrarySnapshot): String = json.encodeToString(snapshot)

    fun decode(text: String): PersistentCustomFilmLibrarySnapshot? = try {
        val snapshot = json.decodeFromString<PersistentCustomFilmLibrarySnapshot>(text)
        if (snapshot.schemaVersion == PersistentCustomFilmLibrarySnapshot.CURRENT_SCHEMA_VERSION) snapshot else null
    } catch (_: Exception) {
        null
    }
}
