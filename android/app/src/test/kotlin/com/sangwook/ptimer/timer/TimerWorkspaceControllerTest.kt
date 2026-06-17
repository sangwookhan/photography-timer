package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.TimerStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** JVM tests for the Android-free timer workspace controller. */
class TimerWorkspaceControllerTest {

    private val base: Instant = Instant.parse("2026-06-17T00:00:00Z")
    private var now: Instant = base
    private val controller = TimerWorkspaceController { now }

    @Test
    fun startAddsActiveTimerWithRemaining() {
        controller.start("Shot", 100.0)
        now = base.plusSeconds(30)
        controller.refresh()
        val item = controller.state.value.active.single()
        assertEquals("Shot", item.name)
        assertEquals(TimerStatus.RUNNING, item.status)
        assertEquals(70.0, item.remainingSeconds, 1.0)
    }

    @Test
    fun pauseAndResumeFreezeAndContinue() {
        val id = controller.start("Shot", 100.0)!!
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
        controller.start("A", 10.0)
        controller.start("B", 100.0)
        now = base.plusSeconds(10)
        val completed = controller.tick()
        assertEquals(1, completed.size)
        assertTrue(controller.tick().isEmpty()) // not re-reported
        assertEquals(1, controller.state.value.completed.size)
        assertEquals(1, controller.state.value.active.size)
    }

    @Test
    fun activeOrderingIsNewestFirst() {
        controller.start("first", 100.0)
        now = base.plusSeconds(1)
        controller.start("second", 100.0)
        controller.refresh()
        assertEquals(listOf("second", "first"), controller.state.value.active.map { it.name })
    }

    @Test
    fun removeAndClearCompleted() {
        val a = controller.start("A", 10.0)!!
        controller.start("B", 5.0)
        now = base.plusSeconds(5)
        controller.tick() // B completes
        controller.clearCompleted()
        assertTrue(controller.state.value.completed.isEmpty())
        controller.remove(a)
        assertTrue(controller.state.value.active.isEmpty())
    }

    @Test
    fun startAgainClonesCompleted() {
        controller.start("A", 42.0)
        now = base.plusSeconds(42)
        controller.tick()
        val completedId = controller.state.value.completed.single().id
        now = base.plusSeconds(50)
        controller.startAgain(completedId)
        val active = controller.state.value.active.single()
        assertEquals("A", active.name)
        assertEquals(TimerStatus.RUNNING, active.status)
    }

    @Test
    fun restoreFromJsonPreservesRunningRemainingAndName() {
        controller.start("Long", 100.0)
        now = base.plusSeconds(30)
        val json = controller.snapshotJson()

        val restoredController = TimerWorkspaceController { base.plusSeconds(30) }
        restoredController.restoreFromJson(json)
        val item = restoredController.state.value.active.single()
        assertEquals("Long", item.name)
        assertEquals(TimerStatus.RUNNING, item.status)
        assertEquals(70.0, item.remainingSeconds, 1.0)
    }

    @Test
    fun nonPositiveDurationDoesNotStart() {
        assertNull(controller.start("bad", 0.0))
        assertTrue(controller.state.value.active.isEmpty())
    }
}
