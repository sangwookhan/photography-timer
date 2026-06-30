// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import UIKit
import PTimerCore
import PTimerKit

@MainActor
struct SystemTimerCompletionFeedbackPlayer: TimerCompletionFeedbackPlaying {
    private let alarmPlayer: TimerAlarmAudioPlaying

    init(alarmPlayer: TimerAlarmAudioPlaying = AVAudioTimerAlarmPlayer()) {
        self.alarmPlayer = alarmPlayer
    }

    func playCompletionFeedback(for timerID: UUID) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        // App-owned playback (AVAudioSession .playback) so a foreground
        // completion is audible even in silent mode (PTIMER-73), unlike the
        // ring-switch-obeying system sound it replaces.
        alarmPlayer.playCompletionAlarm(for: timerID)
    }

    /// Foreground pre1 feedback (PTIMER-73): haptic-first and silent. A medium
    /// impact stands in for "completion approaching" without competing with the
    /// stronger success haptic + sound reserved for actual completion.
    func playPreAlertFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
}

@MainActor
final class ForegroundTimerCompletionAlertService: TimerCompletionAlerting {
    private let feedbackPlayer: TimerCompletionFeedbackPlaying
    private let applicationStateProvider: @MainActor () -> UIApplication.State
    private let dateProvider: () -> Date

    /// A completion older than this when it reaches us is treated as a stale,
    /// caught-up event (a timer that finished while the app was backgrounded)
    /// rather than a live one, so its alarm is suppressed (PTIMER-73).
    private static let liveCompletionGracePeriod: TimeInterval = 2

    init(
        feedbackPlayer: TimerCompletionFeedbackPlaying,
        applicationStateProvider: @escaping @MainActor () -> UIApplication.State = {
            UIApplication.shared.applicationState
        },
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.feedbackPlayer = feedbackPlayer
        self.applicationStateProvider = applicationStateProvider
        self.dateProvider = dateProvider
    }

    func handleTimerCompletion(_ event: TimerCompletionEvent) {
        // Only a live foreground completion rings (PTIMER-73). Background/locked
        // completions are delivered by local notifications, not here. The risk
        // this guards against: after a timer finishes while backgrounded, the
        // suspended RunLoop tick fires a catch-up `tick()` on app return, which
        // emits this completion late while the app is now active. Without the
        // freshness check that would play a stale alarm minutes after the fact —
        // the worst-case behavior reported on device. App-return reconciliation
        // still updates the timer's completed state silently.
        guard applicationStateProvider() == .active else {
            return
        }
        guard dateProvider().timeIntervalSince(event.completionDate) <= Self.liveCompletionGracePeriod else {
            return
        }
        feedbackPlayer.playCompletionFeedback(for: event.timerID)
    }

    func handlePreAlert(_ event: TimerPreAlertEvent) {
        // Pre-alerts are foreground perception only; the runtime already
        // restricts emission to pre1. Mirror completion's active-state guard so
        // a backgrounded process never buzzes silently.
        guard applicationStateProvider() == .active else {
            return
        }

        feedbackPlayer.playPreAlertFeedback()
    }
}

@MainActor
final class TimerManager: ObservableObject, TimerManaging {
    @Published private(set) var timers: [TimerState] = []

    var timersPublisher: AnyPublisher<[TimerState], Never> { $timers.eraseToAnyPublisher() }

    var currentDate: Date {
        runtime.currentDate
    }

    private let tickInterval: TimeInterval
    private let dateProvider: () -> Date
    private let runtime: TimerRuntime
    private var timer: Timer?
    private var cancellable: AnyCancellable?

    init(
        tickInterval: TimeInterval = 0.1,
        dateProvider: @escaping () -> Date = Date.init,
        completionAlertService: TimerCompletionAlerting = NoOpTimerCompletionAlertService(),
        completionNotificationScheduler: TimerCompletionNotificationScheduling = NoOpTimerCompletionScheduler(),
        persistenceStore: TimerPersistenceStoring = NoOpTimerPersistenceStore()
    ) {
        self.tickInterval = tickInterval
        self.dateProvider = dateProvider
        self.runtime = TimerRuntime(
            dateProvider: dateProvider,
            completionAlertService: completionAlertService,
            completionNotificationScheduler: completionNotificationScheduler,
            persistenceStore: persistenceStore
        )

        // Mirror the pure runtime's published timers onto this coordinator so
        // existing SwiftUI/Combine observers of `TimerManager.$timers` keep
        // working unchanged.
        cancellable = runtime.$timers
            .sink { [weak self] states in
                self?.timers = states
            }

        // The runtime may have restored running timers in its initializer;
        // start the RunLoop ticking loop if so.
        reconcileTickingLoop()
    }

    @discardableResult
    func start(id: UUID = UUID(), duration: TimeInterval) -> UUID? {
        let result = runtime.start(id: id, duration: duration)
        reconcileTickingLoop()
        return result
    }

    func pause(id: UUID) {
        runtime.pause(id: id)
        reconcileTickingLoop()
    }

    func resume(id: UUID) {
        runtime.resume(id: id)
        reconcileTickingLoop()
    }

    func tick(now: Date? = nil) {
        runtime.tick(now: now)
        reconcileTickingLoop(now: now)
    }

    func reconcile(now: Date? = nil) {
        runtime.reconcile(now: now)
        reconcileTickingLoop(now: now)
    }

    func removeCompletedTimers() {
        runtime.removeCompletedTimers()
        reconcileTickingLoop()
    }

    func cancel(id: UUID) {
        runtime.cancel(id: id)
        reconcileTickingLoop()
    }

    func remove(id: UUID) {
        runtime.remove(id: id)
        reconcileTickingLoop()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - RunLoop ticking (OS I/O)

    /// Starts the RunLoop ticking loop when a timer is running and stops it
    /// otherwise. This is the only timer responsibility that requires OS I/O;
    /// every state transition lives in `TimerRuntime`.
    private func reconcileTickingLoop(now: Date? = nil) {
        let currentDate = now ?? dateProvider()
        if runtime.hasRunningTimers(at: currentDate) {
            ensureTimerLoop()
        } else {
            stopLoop()
        }
    }

    private func ensureTimerLoop() {
        guard timer == nil else {
            return
        }

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }

        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopLoop() {
        timer?.invalidate()
        timer = nil
    }
}

/// UserDefaults-backed timer persistence. OS I/O adapter — kept in the app
/// target (not in PTimerCore, which must stay Android-portable).
struct UserDefaultsTimerPersistenceStore: TimerPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.timer-state.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSnapshot() -> PersistentTimerCollectionSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentTimerCollectionSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
