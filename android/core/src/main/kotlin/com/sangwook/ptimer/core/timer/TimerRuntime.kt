package com.sangwook.ptimer.core.timer

import java.time.Instant

/**
 * Pure, platform-neutral timer state machine over a collection of timers.
 * Owns no wall clock and no tick loop — callers pass `now` explicitly (the
 * Android coordinator drives ticks). Mirrors the iOS `TimerRuntime`
 * responsibilities at the value-engine level.
 */
class TimerRuntime {
    private val byId = LinkedHashMap<String, TimerState>()

    val timers: List<TimerState> get() = byId.values.toList()

    /** Start a new running timer. Returns the id, or null for a non-positive/non-finite duration. */
    fun start(id: String, durationSeconds: Double, now: Instant): String? {
        if (!durationSeconds.isFinite() || durationSeconds <= 0) return null
        byId[id] = TimerState.running(id, durationSeconds, now)
        return id
    }

    fun pause(id: String, now: Instant) {
        byId[id]?.let { byId[id] = it.pausing(now) }
    }

    fun resume(id: String, now: Instant) {
        byId[id]?.let { byId[id] = it.resume(now) }
    }

    fun remove(id: String) {
        byId.remove(id)
    }

    fun removeCompleted() {
        byId.entries.removeAll { it.value.status == TimerStatus.COMPLETED }
    }

    /**
     * Advance running timers to completion when their end has passed.
     * Returns the ids that transitioned to completed on this tick (the
     * coordinator turns these into exactly-once completion alerts).
     */
    fun tick(now: Instant): List<String> {
        val newlyCompleted = mutableListOf<String>()
        for ((id, state) in byId) {
            if (state is TimerState.Running) {
                val updated = state.updatingStatus(now)
                if (updated.status == TimerStatus.COMPLETED) {
                    byId[id] = updated
                    newlyCompleted += id
                }
            }
        }
        return newlyCompleted
    }

    /**
     * Foreground reconcile: bring running timers to their true status vs the
     * wall clock without emitting completion alerts (no replay on
     * reactivation).
     */
    fun reconcile(now: Instant) {
        for ((id, state) in byId) {
            if (state is TimerState.Running) byId[id] = state.updatingStatus(now)
        }
    }

    /** True when at least one timer is running at [now] (lets the coordinator gate its loop). */
    fun hasRunningTimers(now: Instant): Boolean =
        byId.values.any { it is TimerState.Running && it.statusAt(now) == TimerStatus.RUNNING }

    /** Restore from persisted snapshots, reconciling against [now]; fires no alerts. */
    fun restoreFrom(snapshots: List<PersistentTimerSnapshot>, now: Instant) {
        byId.clear()
        for (snapshot in snapshots) {
            byId[snapshot.id] = snapshot.restore(now)
        }
    }

    /** "Start Again": clone a completed timer into a fresh running timer. */
    fun startAgain(completedId: String, newId: String, now: Instant): String? {
        val source = byId[completedId] as? TimerState.Completed ?: return null
        return start(newId, source.durationSeconds, now)
    }
}
