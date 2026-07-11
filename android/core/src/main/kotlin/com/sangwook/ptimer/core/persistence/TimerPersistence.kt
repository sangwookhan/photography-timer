// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.core.timer.endDate
import com.sangwook.ptimer.core.timer.pausedAt
import com.sangwook.ptimer.core.timer.pausedRemainingTime
import com.sangwook.ptimer.core.timer.plusSecondsDouble
import com.sangwook.ptimer.core.timer.remainingAtCancel
import com.sangwook.ptimer.core.timer.status
import com.sangwook.ptimer.core.timer.TIMER_STABILITY_EPSILON
import com.sangwook.ptimer.core.timer.secondsBetween
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import java.time.Instant
import java.util.UUID

// Faithful port of iOS PTimerCore TimerPersistence with greenfield Android
// packaging. The restore rules (running reconcile to wall-clock, paused stays
// frozen, corrupt paused → completed, canceled restores remaining-at-cancel)
// match iOS exactly. Display/identity metadata is folded into the timer
// snapshot in a later unit (round2 §4 consolidation).

/** Snapshot status. Legacy "stopped" decodes as [paused]. */
enum class SnapshotStatus { running, paused, completed, canceled }

object SnapshotStatusSerializer : KSerializer<SnapshotStatus> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("SnapshotStatus", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: SnapshotStatus) = encoder.encodeString(value.name)

    override fun deserialize(decoder: Decoder): SnapshotStatus = when (val raw = decoder.decodeString()) {
        "running" -> SnapshotStatus.running
        "paused", "stopped" -> SnapshotStatus.paused
        "completed" -> SnapshotStatus.completed
        "canceled" -> SnapshotStatus.canceled
        else -> throw IllegalArgumentException("Unsupported snapshot status: $raw")
    }
}

@Serializable
data class PersistentTimerSnapshot(
    @Serializable(with = UuidSerializer::class) val id: UUID,
    @Serializable(with = SnapshotStatusSerializer::class) val status: SnapshotStatus,
    val duration: Double,
    @Serializable(with = InstantSerializer::class) val startDate: Instant,
    @Serializable(with = InstantSerializer::class) val expectedCompletionAt: Instant? = null,
    val pausedRemainingDuration: Double? = null,
    @Serializable(with = InstantSerializer::class) val pausedAt: Instant? = null,
    @Serializable(with = InstantSerializer::class) val completedAt: Instant? = null,
) {
    fun restore(now: Instant): TimerState = when (status) {
        SnapshotStatus.running -> {
            val expected = expectedCompletionAt
            when {
                expected == null -> makeCompleted(now)
                secondsBetween(now, expected) <= TIMER_STABILITY_EPSILON -> makeCompleted(expected)
                else -> TimerState.fromLegacy(
                    id, duration, startDate,
                    endDate = expected, pausedRemainingTime = null, pausedAt = null,
                    status = TimerStatus.running,
                )
            }
        }
        SnapshotStatus.paused -> {
            val pAt = pausedAt
            val pRemaining = pausedRemainingDuration
            if (pAt == null || pRemaining == null) {
                makeCompleted(completedAt)
            } else {
                TimerState.fromLegacy(
                    id, duration, startDate,
                    endDate = null, pausedRemainingTime = pRemaining, pausedAt = pAt,
                    status = TimerStatus.paused,
                )
            }
        }
        SnapshotStatus.completed -> makeCompleted(completedAt)
        SnapshotStatus.canceled -> TimerState.fromLegacy(
            id, duration, startDate,
            endDate = completedAt ?: startDate.plusSecondsDouble(duration),
            pausedRemainingTime = pausedRemainingDuration, pausedAt = null,
            status = TimerStatus.canceled,
        )
    }

    private fun makeCompleted(completionDate: Instant?): TimerState = TimerState.fromLegacy(
        id, duration, startDate,
        endDate = completionDate ?: expectedCompletionAt ?: pausedAt ?: startDate.plusSecondsDouble(duration),
        pausedRemainingTime = null, pausedAt = null,
        status = TimerStatus.completed,
    )

    companion object {
        fun from(timer: TimerState): PersistentTimerSnapshot {
            val pausedRemaining = timer.pausedRemainingTime ?: timer.remainingAtCancel
            return when (timer.status) {
                TimerStatus.running -> PersistentTimerSnapshot(
                    id = timer.id, status = SnapshotStatus.running, duration = timer.duration,
                    startDate = timer.startDate, expectedCompletionAt = timer.endDate,
                    pausedRemainingDuration = pausedRemaining, pausedAt = timer.pausedAt, completedAt = null,
                )
                TimerStatus.paused -> PersistentTimerSnapshot(
                    id = timer.id, status = SnapshotStatus.paused, duration = timer.duration,
                    startDate = timer.startDate, expectedCompletionAt = null,
                    pausedRemainingDuration = pausedRemaining, pausedAt = timer.pausedAt, completedAt = null,
                )
                TimerStatus.completed -> PersistentTimerSnapshot(
                    id = timer.id, status = SnapshotStatus.completed, duration = timer.duration,
                    startDate = timer.startDate, expectedCompletionAt = null,
                    pausedRemainingDuration = pausedRemaining, pausedAt = timer.pausedAt, completedAt = timer.endDate,
                )
                TimerStatus.canceled -> PersistentTimerSnapshot(
                    id = timer.id, status = SnapshotStatus.canceled, duration = timer.duration,
                    startDate = timer.startDate, expectedCompletionAt = null,
                    pausedRemainingDuration = pausedRemaining, pausedAt = timer.pausedAt, completedAt = timer.endDate,
                )
            }
        }
    }
}

@Serializable
data class PersistentTimerCollectionSnapshot(
    val timers: List<PersistentTimerSnapshot> = emptyList(),
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
) {
    companion object {
        const val CURRENT_SCHEMA_VERSION: Int = 1

        fun from(timers: List<TimerState>): PersistentTimerCollectionSnapshot =
            PersistentTimerCollectionSnapshot(timers.map { PersistentTimerSnapshot.from(it) })
    }
}

/** Persistence boundary for the timer collection. */
interface TimerPersistenceStoring {
    fun loadSnapshot(): PersistentTimerCollectionSnapshot?
    fun saveSnapshot(snapshot: PersistentTimerCollectionSnapshot)
    fun clearSnapshot()
}

/** Unit-test / no-persistence implementation. */
class NoOpTimerPersistenceStore : TimerPersistenceStoring {
    override fun loadSnapshot(): PersistentTimerCollectionSnapshot? = null
    override fun saveSnapshot(snapshot: PersistentTimerCollectionSnapshot) {}
    override fun clearSnapshot() {}
}

/**
 * Pure JSON codec for the timer collection snapshot. Encoding is total.
 * Decoding is per-record and version-gated (PTIMER-215): one timer with an
 * unknown status token is dropped and the rest survive; a missing version is
 * accepted as the legacy v1; a version mismatch or malformed root rejects the
 * whole payload. [decodeWithDiagnostics] reports the outcome so a store can
 * quarantine; [decode] is the fail-safe wrapper.
 */
object TimerSnapshotCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(snapshot: PersistentTimerCollectionSnapshot): String = json.encodeToString(snapshot)

    fun decodeWithDiagnostics(text: String): SnapshotDecodeResult<PersistentTimerCollectionSnapshot> {
        val result = VersionedCollectionDecoder.decodeRecords(
            json = json,
            text = text,
            recordsKey = "timers",
            expectedSchemaVersion = PersistentTimerCollectionSnapshot.CURRENT_SCHEMA_VERSION,
            idOf = { it.id },
            decodeRecord = { json.decodeFromJsonElement<PersistentTimerSnapshot>(it) },
        )
        return SnapshotDecodeResult(
            snapshot = PersistentTimerCollectionSnapshot(timers = result.records),
            outcome = result.outcome,
            droppedRecordCount = result.droppedRecordCount,
        )
    }

    fun decode(text: String): PersistentTimerCollectionSnapshot? {
        val result = decodeWithDiagnostics(text)
        return when (result.outcome) {
            PersistenceLoadOutcome.malformed, PersistenceLoadOutcome.versionRejected -> null
            else -> result.snapshot
        }
    }
}
