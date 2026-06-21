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
        val metadatas = mapOf("r" to "Base 1/30 · ND 0 · Adjusted 100s", "p" to "Base 1/30 · ND 8 · Adjusted 100s", "c" to "Base 1/30 · ND 8 · Adjusted 8.5s")
        val sources = mapOf(
            "r" to ExposureTimerSource.DIGITAL_RESULT,
            "p" to ExposureTimerSource.FILM_ADJUSTED_SHUTTER,
            "c" to ExposureTimerSource.FILM_CORRECTED_EXPOSURE,
        )
        val json = TimerSnapshotCodec.encode(timers, titles, subtitles, metadatas, sources)

        val restored = TimerSnapshotCodec.decode(json)
        assertEquals(3, restored.snapshots.size)
        assertEquals(titles, restored.titles)
        assertEquals(subtitles, restored.subtitles)
        assertEquals(metadatas, restored.metadatas)
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, restored.sources["c"])

        val running = restored.snapshots.first { it.id == "r" }.restore(base.plusSeconds(10))
        assertEquals(TimerStatus.RUNNING, running.status)
        val paused = restored.snapshots.first { it.id == "p" }.restore(base.plusSeconds(9999))
        assertEquals(40.0, paused.remainingTime(base.plusSeconds(9999)), 1e-6)
    }

    @Test
    fun roundTripsCanceledPreservingRemainingAtCancel() {
        val timers = listOf(
            TimerState.Canceled("x", 100.0, base, canceledAt = base.plusSeconds(40), remainingAtCancelSeconds = 60.0),
        )
        val m = mapOf("x" to "Cam · Fomapan")
        val sources = mapOf("x" to ExposureTimerSource.FILM_CORRECTED_EXPOSURE)
        val json = TimerSnapshotCodec.encode(timers, m, m, m, sources)

        val restored = TimerSnapshotCodec.decode(json)
        assertEquals(1, restored.snapshots.size)
        val state = restored.snapshots.single().restore(base.plusSeconds(9999))
        assertEquals(TimerStatus.CANCELED, state.status)
        state as TimerState.Canceled
        assertEquals(base.plusSeconds(40), state.canceledAt)
        assertEquals(60.0, state.remainingAtCancelSeconds, 1e-6)
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, restored.sources["x"])
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

    // --- per-item sanitation (blocker 5) -----------------------------------
    //
    // Policy: skip only the structurally-impossible item (blank id, non-finite
    // or non-positive duration, negative paused remaining, missing start,
    // duplicate id) and keep its valid siblings. Items that merely lack
    // reconcilable detail (running with no expected-completion, paused with no
    // freeze metadata) are kept and safely completed by the core restore
    // contract — never resurrected as impossible active timers.

    private val baseMs = 1_780_000_000_000L
    private fun wrap(vararg items: String) = """{"schemaVersion":1,"timers":[${items.joinToString(",")}]}"""
    private fun running(id: String, dur: Double = 100.0) =
        """{"id":"$id","title":"t","status":"running","durationSeconds":$dur,"startEpochMs":$baseMs,"expectedCompletionEpochMs":${baseMs + 100_000}}"""

    @Test
    fun corruptItemIsSkippedAndValidSiblingStillRestores() {
        val json = wrap(
            """{"id":"","title":"blank","status":"running","durationSeconds":100.0,"startEpochMs":$baseMs}""",
            running("timer-1"),
        )
        val r = TimerSnapshotCodec.decode(json)
        assertEquals(1, r.snapshots.size)
        assertEquals("timer-1", r.snapshots.single().id)
        assertEquals(setOf("timer-1"), r.titles.keys)
    }

    @Test
    fun nonFiniteOrNonPositiveDurationItemsAreSkipped() {
        val json = wrap(running("a", dur = 0.0), running("b", dur = -5.0), running("c"))
        val r = TimerSnapshotCodec.decode(json)
        assertEquals(listOf("c"), r.snapshots.map { it.id })
    }

    @Test
    fun negativePausedRemainingItemIsSkipped() {
        val bad = """{"id":"p","title":"t","status":"paused","durationSeconds":100.0,"startEpochMs":$baseMs,"pausedRemainingSeconds":-3.0,"pausedAtEpochMs":$baseMs}"""
        val r = TimerSnapshotCodec.decode(wrap(bad, running("c")))
        assertEquals(listOf("c"), r.snapshots.map { it.id })
    }

    @Test
    fun duplicateIdItemsAreDedupedKeepingTheFirst() {
        val r = TimerSnapshotCodec.decode(wrap(running("dup"), running("dup")))
        assertEquals(listOf("dup"), r.snapshots.map { it.id })
    }

    @Test
    fun runningItemMissingExpectedCompletionRestoresAsCompleted() {
        val noExpected = """{"id":"r","title":"t","status":"running","durationSeconds":100.0,"startEpochMs":$baseMs}"""
        val r = TimerSnapshotCodec.decode(wrap(noExpected))
        assertEquals(1, r.snapshots.size) // kept, not dropped
        val restored = r.snapshots.single().restore(Instant.ofEpochMilli(baseMs))
        assertEquals(TimerStatus.COMPLETED, restored.status) // safely completed, never a phantom running timer
    }

    @Test
    fun decodeNeverThrowsOnMalformedIndividualFieldsAndSkipsThem() {
        // Missing required-looking fields on one item; a valid sibling survives.
        val json = wrap("""{"id":"missing","status":"running"}""", running("ok"))
        val r = TimerSnapshotCodec.decode(json) // must not throw
        assertEquals(listOf("ok"), r.snapshots.map { it.id })
    }

    // --- per-item TYPE-mismatch isolation (Pass 2, issue 1) ----------------
    // A type mismatch in one item must not drop the whole collection.

    @Test
    fun badDurationTypeInOneItemDoesNotDropValidSibling() {
        val bad = """{"id":"bad","title":"t","status":"running","durationSeconds":"oops","startEpochMs":$baseMs}"""
        assertEquals(listOf("ok"), TimerSnapshotCodec.decode(wrap(bad, running("ok"))).snapshots.map { it.id })
    }

    @Test
    fun badStartEpochTypeInOneItemDoesNotDropValidSibling() {
        val bad = """{"id":"bad","title":"t","status":"running","durationSeconds":100.0,"startEpochMs":"nope"}"""
        assertEquals(listOf("ok"), TimerSnapshotCodec.decode(wrap(bad, running("ok"))).snapshots.map { it.id })
    }

    @Test
    fun badPausedRemainingTypeInOneItemDoesNotDropValidSibling() {
        val bad = """{"id":"bad","title":"t","status":"paused","durationSeconds":100.0,"startEpochMs":$baseMs,"pausedRemainingSeconds":"x","pausedAtEpochMs":$baseMs}"""
        assertEquals(listOf("ok"), TimerSnapshotCodec.decode(wrap(bad, running("ok"))).snapshots.map { it.id })
    }

    @Test
    fun badStatusTypeOrUnknownStatusInOneItemDoesNotDropValidSibling() {
        val badType = """{"id":"a","title":"t","status":123,"durationSeconds":100.0,"startEpochMs":$baseMs}"""
        assertEquals(listOf("ok"), TimerSnapshotCodec.decode(wrap(badType, running("ok"))).snapshots.map { it.id })
        val unknown = """{"id":"b","title":"t","status":"frozen","durationSeconds":100.0,"startEpochMs":$baseMs}"""
        assertEquals(listOf("ok"), TimerSnapshotCodec.decode(wrap(unknown, running("ok"))).snapshots.map { it.id })
    }

    @Test
    fun badSourceMetadataTypeInOneItemDoesNotDropValidSibling() {
        val bad = """{"id":"bad","title":"t","source":123,"status":"running","durationSeconds":100.0,"startEpochMs":$baseMs,"expectedCompletionEpochMs":${baseMs + 100_000}}"""
        assertEquals(listOf("ok"), TimerSnapshotCodec.decode(wrap(bad, running("ok"))).snapshots.map { it.id })
    }

    @Test
    fun fullyMalformedOrNonObjectJsonReturnsEmptyWithoutThrowing() {
        assertTrue(TimerSnapshotCodec.decode("not json {").snapshots.isEmpty())
        assertTrue(TimerSnapshotCodec.decode("[1,2,3]").snapshots.isEmpty()) // non-object top level
        assertTrue(TimerSnapshotCodec.decode("42").snapshots.isEmpty())
    }

    // --- duplicate-id ordering (Pass 2, issue 2) ---------------------------
    // The id is reserved only after validation, so a corrupt item never
    // shadows a later valid item that reuses the same id.

    @Test
    fun corruptDuplicateFirstThenValidDuplicateSecondRestoresTheValidOne() {
        val typeCorrupt = """{"id":"timer-1","status":"running","durationSeconds":"oops","startEpochMs":$baseMs}"""
        assertEquals(listOf("timer-1"), TimerSnapshotCodec.decode(wrap(typeCorrupt, running("timer-1"))).snapshots.map { it.id })

        val structurallyInvalid = """{"id":"timer-1","title":"t","status":"running","durationSeconds":0.0,"startEpochMs":$baseMs}"""
        assertEquals(listOf("timer-1"), TimerSnapshotCodec.decode(wrap(structurallyInvalid, running("timer-1"))).snapshots.map { it.id })
    }

    @Test
    fun twoValidDuplicatesKeepTheFirst() {
        val first = """{"id":"dup","title":"FIRST","status":"running","durationSeconds":100.0,"startEpochMs":$baseMs,"expectedCompletionEpochMs":${baseMs + 100_000}}"""
        val second = """{"id":"dup","title":"SECOND","status":"running","durationSeconds":200.0,"startEpochMs":$baseMs,"expectedCompletionEpochMs":${baseMs + 200_000}}"""
        val r = TimerSnapshotCodec.decode(wrap(first, second))
        assertEquals(listOf("dup"), r.snapshots.map { it.id })
        assertEquals(100.0, r.snapshots.single().durationSeconds, 1e-9) // first valid wins
        assertEquals("FIRST", r.titles["dup"])
    }

    @Test
    fun blankIdItemDoesNotAffectALaterValidItem() {
        val blank = """{"id":"","title":"t","status":"running","durationSeconds":100.0,"startEpochMs":$baseMs}"""
        val r = TimerSnapshotCodec.decode(wrap(blank, running("timer-1")))
        assertEquals(listOf("timer-1"), r.snapshots.map { it.id })
    }
}
