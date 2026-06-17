package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot
import com.sangwook.ptimer.core.timer.TimerState
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant

/**
 * Serializes the timer collection (runtime snapshot + display name) to JSON
 * for DataStore persistence, and decodes it back. Greenfield consolidation:
 * runtime + display metadata live in one collection snapshot (schemaVersion
 * 1). Times are epoch-millis. Corrupt or unknown/future-version payloads
 * decode to empty (fail-safe), matching the iOS restore contract.
 */
object TimerSnapshotCodec {
    private const val SCHEMA_VERSION = 1
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Serializable
    private data class Dto(
        val id: String,
        val name: String,
        val status: String,
        val durationSeconds: Double,
        val startEpochMs: Long,
        val expectedCompletionEpochMs: Long? = null,
        val pausedRemainingSeconds: Double? = null,
        val pausedAtEpochMs: Long? = null,
        val completedAtEpochMs: Long? = null,
    )

    @Serializable
    private data class CollectionDto(
        val schemaVersion: Int = SCHEMA_VERSION,
        val timers: List<Dto> = emptyList(),
    )

    data class Restored(
        val snapshots: List<PersistentTimerSnapshot>,
        val names: Map<String, String>,
    )

    fun encode(timers: List<TimerState>, names: Map<String, String>): String {
        val dtos = timers.map { timer ->
            val snap = PersistentTimerSnapshot.fromTimer(timer)
            Dto(
                id = snap.id,
                name = names[snap.id] ?: "Timer",
                status = snap.status.token,
                durationSeconds = snap.durationSeconds,
                startEpochMs = snap.startDate.toEpochMilli(),
                expectedCompletionEpochMs = snap.expectedCompletionAt?.toEpochMilli(),
                pausedRemainingSeconds = snap.pausedRemainingDuration,
                pausedAtEpochMs = snap.pausedAt?.toEpochMilli(),
                completedAtEpochMs = snap.completedAt?.toEpochMilli(),
            )
        }
        return json.encodeToString(CollectionDto(SCHEMA_VERSION, dtos))
    }

    fun decode(text: String): Restored {
        val collection = try {
            json.decodeFromString<CollectionDto>(text)
        } catch (_: Exception) {
            return Restored(emptyList(), emptyMap())
        }
        if (collection.schemaVersion != SCHEMA_VERSION) return Restored(emptyList(), emptyMap())

        val snapshots = ArrayList<PersistentTimerSnapshot>(collection.timers.size)
        val names = LinkedHashMap<String, String>()
        for (dto in collection.timers) {
            val status = try {
                PersistentTimerSnapshot.SnapshotStatus.fromToken(dto.status)
            } catch (_: IllegalArgumentException) {
                continue // skip an unrecognized status rather than failing the whole load
            }
            snapshots += PersistentTimerSnapshot(
                id = dto.id,
                status = status,
                durationSeconds = dto.durationSeconds,
                startDate = Instant.ofEpochMilli(dto.startEpochMs),
                expectedCompletionAt = dto.expectedCompletionEpochMs?.let(Instant::ofEpochMilli),
                pausedRemainingDuration = dto.pausedRemainingSeconds,
                pausedAt = dto.pausedAtEpochMs?.let(Instant::ofEpochMilli),
                completedAt = dto.completedAtEpochMs?.let(Instant::ofEpochMilli),
            )
            names[dto.id] = dto.name
        }
        return Restored(snapshots, names)
    }
}
