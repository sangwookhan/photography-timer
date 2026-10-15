// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// Legacy persistence of the fixed four-slot session. The managed camera list
// (ManagedCameraListPersistence) replaced it as the live store; this payload
// is now read-only migration input (CAMERA-PERSIST-006) and is never written
// by the app.

@Serializable
data class PersistentSlotSession(
    val activeSlotId: CameraSlotId,
    /** Snapshot per slot, including the active slot's captured live state. */
    val snapshots: Map<CameraSlotId, SlotCalculatorSnapshot> = emptyMap(),
    val customNames: Map<CameraSlotId, String> = emptyMap(),
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
) {
    companion object {
        const val CURRENT_SCHEMA_VERSION: Int = 1
    }
}

/** Outcome of reading the legacy slot session for migration. */
sealed interface SlotSessionLoadResult {
    /** No legacy payload is stored. */
    data object Absent : SlotSessionLoadResult

    data class Loaded(val session: PersistentSlotSession) : SlotSessionLoadResult

    /** Content was read but is not a supported fixed-slot shape. */
    data object Unsupported : SlotSessionLoadResult

    /** The read failed and supplied no content: no migration, no fallback (CAMERA-PERSIST-006). */
    data object ReadFailed : SlotSessionLoadResult
}

/** Persistence boundary for the camera-slot session. */
interface SlotSessionStoring {
    fun loadSession(): PersistentSlotSession?

    /** Distinguishes an absent or unsupported payload from a failed read. */
    fun load(): SlotSessionLoadResult = loadSession()?.let { SlotSessionLoadResult.Loaded(it) } ?: SlotSessionLoadResult.Absent

    fun saveSession(session: PersistentSlotSession)
    fun clearSession()
}

class NoOpSlotSessionStore : SlotSessionStoring {
    override fun loadSession(): PersistentSlotSession? = null
    override fun saveSession(session: PersistentSlotSession) {}
    override fun clearSession() {}
}

/**
 * Pure JSON codec for the slot session. Encoding is total; decoding fails safe
 * to null on malformed payloads or an unrecognized future schema version.
 */
object SlotSessionCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(session: PersistentSlotSession): String = json.encodeToString(session)

    fun decode(text: String): PersistentSlotSession? = try {
        val session = json.decodeFromString<PersistentSlotSession>(text)
        if (session.schemaVersion == PersistentSlotSession.CURRENT_SCHEMA_VERSION) session else null
    } catch (_: Exception) {
        null
    }
}
