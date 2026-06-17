package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot
import com.sangwook.ptimer.core.timer.TimerState
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant

/**
 * Serializes the timer collection (runtime snapshot + title + source-identity
 * subtitle + source) to JSON for DataStore persistence, and decodes it back.
 * schemaVersion 1; epoch-millis; corrupt or unknown-version payloads decode to
 * empty (fail-safe), matching the iOS restore contract.
 */
object TimerSnapshotCodec {
    private const val SCHEMA_VERSION = 1
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Serializable
    private data class Dto(
        val id: String,
        val title: String,
        val subtitle: String = "",
        val source: String = "MANUAL",
        val status: String,
        val durationSeconds: Double,
        val startEpochMs: Long,
        val expectedCompletionEpochMs: Long? = null,
        val pausedRemainingSeconds: Double? = null,
        val pausedAtEpochMs: Long? = null,
        val completedAtEpochMs: Long? = null,
    )

    @Serializable
    private data class CollectionDto(val schemaVersion: Int = SCHEMA_VERSION, val timers: List<Dto> = emptyList())

    data class Restored(
        val snapshots: List<PersistentTimerSnapshot>,
        val titles: Map<String, String>,
        val subtitles: Map<String, String>,
        val sources: Map<String, ExposureTimerSource>,
    )

    fun encode(
        timers: List<TimerState>,
        titles: Map<String, String>,
        subtitles: Map<String, String>,
        sources: Map<String, ExposureTimerSource>,
    ): String {
        val dtos = timers.map { timer ->
            val snap = PersistentTimerSnapshot.fromTimer(timer)
            Dto(
                id = snap.id,
                title = titles[snap.id] ?: "Timer",
                subtitle = subtitles[snap.id] ?: "",
                source = (sources[snap.id] ?: ExposureTimerSource.MANUAL).name,
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
            return Restored(emptyList(), emptyMap(), emptyMap(), emptyMap())
        }
        if (collection.schemaVersion != SCHEMA_VERSION) return Restored(emptyList(), emptyMap(), emptyMap(), emptyMap())

        val snapshots = ArrayList<PersistentTimerSnapshot>(collection.timers.size)
        val titles = LinkedHashMap<String, String>()
        val subtitles = LinkedHashMap<String, String>()
        val sources = LinkedHashMap<String, ExposureTimerSource>()
        for (dto in collection.timers) {
            val status = try {
                PersistentTimerSnapshot.SnapshotStatus.fromToken(dto.status)
            } catch (_: IllegalArgumentException) {
                continue
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
            titles[dto.id] = dto.title
            subtitles[dto.id] = dto.subtitle
            sources[dto.id] = runCatching { ExposureTimerSource.valueOf(dto.source) }.getOrDefault(ExposureTimerSource.MANUAL)
        }
        return Restored(snapshots, titles, subtitles, sources)
    }
}
