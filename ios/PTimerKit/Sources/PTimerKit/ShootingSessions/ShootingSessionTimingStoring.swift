// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

public protocol ShootingSessionTimingStoring {
    func loadShortenedIntervals() -> Bool
    func saveShortenedIntervals(_ enabled: Bool)
}

public struct NoOpShootingSessionTimingStore: ShootingSessionTimingStoring {
    public init() {}
    public func loadShortenedIntervals() -> Bool { false }
    public func saveShortenedIntervals(_ enabled: Bool) {}
}
