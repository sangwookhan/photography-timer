package com.sangwook.ptimer.customfilm

import com.sangwook.ptimer.core.catalog.FilmIdentity
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Serializes the custom-film library (a list of custom FilmIdentity) for
 * DataStore persistence. schemaVersion 1; corrupt/unknown-version payloads
 * decode to empty (fail-safe). Mirrors iOS `PersistentCustomFilmLibrarySnapshot`.
 */
object CustomFilmLibraryCodec {
    private const val SCHEMA_VERSION = 1
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Serializable
    private data class Envelope(val schemaVersion: Int = SCHEMA_VERSION, val films: List<FilmIdentity> = emptyList())

    fun encode(films: List<FilmIdentity>): String = json.encodeToString(Envelope(SCHEMA_VERSION, films))

    fun decode(text: String): List<FilmIdentity> {
        val env = try {
            json.decodeFromString<Envelope>(text)
        } catch (_: Exception) {
            return emptyList()
        }
        if (env.schemaVersion != SCHEMA_VERSION) return emptyList()
        // Only keep well-formed custom films.
        return env.films.filter { CustomFilmLibrary.isWellFormed(it) }
    }
}
