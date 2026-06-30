// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The discrete stages of timer-completion awareness.
///
/// `pre1` and `pre2` are *pre-alerts* that fire before completion to make a
/// timer harder to miss in the field; `completion` is the existing terminal
/// alert at the timer's end instant.
public enum TimerAlertStage: String, Equatable, CaseIterable, Sendable {
    /// First, gentle "completion is approaching" pre-alert (haptic-first).
    case pre1
    /// Stronger "finishing soon" pre-alert. Used only when the app is not in
    /// the foreground (long timers only).
    case pre2
    /// The terminal completion alert at the timer's end instant.
    case completion
}

/// A single staged alert: which stage, when it fires, and how many seconds
/// remain to completion at that instant (`0` for the completion alert). The
/// remaining-seconds value drives user-facing copy such as "10s remaining".
public struct TimerStagedAlert: Equatable, Sendable {
    public let stage: TimerAlertStage
    public let fireDate: Date
    public let secondsBeforeCompletion: Int

    public init(stage: TimerAlertStage, fireDate: Date, secondsBeforeCompletion: Int) {
        self.stage = stage
        self.fireDate = fireDate
        self.secondsBeforeCompletion = secondsBeforeCompletion
    }
}

/// Pure, platform-neutral policy mapping a timer's duration and end instant to
/// the staged alerts it should produce (PTIMER-73).
///
/// Duration buckets:
/// - `duration <= 30s` — completion only.
/// - `30s < duration <= 60s` — pre1 at T−5s, then completion.
/// - `duration > 60s` — pre1 at T−10s, pre2 at T−5s, then completion.
///
/// Alerts are returned in fire order. The function is intentionally clock-free
/// (it takes the end instant as input) so it is deterministic and shared by the
/// background notification scheduler and the foreground tick path.
public enum TimerAlertSchedule {
    /// Durations at or below this (seconds) get the completion alert only.
    public static let preAlertMinimumDuration: TimeInterval = 30
    /// Durations above this (seconds) add the second pre-alert (pre2).
    public static let secondPreAlertMinimumDuration: TimeInterval = 60

    private static let pre1ShortLeadSeconds = 5
    private static let pre1LongLeadSeconds = 10
    private static let pre2LeadSeconds = 5

    public static func alerts(duration: TimeInterval, endDate: Date) -> [TimerStagedAlert] {
        var alerts: [TimerStagedAlert] = []

        if duration > secondPreAlertMinimumDuration {
            alerts.append(
                TimerStagedAlert(
                    stage: .pre1,
                    fireDate: endDate.addingTimeInterval(-TimeInterval(pre1LongLeadSeconds)),
                    secondsBeforeCompletion: pre1LongLeadSeconds
                )
            )
            alerts.append(
                TimerStagedAlert(
                    stage: .pre2,
                    fireDate: endDate.addingTimeInterval(-TimeInterval(pre2LeadSeconds)),
                    secondsBeforeCompletion: pre2LeadSeconds
                )
            )
        } else if duration > preAlertMinimumDuration {
            alerts.append(
                TimerStagedAlert(
                    stage: .pre1,
                    fireDate: endDate.addingTimeInterval(-TimeInterval(pre1ShortLeadSeconds)),
                    secondsBeforeCompletion: pre1ShortLeadSeconds
                )
            )
        }

        alerts.append(
            TimerStagedAlert(stage: .completion, fireDate: endDate, secondsBeforeCompletion: 0)
        )
        return alerts
    }
}
