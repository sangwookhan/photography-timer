// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Platform-neutral abstractions for the OS-side effects a timer completion
/// triggers. The app target provides the concrete UIKit / AudioToolbox /
/// UserNotifications implementations; the timer runtime depends only on these
/// protocols so it stays free of OS I/O.

public protocol TimerCompletionAlerting {
    @MainActor
    func handleTimerCompletion(_ event: TimerCompletionEvent)

    /// Handle a foreground pre-alert crossing (PTIMER-73). A default no-op is
    /// provided so completion-only conformers keep compiling unchanged.
    @MainActor
    func handlePreAlert(_ event: TimerPreAlertEvent)
}

public extension TimerCompletionAlerting {
    @MainActor
    func handlePreAlert(_ event: TimerPreAlertEvent) {}
}

public struct NoOpTimerCompletionAlertService: TimerCompletionAlerting {
    public init() {}
    public func handleTimerCompletion(_ event: TimerCompletionEvent) {}
}

public protocol TimerCompletionFeedbackPlaying {
    @MainActor
    func playCompletionFeedback()

    /// Play the lighter, haptic-first pre-alert feedback (PTIMER-73). A default
    /// no-op is provided so completion-only conformers keep compiling unchanged.
    @MainActor
    func playPreAlertFeedback()

    /// Play the audible completion alarm *without* the haptic — used when a
    /// timer completes while the app is in the background (kept alive by the
    /// background-audio session), where a haptic would not be perceived
    /// (PTIMER-73). Defaults to the full completion feedback so existing
    /// conformers keep their behavior.
    @MainActor
    func playCompletionAlarm()
}

public extension TimerCompletionFeedbackPlaying {
    @MainActor
    func playPreAlertFeedback() {}

    @MainActor
    func playCompletionAlarm() { playCompletionFeedback() }
}

public protocol TimerCompletionNotificationScheduling {
    @MainActor
    func requestAuthorizationIfNeeded()

    @MainActor
    func scheduleCompletionNotification(for timer: TimerState)

    @MainActor
    func cancelCompletionNotification(forTimerID timerID: UUID)
}

public struct NoOpTimerCompletionScheduler: TimerCompletionNotificationScheduling {
    public init() {}
    public func requestAuthorizationIfNeeded() {}
    public func scheduleCompletionNotification(for timer: TimerState) {}
    public func cancelCompletionNotification(forTimerID timerID: UUID) {}
}
