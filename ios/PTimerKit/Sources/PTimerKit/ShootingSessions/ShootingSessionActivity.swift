// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Retained with Timer metadata, independently of assignment confirmation.
public struct ShootingSessionActivity: Codable, Equatable {
    public let startedAt: Date
    public let policy: ShootingSessionPolicy

    public init(startedAt: Date, policy: ShootingSessionPolicy) {
        self.startedAt = startedAt
        self.policy = policy
    }
}
