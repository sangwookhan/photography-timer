// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sangwook.ptimer.app.notify.TimerAlarmPlayer
import com.sangwook.ptimer.app.persistence.AppPersistenceWriter
import com.sangwook.ptimer.app.persistence.OrderedPersistenceWriter
import com.sangwook.ptimer.app.timer.AndroidTimerCoordinator
import com.sangwook.ptimer.core.customfilm.CustomFilmLibrary
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.persistence.SlotSessionStoring
import com.sangwook.ptimer.core.persistence.WorkspacePersistenceStoring
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.timer.TimerStatus
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

/**
 * Quiet window between the last calculator change and its slot-session write,
 * keeping persistence off the hot wheel-tick path. Owned by [viewModelScope]
 * (PTIMER-223), so a configuration change no longer interrupts the window —
 * the collector keeps running and the pending write still lands.
 */
private const val SLOT_SESSION_DEBOUNCE_MILLIS = 400L

/**
 * Delivers the in-app completion alert for a timer that just finished while
 * the app process is alive. Injected so the owner stays free of Android
 * notification calls; production posts through `TimerNotifications` (which
 * de-dupes against the AlarmManager delivery path), tests record the calls.
 */
fun interface TimerCompletionNotifier {
    fun notifyCompletion(card: TimerCardState)
}

/**
 * AndroidX lifecycle owner of the app's screen state (PTIMER-223). Holds the
 * pure Kotlin state holders — [ShootingViewModel] for the timer workspace,
 * [CalculatorController] for the calculator across camera slots, and the
 * [CustomFilmLibrary] — across configuration changes, so Activity recreation
 * reuses the committed in-memory state instead of rebuilding it from
 * persistence. Process death still restores from the durable stores via the
 * unchanged restore path.
 *
 * This type is deliberately thin: it wires lifecycle to the existing state
 * machines and owns their asynchronous work in [viewModelScope] —
 *
 * - the one-shot timer-workspace restore, which now runs once per ViewModel
 *   lifetime rather than once per recreation;
 * - the debounced calculator slot-session persistence collector, formerly a
 *   Compose `LaunchedEffect`, whose debounce window a recreation destroyed;
 * - a single timer-state collector that, in order, delivers the completion
 *   alert, records the running-transition tracking, and drives the
 *   wall-clock tick loop ([AndroidTimerCoordinator]). The loop keeps ticking
 *   through a recreation, and because it can complete a timer while the
 *   Composition is gone, the seen-running/notified sets must outlive the UI
 *   and be recorded before the loop starts — a composition-owned or separate
 *   collector could miss that completion.
 *
 * All state logic stays in the held types; they remain plain Kotlin and
 * JVM-unit-testable. Dependencies are injected so this owner is too.
 */
@OptIn(FlowPreview::class)
class ShootingAppViewModel(
    films: List<FilmIdentity>,
    /** Custom film library; retained here so UI generations share one instance. */
    val library: CustomFilmLibrary,
    initialSession: PersistentSlotSession?,
    timerStore: WorkspacePersistenceStoring,
    alarmPlayer: TimerAlarmPlayer,
    private val slotStore: SlotSessionStoring,
    private val completionNotifier: TimerCompletionNotifier,
    clock: () -> Instant = { Instant.now() },
    private val persistence: OrderedPersistenceWriter = AppPersistenceWriter,
) : ViewModel() {

    /** Timer workspace state holder (unchanged pure Kotlin type). */
    val timers = ShootingViewModel(
        store = timerStore,
        clock = clock,
        alarmPlayer = alarmPlayer,
        persistenceWriter = persistence,
    )

    /** Calculator state holder across camera slots (unchanged pure Kotlin type). */
    val calculator = CalculatorController(
        films = films,
        onStart = { duration, identity ->
            timers.onEvent(ShootingIntent.StartTimer(duration, identity))
        },
        initialSession = initialSession,
    )

    private val coordinator = AndroidTimerCoordinator(viewModelScope, timers, clock)

    init {
        // Restore the timer workspace once per ViewModel lifetime. On a
        // configuration change the retained workspace state simply survives;
        // only a new owner — a fresh process, or a new Activity after the
        // previous one finished and cleared this owner — reaches this read.
        // The ordered read still waits behind any write already submitted to
        // the shared writer within this process.
        viewModelScope.launch {
            val snapshot = persistence.readOrdered { timers.readPersistedSnapshot() }
            timers.restore(snapshot)
        }

        // Persist the slot session off the hot wheel-tick path: debounce the
        // state stream and write the latest exported session. `drop(1)` skips
        // the initial emission so a fresh launch does not immediately rewrite
        // the restored state. The write goes through the shared ordered writer,
        // so a later bootstrap read observes it.
        viewModelScope.launch {
            calculator.state.drop(1).debounce(SLOT_SESSION_DEBOUNCE_MILLIS).collect {
                val session = calculator.exportSession()
                persistence.submit { runCatching { slotStore.saveSession(session) } }
            }
        }

        // One collector drives the completion alert, the running-transition
        // tracking, and the tick loop — in that order within each emission,
        // so the emission that first shows a timer running records it in
        // seenRunning BEFORE the coordinator can start ticking. Two separate
        // collectors would leave that ordering to chance: the tick loop's
        // first (immediate) tick could complete a just-restored, nearly
        // expired timer before the tracking ever observed it running, and
        // the alert would be skipped.
        //
        // The alert rings the moment a timer finishes while the process is
        // alive (foreground, backgrounded, or mid-recreation with no
        // Composition attached), not only via the AlarmManager alarm. On the
        // inexact-alarm fallback the running-set sync cancels a just-
        // completed timer's alarm before it fires, so this collector is the
        // delivery path — it must survive recreation, which is why the
        // seen-running/notified transition sets live here and not in a
        // Compose effect. Only ids this owner saw running notify, and each
        // at most once, so a UI generation attaching or detaching can
        // neither duplicate nor resurrect an alert.
        viewModelScope.launch {
            var seenRunning = setOf<UUID>()
            var notified = setOf<UUID>()
            timers.uiState.collect { state ->
                state.history
                    .filter { it.status == TimerStatus.completed && it.id in seenRunning && it.id !in notified }
                    .forEach { card ->
                        // A notifier failure must not kill this collector —
                        // it also drives the tick loop. A failed id is not
                        // marked notified, so the next state emission simply
                        // retries it.
                        val delivered = runCatching { completionNotifier.notifyCompletion(card) }.isSuccess
                        if (delivered) notified = notified + card.id
                    }
                seenRunning = seenRunning +
                    state.active.filter { it.status == TimerStatus.running }.map { it.id }
                // Tick loop follows the running set: start is idempotent, and
                // the loop itself exits once nothing is running.
                if (timers.hasRunningTimers) coordinator.start() else coordinator.stop()
            }
        }
    }

    /**
     * Flushes a pending debounced slot-session write when the owner goes away
     * for good (Activity finish, not a configuration change), so a calculator
     * change committed inside the debounce window is not lost with the scope.
     */
    override fun onCleared() {
        val session = calculator.exportSession()
        persistence.submit { runCatching { slotStore.saveSession(session) } }
    }
}
