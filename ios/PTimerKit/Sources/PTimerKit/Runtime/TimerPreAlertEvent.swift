// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Value type describing a staged pre-alert crossing (pre1/pre2) for a running
/// timer. Platform-neutral request/result type emitted by the timer runtime on
/// foreground ticks and consumed by the app's OS-side feedback handling.
///
/// Only pre-alerts intended to be perceivable in the foreground are emitted as
/// events; the background delivery of every stage is handled separately by the
/// notification scheduler.
public struct TimerPreAlertEvent: Equatable {
    public let timerID: UUID
    public let stage: TimerAlertStage
    public let secondsBeforeCompletion: Int

    public init(timerID: UUID, stage: TimerAlertStage, secondsBeforeCompletion: Int) {
        self.timerID = timerID
        self.stage = stage
        self.secondsBeforeCompletion = secondsBeforeCompletion
    }
}
