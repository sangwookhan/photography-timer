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
    /// Play the full completion feedback (haptic + audible alarm) for the timer
    /// that completed. The id lets the audible alarm publish which timer is
    /// sounding so the UI can offer a stop-alarm affordance (PTIMER-73).
    @MainActor
    func playCompletionFeedback(for timerID: UUID)

    /// Play the lighter, haptic-first pre-alert feedback (PTIMER-73). A default
    /// no-op is provided so completion-only conformers keep compiling unchanged.
    @MainActor
    func playPreAlertFeedback()
}

public extension TimerCompletionFeedbackPlaying {
    @MainActor
    func playPreAlertFeedback() {}
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
