// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.WorkspaceTimer
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.util.UUID

// Persistence for the timer workspace: each timer's runtime snapshot plus its
// captured display identity, consolidated into one snapshot (round2 §4).

@Serializable
data class PersistentWorkspaceTimer(
    val snapshot: PersistentTimerSnapshot,
    val identity: TimerIdentity,
    // Defaulted so snapshots written before the field existed decode to 0.
    val order: Int = 0,
) {
    fun restore(now: Instant): WorkspaceTimer = WorkspaceTimer(snapshot.restore(now), identity, order)

    companion object {
        fun from(timer: WorkspaceTimer): PersistentWorkspaceTimer =
            PersistentWorkspaceTimer(PersistentTimerSnapshot.from(timer.state), timer.identity, timer.order)
    }
}

@Serializable
data class PersistentWorkspaceSnapshot(
    val timers: List<PersistentWorkspaceTimer> = emptyList(),
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
) {
    fun restore(now: Instant): List<WorkspaceTimer> = timers.map { it.restore(now) }

    companion object {
        const val CURRENT_SCHEMA_VERSION: Int = 1

        fun from(timers: List<WorkspaceTimer>): PersistentWorkspaceSnapshot =
            PersistentWorkspaceSnapshot(timers.map { PersistentWorkspaceTimer.from(it) })
    }
}

/** Persistence boundary for the timer workspace. */
interface WorkspacePersistenceStoring {
    fun loadSnapshot(): PersistentWorkspaceSnapshot?
    fun saveSnapshot(snapshot: PersistentWorkspaceSnapshot)
    fun clearSnapshot()
}

class NoOpWorkspacePersistenceStore : WorkspacePersistenceStoring {
    override fun loadSnapshot(): PersistentWorkspaceSnapshot? = null
    override fun saveSnapshot(snapshot: PersistentWorkspaceSnapshot) {}
    override fun clearSnapshot() {}
}

/**
 * Pure JSON codec for the workspace snapshot. Encoding is total; decoding fails
 * safe to null on malformed payloads or an unrecognized future schema version.
 */
object WorkspaceSnapshotCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(snapshot: PersistentWorkspaceSnapshot): String = json.encodeToString(snapshot)

    /**
     * Decodes the workspace snapshot, hardened against partial corruption:
     * a malformed payload or unrecognized schema version fails safe to null;
     * a single undecodable timer entry is dropped rather than discarding the
     * whole collection; and duplicate timer ids are de-duplicated (first valid
     * wins). The typed [PersistentWorkspaceTimer] schema is unchanged.
     */
    fun decode(text: String): PersistentWorkspaceSnapshot? {
        return try {
            val root = json.parseToJsonElement(text).jsonObject
            val version = root["schemaVersion"]?.jsonPrimitive?.intOrNull
                ?: PersistentWorkspaceSnapshot.CURRENT_SCHEMA_VERSION
            if (version != PersistentWorkspaceSnapshot.CURRENT_SCHEMA_VERSION) return null
            val timersArray = root["timers"] as? JsonArray ?: JsonArray(emptyList())
            val seen = HashSet<UUID>()
            val timers = timersArray.mapNotNull { element ->
                runCatching { json.decodeFromJsonElement<PersistentWorkspaceTimer>(element) }
                    .getOrNull()
                    ?.takeIf { seen.add(it.snapshot.id) }
            }
            PersistentWorkspaceSnapshot(timers = timers, schemaVersion = version)
        } catch (_: Exception) {
            null
        }
    }
}
