// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.timer

import com.sangwook.ptimer.app.notify.TimerAlarmPlayer
import com.sangwook.ptimer.app.vm.ShootingIntent
import com.sangwook.ptimer.app.vm.ShootingViewModel
import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.persistence.WorkspacePersistenceStoring
import com.sangwook.ptimer.core.timer.TimerIdentity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant
import java.util.UUID

/**
 * PTIMER-216: pins the Timer spec §6 display-ordering contract at the
 * view-model layer by reproducing the ordering transformation
 * `TimerListScreen` currently applies (`state.active.asReversed()` /
 * `state.history`) — active timers most-recently-created first, completed
 * timers most-recently-completed first — across representative mixed timer
 * states. It asserts on view-model state, not on the Composable itself. Does
 * not move or redesign ordering ownership (PTIMER-194 remains open).
 */
class TimerWorkspaceOrderingTest {

    private val t0: Instant = Instant.parse("2026-06-20T00:00:00Z")

    private class NoOpStore : WorkspacePersistenceStoring {
        override fun loadSnapshot(): PersistentWorkspaceSnapshot? = null
        override fun saveSnapshot(snapshot: PersistentWorkspaceSnapshot) {}
        override fun clearSnapshot() {}
    }

    private class NoOpAlarmPlayer : TimerAlarmPlayer {
        private val _soundingTimerId = MutableStateFlow<UUID?>(null)
        override val soundingTimerId: StateFlow<UUID?> = _soundingTimerId.asStateFlow()
        override fun playAlarm(timerId: UUID) {}
        override fun stop() {}
    }

    private fun identity(label: String) = TimerIdentity(title = label, slotLabel = label)

    @Test
    fun activeGroupOrdersMostRecentlyCreatedFirst() {
        var now = t0
        var counter = 0
        val sut = ShootingViewModel(
            store = NoOpStore(),
            clock = { now },
            idProvider = { UUID.fromString("00000000-0000-0000-0000-%012d".format(++counter)) },
            alarmPlayer = NoOpAlarmPlayer(),
        )

        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("A")))
        now = t0.plusSeconds(1)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("B")))
        now = t0.plusSeconds(2)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("C")))

        // The display order (matching TimerListScreen's `state.active.asReversed()`)
        // is LIFO by creation: C (newest), then B, then A (oldest).
        val displayOrder = sut.uiState.value.active.asReversed().map { it.identity.title }
        assertEquals(listOf("C", "B", "A"), displayOrder)
    }

    @Test
    fun activeGroupKeepsLifoOrderAcrossMixedRunningAndPausedStates() {
        var now = t0
        var counter = 0
        val sut = ShootingViewModel(
            store = NoOpStore(),
            clock = { now },
            idProvider = { UUID.fromString("00000000-0000-0000-0000-%012d".format(++counter)) },
            alarmPlayer = NoOpAlarmPlayer(),
        )

        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("A")))
        val idA = sut.uiState.value.active.first().id
        now = t0.plusSeconds(1)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("B")))
        now = t0.plusSeconds(2)
        sut.onEvent(ShootingIntent.Pause(idA))
        now = t0.plusSeconds(3)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("C")))

        // Running and paused both belong to "active" and share one LIFO domain
        // regardless of status — A (paused) keeps its creation-order slot here.
        val displayOrder = sut.uiState.value.active.asReversed().map { it.identity.title }
        assertEquals(listOf("C", "B", "A"), displayOrder)
    }

    @Test
    fun historyGroupOrdersMostRecentlyCompletedFirst() {
        var now = t0
        var counter = 0
        val sut = ShootingViewModel(
            store = NoOpStore(),
            clock = { now },
            idProvider = { UUID.fromString("00000000-0000-0000-0000-%012d".format(++counter)) },
            alarmPlayer = NoOpAlarmPlayer(),
        )

        sut.onEvent(ShootingIntent.StartTimer(10.0, identity("A")))
        now = t0.plusSeconds(11)
        sut.tick(now) // A completes at t0+11.

        sut.onEvent(ShootingIntent.StartTimer(20.0, identity("B")))
        val idB = sut.uiState.value.active.first { it.identity.title == "B" }.id
        now = t0.plusSeconds(15)
        sut.onEvent(ShootingIntent.Cancel(idB)) // B canceled at t0+15 (later than A's completion).

        sut.onEvent(ShootingIntent.StartTimer(5.0, identity("C")))
        now = t0.plusSeconds(21)
        sut.tick(now) // C completes at t0+21 (the most recent terminal stamp).

        // Completed group: sorted by terminal stamp descending, regardless of
        // whether the terminal state is completed or canceled.
        val displayOrder = sut.uiState.value.history.map { it.identity.title }
        assertEquals(listOf("C", "B", "A"), displayOrder)
    }
}
