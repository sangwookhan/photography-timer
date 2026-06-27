// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// Persistence for the camera-slot session so each slot's calculator context
// (wheel indices, film/profile, target) and custom name survive a relaunch
// (closes the unit-8 / unit-10 "deferred to 5b" notes).

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

/** Persistence boundary for the camera-slot session. */
interface SlotSessionStoring {
    fun loadSession(): PersistentSlotSession?
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
