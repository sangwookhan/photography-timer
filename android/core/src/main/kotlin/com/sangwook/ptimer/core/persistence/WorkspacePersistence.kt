// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.WorkspaceTimer
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import java.time.Instant

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
 * Pure JSON codec for the workspace snapshot. Encoding is total. Decoding is
 * per-record and version-gated: a single undecodable timer entry is dropped
 * rather than discarding the whole collection, duplicate ids collapse
 * first-valid-wins, a missing version is accepted as the legacy v1, and a
 * version mismatch or malformed root rejects the whole payload.
 * [decodeWithDiagnostics] reports the outcome so the store can quarantine
 * (PTIMER-215); [decode] is the fail-safe wrapper with the prior contract.
 */
object WorkspaceSnapshotCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(snapshot: PersistentWorkspaceSnapshot): String = json.encodeToString(snapshot)

    fun decodeWithDiagnostics(text: String): SnapshotDecodeResult<PersistentWorkspaceSnapshot> {
        val result = VersionedCollectionDecoder.decodeRecords(
            json = json,
            text = text,
            recordsKey = "timers",
            expectedSchemaVersion = PersistentWorkspaceSnapshot.CURRENT_SCHEMA_VERSION,
            idOf = { it.snapshot.id },
            decodeRecord = { json.decodeFromJsonElement<PersistentWorkspaceTimer>(it) },
        )
        return SnapshotDecodeResult(
            snapshot = PersistentWorkspaceSnapshot(timers = result.records),
            outcome = result.outcome,
            droppedRecordCount = result.droppedRecordCount,
        )
    }

    fun decode(text: String): PersistentWorkspaceSnapshot? {
        val result = decodeWithDiagnostics(text)
        return when (result.outcome) {
            PersistenceLoadOutcome.malformed, PersistenceLoadOutcome.versionRejected -> null
            else -> result.snapshot
        }
    }
}
