// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

public enum TimerCancellationReason: String, Codable, Equatable {
    case pauseExpired
    case newTimerStarted
}
