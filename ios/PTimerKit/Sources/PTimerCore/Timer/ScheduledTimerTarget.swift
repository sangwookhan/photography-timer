// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure value type shared by the app's Live Activity, the widget extension,
/// and the lock-screen coordinator. Lives in PTimerCore so the widget can use
/// it without depending on the full PTimerKit layer.
public struct ScheduledTimerTarget: Codable, Equatable, Hashable {
    public let timerID: UUID
    public let timerName: String
    public let endDate: Date

    public init(timerID: UUID, timerName: String, endDate: Date) {
        self.timerID = timerID
        self.timerName = timerName
        self.endDate = endDate
    }
}
