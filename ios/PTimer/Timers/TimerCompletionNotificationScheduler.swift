// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit
import PTimerCore
import UserNotifications

protocol UserNotificationCentering: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCentering {
    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

@MainActor
final class UserNotificationTimerCompletionScheduler: TimerCompletionNotificationScheduling {
    private let notificationCenter: UserNotificationCentering
    private let calendar: Calendar
    private let dateProvider: () -> Date
    private var hasRequestedAuthorization = false
    /// Per-timer scheduling generation. Bumped on every (re)schedule and on
    /// cancel so an in-flight async add for a superseded generation can detect
    /// it lost the race and refuse to leave stale requests behind (PTIMER-73).
    private var schedulingTokens: [UUID: Int] = [:]
    /// The most recent scheduling task per timer. A new schedule awaits its
    /// predecessor so add sequences for the same timer never run concurrently —
    /// an obsolete task therefore can never interleave with, clobber, or delete
    /// a newer schedule's valid requests (PTIMER-73).
    private var schedulingTasks: [UUID: Task<Void, Never>] = [:]

    /// Pre-alerts within this many seconds of now are treated as effectively
    /// due and skipped, so resuming a long timer near its end never fires a
    /// stale pre-alert. The completion alert is never skipped.
    private static let preAlertSchedulingLeeway: TimeInterval = 0.5

    /// iOS background pre-alert lead times. These are intentionally *earlier*
    /// than the foreground schedule (`TimerAlertSchedule`, T−5 / T−10): local
    /// notifications can be delivered seconds late, so a T−5 alert can arrive
    /// after the timer has already completed. Firing at T−30 / T−15 gives real
    /// margin, and each pre-alert also carries the expected end time as the
    /// source of truth for late delivery (PTIMER-73). The duration buckets
    /// match `TimerAlertSchedule`; only the lead times differ.
    private static let earlyPreAlertLeadSeconds = 30
    private static let latePreAlertLeadSeconds = 15

    init(
        notificationCenter: UserNotificationCentering = UNUserNotificationCenter.current(),
        calendar: Calendar = .current,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.calendar = calendar
        self.dateProvider = dateProvider
    }

    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else {
            return
        }

        hasRequestedAuthorization = true

        Task {
            _ = try? await notificationCenter.requestAuthorization(
                options: [.alert, .sound]
            )
        }
    }

    func scheduleCompletionNotification(for timer: TimerState) {
        guard timer.status == .running, let endDate = timer.endDate else {
            cancelCompletionNotification(forTimerID: timer.id)
            return
        }

        // Open a fresh scheduling generation. This both invalidates any earlier
        // in-flight add task for this timer and becomes the token the new task
        // checks against.
        let token = nextSchedulingToken(for: timer.id)

        // Skip pre-alerts already in the past or effectively due — e.g. a long
        // timer paused near the end and resumed with only a few seconds left,
        // whose pre1/pre2 instants have passed. Completion is always kept.
        let now = dateProvider()
        let timerID = timer.id
        let requests = Self.notificationAlerts(duration: timer.duration, endDate: endDate)
            .filter { Self.shouldSchedule($0, at: now) }
            .map { notificationRequest(for: timerID, alert: $0, endDate: endDate) }

        // Serialize per timer: wait for the prior scheduling task to fully
        // settle before touching this timer's pending requests. Because add
        // sequences never overlap, the broad per-timer removal below can only
        // ever clear *this* generation's own requests — an obsolete task can no
        // longer delete a newer valid schedule (PTIMER-73).
        let previous = schedulingTasks[timerID]
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            // A still-newer schedule (or a cancel) bumped the token while we
            // waited: that task now owns the timer, so do nothing here.
            guard self.schedulingTokens[timerID] == token else { return }

            // We now exclusively own this timer's pending requests: drop any
            // stale stages (e.g. from a resume at a different end instant) and
            // add the current schedule.
            self.removePendingRequests(for: timerID)
            for request in requests {
                // A cancel/reschedule that interleaved between awaits bumps the
                // token: bail and clear anything this task already added so no
                // stale request survives the supersession.
                guard self.schedulingTokens[timerID] == token else {
                    self.removePendingRequests(for: timerID)
                    return
                }
                try? await self.notificationCenter.add(request)
                // Re-check after the add: a cancel/remove can land while this
                // add is in flight (it bumps the token and clears pending), and
                // for the final/only request there is no next iteration to catch
                // the mismatch — so this add could otherwise leave a stale
                // request behind after the cancel.
                guard self.schedulingTokens[timerID] == token else {
                    self.removePendingRequests(for: timerID)
                    return
                }
            }
        }
        schedulingTasks[timerID] = task
    }

    func cancelCompletionNotification(forTimerID timerID: UUID) {
        // Invalidate any in-flight scheduling task for this timer (so a late
        // async add cannot resurrect cancelled stages), then drop pending
        // requests.
        _ = nextSchedulingToken(for: timerID)
        removePendingRequests(for: timerID)
    }

    private func nextSchedulingToken(for timerID: UUID) -> Int {
        let next = (schedulingTokens[timerID] ?? 0) + 1
        schedulingTokens[timerID] = next
        return next
    }

    private func removePendingRequests(for timerID: UUID) {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: Self.allNotificationIdentifiers(for: timerID)
        )
    }

    /// The iOS background notification schedule (PTIMER-73). Same duration
    /// buckets as `TimerAlertSchedule`, but earlier lead times tuned for
    /// notification delivery lag (see `earlyPreAlertLeadSeconds`):
    /// - `duration <= 30s` — completion only.
    /// - `30s < duration <= 60s` — one audible pre-alert at T−15, then completion.
    /// - `duration > 60s` — a gentle (silent) heads-up at T−30, an audible
    ///   pre-alert at T−15, then completion.
    ///
    /// `pre1` is the silent T−30 heads-up (long timers only); `pre2` is the
    /// audible T−15 warning (present whenever any pre-alert is scheduled).
    private static func notificationAlerts(duration: TimeInterval, endDate: Date) -> [TimerStagedAlert] {
        var alerts: [TimerStagedAlert] = []

        if duration > TimerAlertSchedule.secondPreAlertMinimumDuration {
            alerts.append(
                TimerStagedAlert(
                    stage: .pre1,
                    fireDate: endDate.addingTimeInterval(-TimeInterval(earlyPreAlertLeadSeconds)),
                    secondsBeforeCompletion: earlyPreAlertLeadSeconds
                )
            )
        }
        if duration > TimerAlertSchedule.preAlertMinimumDuration {
            alerts.append(
                TimerStagedAlert(
                    stage: .pre2,
                    fireDate: endDate.addingTimeInterval(-TimeInterval(latePreAlertLeadSeconds)),
                    secondsBeforeCompletion: latePreAlertLeadSeconds
                )
            )
        }

        alerts.append(
            TimerStagedAlert(stage: .completion, fireDate: endDate, secondsBeforeCompletion: 0)
        )
        return alerts
    }

    private static func shouldSchedule(_ alert: TimerStagedAlert, at now: Date) -> Bool {
        switch alert.stage {
        case .completion:
            return true
        case .pre1, .pre2:
            return alert.fireDate.timeIntervalSince(now) > preAlertSchedulingLeeway
        }
    }

    private func notificationRequest(
        for timerID: UUID,
        alert: TimerStagedAlert,
        endDate: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.userInfo = ["timerID": timerID.uuidString]

        switch alert.stage {
        case .pre1:
            // Gentle (silent) early heads-up at T−30 for long timers. Like the
            // audible pre2 it carries the expected end time, because the
            // notification can be delivered late; the "Ns remaining" describes
            // the scheduled point, not the delivery instant (PTIMER-73).
            content.title = String(localized: "Timer finishing soon")
            content.body = Self.preAlertBody(secondsBefore: alert.secondsBeforeCompletion, endDate: endDate)
            content.sound = nil
        case .pre2:
            // The primary audible pre-alert (T−15). Auto-suppressed in the
            // foreground (no notification-center delegate), so it surfaces only
            // when the app is not foreground.
            content.title = String(localized: "Timer finishing soon")
            content.body = Self.preAlertBody(secondsBefore: alert.secondsBeforeCompletion, endDate: endDate)
            content.sound = .default
        case .completion:
            content.title = String(localized: "Timer complete")
            content.body = String(localized: "Your timer has finished.")
            content.sound = .default
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: alert.fireDate
            ),
            repeats: false
        )
        return UNNotificationRequest(
            identifier: Self.notificationIdentifier(for: timerID, stage: alert.stage),
            content: content,
            trigger: trigger
        )
    }

    /// Pre-alert body: the scheduled remaining time plus the expected end time
    /// in the user's local short time style, so the target is unambiguous even
    /// if the notification is delivered late (PTIMER-73).
    private static func preAlertBody(secondsBefore: Int, endDate: Date) -> String {
        String(localized: "\(secondsBefore)s remaining · ends \(endDate.formatted(date: .omitted, time: .shortened))")
    }

    static func notificationIdentifier(for timerID: UUID) -> String {
        notificationIdentifier(for: timerID, stage: .completion)
    }

    static func notificationIdentifier(for timerID: UUID, stage: TimerAlertStage) -> String {
        "timer-\(stage.rawValue)-\(timerID.uuidString.lowercased())"
    }

    static func allNotificationIdentifiers(for timerID: UUID) -> [String] {
        TimerAlertStage.allCases.map { notificationIdentifier(for: timerID, stage: $0) }
    }
}
