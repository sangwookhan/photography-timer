// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Value type describing a timer transition from running to completed.
/// Platform-neutral request/result type emitted by the timer runtime and
/// consumed by the app's OS-side completion handling.
public struct TimerCompletionEvent: Equatable {
    public let timerID: UUID
    public let completionDate: Date

    public init(timerID: UUID, completionDate: Date) {
        self.timerID = timerID
        self.completionDate = completionDate
    }
}
