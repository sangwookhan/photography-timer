package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.TimerStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** JVM tests for the Android-free timer workspace controller. */
class TimerWorkspaceControllerTest {

    private val base: Instant = Instant.parse("2026-06-17T00:00:00Z")
    private var now: Instant = base
    private val controller = TimerWorkspaceController { now }

    private fun TimerWorkspaceController.startAdjusted(title: String, durationSeconds: Double) =
        start(
            title,
            "Adjusted Shutter · ${durationSeconds.toInt()}s",
            "Base 1/30 · ND 0 · Adjusted ${durationSeconds.toInt()}s",
            ExposureTimerSource.FILM_ADJUSTED_SHUTTER,
            durationSeconds,
        )

    @Test
    fun startAddsActiveTimerWithRemaining() {
        controller.startAdjusted("Cam 1 · Shot", 100.0)
        now = base.plusSeconds(30)
        controller.refresh()
        val item = controller.state.value.active.single()
        assertEquals("Cam 1 · Shot", item.title)
        assertEquals(ExposureTimerSource.FILM_ADJUSTED_SHUTTER, item.source)
        assertEquals(TimerStatus.RUNNING, item.status)
        assertEquals(70.0, item.remainingSeconds, 1.0)
    }

    @Test
    fun pauseAndResumeFreezeAndContinue() {
        val id = controller.startAdjusted("Shot", 100.0)!!
        now = base.plusSeconds(40)
        controller.pause(id)
        assertEquals(TimerStatus.PAUSED, controller.state.value.active.single().status)
        now = base.plusSeconds(9999)
        controller.refresh()
        assertEquals(60.0, controller.state.value.active.single().remainingSeconds, 1e-6)
        controller.resume(id)
        assertEquals(TimerStatus.RUNNING, controller.state.value.active.single().status)
    }

    @Test
    fun tickCompletesExactlyOnceAndMovesToCompleted() {
        controller.startAdjusted("A", 10.0)
        controller.startAdjusted("B", 100.0)
        now = base.plusSeconds(10)
        val completed = controller.tick()
        assertEquals(1, completed.size)
        assertTrue(controller.tick().isEmpty())
        assertEquals(1, controller.state.value.completed.size)
        assertEquals(1, controller.state.value.active.size)
    }

    @Test
    fun activeOrderingIsNewestFirst() {
        controller.startAdjusted("first", 100.0)
        now = base.plusSeconds(1)
        controller.startAdjusted("second", 100.0)
        controller.refresh()
        assertEquals(listOf("second", "first"), controller.state.value.active.map { it.title })
    }

    @Test
    fun sourceIdentityIsPreservedPerTimer() {
        controller.start("Cam · Digital", "Adjusted Shutter · 10s", "Base 1/30 · ND 0 · Adjusted 10s", ExposureTimerSource.DIGITAL_RESULT, 10.0)
        controller.start("Cam · Fomapan", "Corrected Exposure · table · 02:00", "Base 1/30 · ND 8 · Adjusted 8.5s", ExposureTimerSource.FILM_CORRECTED_EXPOSURE, 120.0)
        val active = controller.state.value.active
        val fomapan = active.first { it.title.contains("Fomapan") }
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, fomapan.source)
        assertEquals(ExposureTimerSource.DIGITAL_RESULT, active.first { it.title.contains("Digital") }.source)
        assertTrue(fomapan.subtitle.contains("Corrected Exposure"))
        assertTrue(fomapan.metadata.contains("Adjusted"))
        assertEquals("Running", fomapan.statusLabel)
        assertTrue(fomapan.endsAtLabel!!.startsWith("Ends "))
    }

    @Test
    fun timerIdentityIsImmutableAcrossLifecycleAndLaterStarts() {
        // A timer captures its identity at start; nothing after start (pause,
        // resume, a later differently-identified start, or a clone) may mutate
        // it. This is the Android analog of iOS's snapshot-identity-stability
        // guard against late calculator edits bleeding into a running timer.
        val id = controller.start(
            "Cam 1 · Pan F", "Adjusted Shutter · 100s", "Base 1/30 · ND 0 · Adjusted 100s",
            ExposureTimerSource.FILM_ADJUSTED_SHUTTER, 100.0,
        )!!
        fun captured() = controller.state.value.active.first { it.id == id }
        val before = captured().let { listOf(it.title, it.subtitle, it.metadata, it.source.name) }

        now = base.plusSeconds(20); controller.pause(id)
        now = base.plusSeconds(50); controller.resume(id); controller.refresh()
        // A later start with a completely different identity must not touch the first.
        controller.start(
            "Cam 2 · Portra 400", "Corrected Exposure · limited", "Base 1/30 · ND 8 · Adjusted 8.5s",
            ExposureTimerSource.FILM_CORRECTED_EXPOSURE, 30.0,
        )
        controller.refresh()

        val after = captured().let { listOf(it.title, it.subtitle, it.metadata, it.source.name) }
        assertEquals(before, after)
    }

    @Test
    fun startNewClonesAnActiveRunningTimer() {
        controller.start("Cam · Fomapan", "Corrected Exposure · table", "Base 1/30 · ND 8 · Adjusted 8.5s", ExposureTimerSource.FILM_CORRECTED_EXPOSURE, 120.0)
        val original = controller.state.value.active.single().id
        controller.cloneToNew(original)
        val active = controller.state.value.active
        assertEquals(2, active.size)
        // Both carry the same identity/source; they are distinct timers.
        assertTrue(active.all { it.source == ExposureTimerSource.FILM_CORRECTED_EXPOSURE })
        assertEquals(2, active.map { it.id }.toSet().size)
    }

    @Test
    fun startAgainClonesTitleSubtitleAndSource() {
        controller.start("Cam · Fomapan", "Corrected Exposure · table", "Base 1/30 · ND 5 · Adjusted 32s", ExposureTimerSource.FILM_CORRECTED_EXPOSURE, 42.0)
        now = base.plusSeconds(42)
        controller.tick()
        val completedId = controller.state.value.completed.single().id
        now = base.plusSeconds(50)
        controller.startAgain(completedId)
        val active = controller.state.value.active.single()
        assertEquals("Cam · Fomapan", active.title)
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, active.source)
        assertEquals(TimerStatus.RUNNING, active.status)
    }

    @Test
    fun restoreFromJsonPreservesIdentityAndRunningRemaining() {
        controller.start("Cam 2 · Portra 400", "Adjusted Shutter · Limited guidance · 100s", "Base 1/30 · ND 8 · Adjusted 100s", ExposureTimerSource.FILM_ADJUSTED_SHUTTER, 100.0)
        now = base.plusSeconds(30)
        val json = controller.snapshotJson()

        val restored = TimerWorkspaceController { base.plusSeconds(30) }
        restored.restoreFromJson(json)
        val item = restored.state.value.active.single()
        assertEquals("Cam 2 · Portra 400", item.title)
        assertTrue(item.subtitle.contains("Limited guidance"))
        assertEquals(ExposureTimerSource.FILM_ADJUSTED_SHUTTER, item.source)
        assertEquals(70.0, item.remainingSeconds, 1.0)
    }

    @Test
    fun nonPositiveDurationDoesNotStart() {
        assertNull(controller.startAdjusted("bad", 0.0))
        assertTrue(controller.state.value.active.isEmpty())
    }

    // --- restored-id collision hardening (blocker 1) -----------------------

    private fun jsonOf(vararg ids: String): String {
        val timers = ids.map { TimerState.running(it, 100.0, base) }
        val m = ids.associateWith { "t" }
        val srcs = ids.associateWith { ExposureTimerSource.MANUAL }
        return TimerSnapshotCodec.encode(timers, m, m, m, srcs)
    }

    @Test
    fun startAfterRestoringTimerZeroYieldsTimerOne() {
        controller.restoreFromJson(jsonOf("timer-0"))
        val newId = controller.start("X", "s", "m", ExposureTimerSource.MANUAL, 50.0)
        assertEquals("timer-1", newId)
        // The restored timer is untouched (no overwrite).
        assertEquals(2, controller.state.value.active.size)
    }

    @Test
    fun startAfterRestoringSparseIdsContinuesPastTheMax() {
        controller.restoreFromJson(jsonOf("timer-0", "timer-3"))
        assertEquals("timer-4", controller.start("X", "s", "m", ExposureTimerSource.MANUAL, 50.0))
    }

    @Test
    fun startAfterRestoringNonMatchingIdsStillProducesAUniqueId() {
        controller.restoreFromJson(jsonOf("weird-1", "custom-x", "timer-abc"))
        val newId = controller.start("X", "s", "m", ExposureTimerSource.MANUAL, 50.0)
        assertNotNull(newId)
        assertTrue(newId!!.startsWith("timer-"))
        val restoredIds = controller.state.value.active.map { it.id }.toSet()
        // Unique: the started id is distinct from every restored id.
        assertEquals(4, restoredIds.size)
        assertFalse(setOf("weird-1", "custom-x", "timer-abc").contains(newId))
    }

    @Test
    fun startAfterRestoringSnapshotWithCorruptItemSkipsItAndAvoidsCollision() {
        // One blank-id (corrupt) item is skipped; the valid timer-2 restores and
        // the counter advances past it. Epochs derive from `base` so timer-2 is
        // still running under the controller's clock.
        val startMs = base.toEpochMilli()
        val expectedMs = base.plusSeconds(100).toEpochMilli()
        val json = """{"schemaVersion":1,"timers":[""" +
            """{"id":"","title":"t","status":"running","durationSeconds":100.0,"startEpochMs":$startMs},""" +
            """{"id":"timer-2","title":"t","status":"running","durationSeconds":100.0,"startEpochMs":$startMs,"expectedCompletionEpochMs":$expectedMs}""" +
            """]}"""
        controller.restoreFromJson(json)
        assertEquals(1, controller.state.value.active.size) // corrupt item skipped
        assertEquals("timer-3", controller.start("X", "s", "m", ExposureTimerSource.MANUAL, 50.0))
    }
}
