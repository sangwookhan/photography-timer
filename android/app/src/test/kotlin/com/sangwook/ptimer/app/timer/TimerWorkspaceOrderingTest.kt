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
 * PTIMER-194 / PTIMER-216: pins the Timer spec §6 display-ordering contract now
 * that the workspace ([TimerWorkspace.active] / [TimerWorkspace.history]) is the
 * single owner of ordering — active timers most-recently-created first,
 * terminal timers most-recently-finished first — across representative mixed
 * timer states, plus deterministic tie-breaks when creation counters or
 * terminal stamps collide.
 *
 * These assert on the ordering the view model publishes ([ShootingViewModel]
 * driven via `onEvent`/`tick`), i.e. the exact `state.active` / `state.history`
 * lists both timer surfaces render. They do not run the Composables: the compact
 * [com.sangwook.ptimer.app.ui.timer.MiniTimerBar] and expanded
 * `FullTimerList` now consume those lists verbatim (the previous
 * `state.active.asReversed()` transform was removed in PTIMER-194), so the order
 * asserted here is the order both surfaces show.
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

    /** A view model with a movable clock and deterministic, ascending ids. */
    private fun viewModel(nowSupplier: () -> Instant): ShootingViewModel {
        var counter = 0
        return ShootingViewModel(
            store = NoOpStore(),
            clock = nowSupplier,
            idProvider = { UUID.fromString("00000000-0000-0000-0000-%012d".format(++counter)) },
            alarmPlayer = NoOpAlarmPlayer(),
        )
    }

    @Test
    fun activeGroupOrdersMostRecentlyCreatedFirst() {
        var now = t0
        val sut = viewModel { now }

        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("A")))
        now = t0.plusSeconds(1)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("B")))
        now = t0.plusSeconds(2)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("C")))

        // Single-owner display order: LIFO by creation — C (newest), B, A.
        val displayOrder = sut.uiState.value.active.map { it.identity.title }
        assertEquals(listOf("C", "B", "A"), displayOrder)
    }

    @Test
    fun activeGroupKeepsLifoOrderAcrossMixedRunningAndPausedStates() {
        var now = t0
        val sut = viewModel { now }

        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("A")))
        val idA = sut.uiState.value.active.first().id
        now = t0.plusSeconds(1)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("B")))
        now = t0.plusSeconds(2)
        sut.onEvent(ShootingIntent.Pause(idA))
        now = t0.plusSeconds(3)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("C")))

        // Running and paused both belong to "active" and share one LIFO domain
        // regardless of status — A (paused) keeps its creation-order slot.
        val displayOrder = sut.uiState.value.active.map { it.identity.title }
        assertEquals(listOf("C", "B", "A"), displayOrder)
    }

    @Test
    fun runningToPausedToRunningDoesNotReorderActive() {
        var now = t0
        val sut = viewModel { now }

        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("A")))
        now = t0.plusSeconds(1)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("B")))
        now = t0.plusSeconds(2)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("C")))
        val idB = sut.uiState.value.active.first { it.identity.title == "B" }.id

        val before = sut.uiState.value.active.map { it.identity.title }

        // A pause then resume of the middle timer must not move it: ordering is
        // keyed on creation order, not the start/resume instant.
        now = t0.plusSeconds(3)
        sut.onEvent(ShootingIntent.Pause(idB))
        val whilePaused = sut.uiState.value.active.map { it.identity.title }
        now = t0.plusSeconds(4)
        sut.onEvent(ShootingIntent.Resume(idB))
        val afterResume = sut.uiState.value.active.map { it.identity.title }

        assertEquals(listOf("C", "B", "A"), before)
        assertEquals(listOf("C", "B", "A"), whilePaused)
        assertEquals(listOf("C", "B", "A"), afterResume)
    }

    @Test
    fun activeGroupTieBreakIsDeterministicForEqualStartInstants() {
        val fixed = t0
        val sut = viewModel { fixed } // clock never advances: identical start instants.

        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("A")))
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("B")))
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("C")))

        // Same start instant for all three, so creation order (not the timestamp)
        // decides: C, B, A — deterministic despite the timestamp collision.
        val displayOrder = sut.uiState.value.active.map { it.identity.title }
        assertEquals(listOf("C", "B", "A"), displayOrder)
    }

    @Test
    fun historyGroupOrdersMostRecentlyFinishedFirstAcrossCompletedAndCanceled() {
        var now = t0
        val sut = viewModel { now }

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

        // History: terminal stamp descending, regardless of completed vs canceled.
        val displayOrder = sut.uiState.value.history.map { it.identity.title }
        assertEquals(listOf("C", "B", "A"), displayOrder)
    }

    @Test
    fun canceledOnlyHistoryOrdersMostRecentlyCanceledFirst() {
        var now = t0
        val sut = viewModel { now }

        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("A")))
        val idA = sut.uiState.value.active.first { it.identity.title == "A" }.id
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("B")))
        val idB = sut.uiState.value.active.first { it.identity.title == "B" }.id

        now = t0.plusSeconds(5)
        sut.onEvent(ShootingIntent.Cancel(idA)) // A canceled at t0+5.
        now = t0.plusSeconds(8)
        sut.onEvent(ShootingIntent.Cancel(idB)) // B canceled at t0+8 (more recent).

        val displayOrder = sut.uiState.value.history.map { it.identity.title }
        assertEquals(listOf("B", "A"), displayOrder)
    }

    @Test
    fun historyGroupTieBreakIsDeterministicForEqualTerminalStamps() {
        var now = t0
        val sut = viewModel { now }

        // Two timers with identical duration started at the same instant finish
        // at the same terminal stamp.
        sut.onEvent(ShootingIntent.StartTimer(10.0, identity("A")))
        sut.onEvent(ShootingIntent.StartTimer(10.0, identity("B")))
        now = t0.plusSeconds(11)
        sut.tick(now) // Both complete at t0+10 (identical endDate).

        // Equal terminal stamps fall back to creation order descending: B, A —
        // deterministic despite the collision.
        val displayOrder = sut.uiState.value.history.map { it.identity.title }
        assertEquals(listOf("B", "A"), displayOrder)
    }

    @Test
    fun publishedOrderMatchesBothSurfaceConsumptionContract() {
        var now = t0
        val sut = viewModel { now }

        sut.onEvent(ShootingIntent.StartTimer(10.0, identity("A")))
        now = t0.plusSeconds(11)
        sut.tick(now) // A completes.
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("B")))
        now = t0.plusSeconds(12)
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity("C")))

        val state = sut.uiState.value
        // The compact dock (MiniTimerBar) renders active-then-history; the
        // expanded list (FullTimerList) renders the same active list in its
        // Active section and the same history list in its History section. Both
        // read these lists verbatim after PTIMER-194, so the active sub-sequence
        // and history sub-sequence are identical across surfaces.
        val compactDock = state.active + state.history
        assertEquals(listOf("C", "B", "A"), compactDock.map { it.identity.title })
        assertEquals(listOf("C", "B"), state.active.map { it.identity.title })
        assertEquals(listOf("A"), state.history.map { it.identity.title })
    }
}
