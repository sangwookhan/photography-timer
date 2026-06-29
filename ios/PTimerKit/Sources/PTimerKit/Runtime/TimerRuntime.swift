// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// The pure, platform-neutral timer runtime extracted from the app's
/// `TimerManager`. It owns the live `[TimerState]` collection and the
/// start/pause/resume/tick/reconcile/remove transitions, emits completion
/// effects through injected protocols (alert / notification / persistence),
/// and publishes `timers` for an observer to bind to.
///
/// It deliberately contains **no** OS I/O: no `RunLoop`/`Timer` scheduling,
/// no UIKit, no UserNotifications, no ActivityKit. The app's `TimerManager`
/// owns those, drives `tick()` from a `RunLoop` timer, and starts/stops that
/// loop based on `timers`.
@MainActor
public final class TimerRuntime: ObservableObject {
    @Published public private(set) var timers: [TimerState] = []

    public var currentDate: Date {
        dateProvider()
    }

    private let dateProvider: () -> Date
    private let completionAlertService: TimerCompletionAlerting
    private let completionNotificationScheduler: TimerCompletionNotificationScheduling
    private let persistenceStore: TimerPersistenceStoring
    private var hasRestoredPersistedTimers = false
    /// Instant of the last foreground-tick reconciliation, used to detect
    /// pre-alert crossings within `(lastForegroundTickDate, now]`. `nil` until
    /// the first foreground tick so a freshly restored runtime never replays
    /// pre-alerts that already passed.
    private var lastForegroundTickDate: Date?

    public init(
        dateProvider: @escaping () -> Date = Date.init,
        completionAlertService: TimerCompletionAlerting = NoOpTimerCompletionAlertService(),
        completionNotificationScheduler: TimerCompletionNotificationScheduling = NoOpTimerCompletionScheduler(),
        persistenceStore: TimerPersistenceStoring = NoOpTimerPersistenceStore()
    ) {
        self.dateProvider = dateProvider
        self.completionAlertService = completionAlertService
        self.completionNotificationScheduler = completionNotificationScheduler
        self.persistenceStore = persistenceStore

        restorePersistedTimersIfNeeded()
    }

    /// Whether any timer is running at the given instant. The OS coordinator
    /// uses this to decide whether its `RunLoop` ticking loop should run.
    public func hasRunningTimers(at date: Date) -> Bool {
        timers.contains { $0.status(at: date) == .running }
    }

    @discardableResult
    public func start(id: UUID = UUID(), duration: TimeInterval) -> UUID? {
        // Per Timer Spec §1.2, the system rejects creation with non-positive,
        // non-finite, or NaN duration values. `> 0` admits `+Infinity`
        // (`.infinity > 0` is true) so `isFinite` must be checked explicitly.
        // NaN comparisons return false in both directions, so the `> 0` guard
        // already rejects NaN.
        guard duration.isFinite, duration > 0 else {
            return nil
        }

        let now = dateProvider()
        let endDate = now.addingTimeInterval(duration)
        timers.append(
            TimerState(
                id: id,
                duration: duration,
                startDate: now,
                endDate: endDate,
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running
            )
        )
        completionNotificationScheduler.requestAuthorizationIfNeeded()
        if let timer = timers.last {
            completionNotificationScheduler.scheduleCompletionNotification(for: timer)
        }
        persistTimers()
        return id
    }

    public func pause(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else {
            return
        }

        let currentDate = dateProvider()
        timers[index] = timers[index].pausing(at: currentDate)
        completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
        persistTimers()
    }

    public func resume(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else {
            return
        }

        let currentDate = dateProvider()
        let newState = timers[index].resume(at: currentDate)
        timers[index] = newState

        if newState.status == .running {
            completionNotificationScheduler.requestAuthorizationIfNeeded()
            completionNotificationScheduler.scheduleCompletionNotification(for: newState)
        } else {
            completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
        }

        persistTimers()
    }

    public func tick(now: Date? = nil) {
        guard !timers.isEmpty else {
            return
        }

        let currentDate = now ?? dateProvider()
        // Regular foreground ticking keeps timer state fresh and is allowed to
        // emit foreground completion alerts when a running timer finishes now.
        applyRunningStateReconciliation(
            now: currentDate,
            shouldEmitCompletionAlerts: true
        )
    }

    public func reconcile(now: Date? = nil) {
        guard !timers.isEmpty else {
            return
        }

        let currentDate = now ?? dateProvider()
        // Foreground reactivation runs while the same process is still alive.
        // Relaunch restore happens only once in init and must
        // not be re-entered from lifecycle hooks like this.
        applyRunningStateReconciliation(
            now: currentDate,
            shouldEmitCompletionAlerts: false
        )
    }

    public func removeCompletedTimers() {
        let currentDate = dateProvider()
        let completedIDs = timers
            .filter { $0.status(at: currentDate) == .completed }
            .map(\.id)
        completedIDs.forEach { id in
            completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
        }
        timers.removeAll { $0.status(at: currentDate) == .completed }

        persistTimers()
    }

    public func remove(id: UUID) {
        completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
        timers.removeAll { $0.id == id }
        persistTimers()
    }

    /// Cancels a running or paused timer, transitioning it to the
    /// terminal `canceled` record (kept in `timers`, unlike `remove`).
    /// Pending completion notifications are dropped because the timer
    /// will no longer finish. Already-terminal timers are left intact.
    public func cancel(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else {
            return
        }

        let now = dateProvider()
        timers[index] = timers[index].canceled(at: now)
        completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
        persistTimers()
    }

    private func completionEvent(
        from previous: TimerState,
        to updated: TimerState
    ) -> TimerCompletionEvent? {
        guard previous.status == .running,
              updated.status == .completed,
              let completionDate = updated.endDate else {
            return nil
        }

        return TimerCompletionEvent(
            timerID: updated.id,
            completionDate: completionDate
        )
    }

    /// Emits a pre-alert event for every pre1 crossing in
    /// `(lastForegroundTickDate, now]`. Only timers that were running before
    /// this tick are considered, and only the pre1 stage is emitted; pre2 is a
    /// not-foreground-only escalation handled by the background scheduler. With
    /// `lastTick == nil` (the first foreground tick) no window exists yet, so
    /// nothing is emitted and the baseline is simply established by the caller.
    private func emitForegroundPreAlerts(
        from previousTimers: [TimerState],
        since lastTick: Date?,
        now currentDate: Date
    ) {
        guard let lastTick else {
            return
        }

        for state in previousTimers where state.status == .running {
            guard let endDate = state.endDate else {
                continue
            }

            let preAlerts = TimerAlertSchedule
                .alerts(duration: state.duration, endDate: endDate)
                .filter { $0.stage == .pre1 }

            for alert in preAlerts where alert.fireDate > lastTick && alert.fireDate <= currentDate {
                completionAlertService.handlePreAlert(
                    TimerPreAlertEvent(
                        timerID: state.id,
                        stage: alert.stage,
                        secondsBeforeCompletion: alert.secondsBeforeCompletion
                    )
                )
            }
        }
    }

    private func applyRunningStateReconciliation(
        now currentDate: Date,
        shouldEmitCompletionAlerts: Bool
    ) {
        // Only running timers can advance to completed here. Paused timers are
        // frozen/resumable and keep their preserved remaining time regardless of
        // wall-clock passage, and completed timers remain completed.
        let previousTimers = timers
        let transitionResult = timers.map { state in
            let updated = state.updatingStatus(at: currentDate)
            return (updated, completionEvent(from: state, to: updated))
        }

        timers = transitionResult.map(\.0)

        if shouldEmitCompletionAlerts {
            // Foreground pre-alerts (PTIMER-73) fire before completion alerts so
            // a crossing and a completion in the same tick keep their natural
            // order. pre2 is intentionally never emitted here: it is a
            // not-foreground-only escalation delivered solely as a background
            // notification.
            emitForegroundPreAlerts(
                from: previousTimers,
                since: lastForegroundTickDate,
                now: currentDate
            )
            transitionResult
                .compactMap(\.1)
                .forEach(completionAlertService.handleTimerCompletion)
        }

        // Advance the foreground-tick window regardless of branch so a
        // background reactivation (`shouldEmitCompletionAlerts == false`) moves
        // the window forward without replaying already-passed pre-alerts.
        lastForegroundTickDate = currentDate

        transitionResult
            .filter { $0.1 != nil }
            .forEach { updated, _ in
                completionNotificationScheduler.cancelCompletionNotification(
                    forTimerID: updated.id
                )
            }

        persistTimers()
    }

    private func restorePersistedTimersIfNeeded() {
        guard !hasRestoredPersistedTimers else {
            return
        }

        hasRestoredPersistedTimers = true

        guard let snapshot = persistenceStore.loadSnapshot() else {
            return
        }

        let currentDate = dateProvider()
        timers = snapshot.timers.map { $0.restore(at: currentDate) }

        // Relaunch restore is deterministic and init-only: it reads the
        // saved snapshot once, reconciles only running timers against wall
        // clock time, preserves paused timers as frozen resumable state, and
        // writes the normalized result back as the new source.
        persistTimers()
    }

    private func persistTimers() {
        guard !timers.isEmpty else {
            persistenceStore.clearSnapshot()
            return
        }

        persistenceStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(timers: timers)
        )
    }
}
