// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct ShootingSessionPolicy: Codable, Equatable {
    public let connectionWindow: TimeInterval
    public let admissionSpan: TimeInterval

    public static let normal = Self(connectionWindow: 3_600, admissionSpan: 28_800)
    public static let shortened = Self(connectionWindow: 60, admissionSpan: 480)

    public init(connectionWindow: TimeInterval, admissionSpan: TimeInterval) {
        self.connectionWindow = connectionWindow
        self.admissionSpan = admissionSpan
    }

    public func connects(start: Date, firstStart: Date, latestStart: Date) -> Bool {
        let gap = start.timeIntervalSince(latestStart)
        let span = start.timeIntervalSince(firstStart)
        return gap >= 0 && gap <= connectionWindow && span >= 0 && span < admissionSpan
    }
}
