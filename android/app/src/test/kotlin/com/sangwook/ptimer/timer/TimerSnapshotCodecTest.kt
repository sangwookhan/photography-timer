package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.TimerStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** JVM round-trip + fail-safe tests for the timer persistence codec. */
class TimerSnapshotCodecTest {

    private val base: Instant = Instant.parse("2026-06-17T00:00:00Z")

    @Test
    fun roundTripsRunningPausedCompletedWithIdentity() {
        val timers = listOf(
            TimerState.running("r", 100.0, base),
            TimerState.Paused("p", 100.0, base, pausedRemainingSeconds = 40.0, pausedAt = base.plusSeconds(60)),
            TimerState.Completed("c", 30.0, base, completedAt = base.plusSeconds(30)),
        )
        val titles = mapOf("r" to "Cam · Digital", "p" to "Cam · Portra 400", "c" to "Cam · Fomapan")
        val subtitles = mapOf("r" to "Adjusted Shutter · 100s", "p" to "Adjusted Shutter · Limited guidance · 100s", "c" to "Corrected Exposure · table")
        val sources = mapOf(
            "r" to ExposureTimerSource.DIGITAL_RESULT,
            "p" to ExposureTimerSource.FILM_ADJUSTED_SHUTTER,
            "c" to ExposureTimerSource.FILM_CORRECTED_EXPOSURE,
        )
        val json = TimerSnapshotCodec.encode(timers, titles, subtitles, sources)

        val restored = TimerSnapshotCodec.decode(json)
        assertEquals(3, restored.snapshots.size)
        assertEquals(titles, restored.titles)
        assertEquals(subtitles, restored.subtitles)
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, restored.sources["c"])

        val running = restored.snapshots.first { it.id == "r" }.restore(base.plusSeconds(10))
        assertEquals(TimerStatus.RUNNING, running.status)
        val paused = restored.snapshots.first { it.id == "p" }.restore(base.plusSeconds(9999))
        assertEquals(40.0, paused.remainingTime(base.plusSeconds(9999)), 1e-6)
    }

    @Test
    fun corruptPayloadDecodesToEmpty() {
        assertTrue(TimerSnapshotCodec.decode("{ not json").snapshots.isEmpty())
        assertTrue(TimerSnapshotCodec.decode("").snapshots.isEmpty())
    }

    @Test
    fun unknownSchemaVersionDecodesToEmpty() {
        assertTrue(TimerSnapshotCodec.decode("""{"schemaVersion":999,"timers":[]}""").snapshots.isEmpty())
    }
}
