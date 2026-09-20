// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One actual automatic removal of empty wheels (FILTER-STACK-006):
/// published by the calculator facade only when cleanup removed at
/// least one Standard 0 or Filter Set Empty wheel — never when it was
/// scheduled, deferred, or found nothing to remove. `sequence`
/// increases per removal so two equal removals in a row still read as
/// two events; the platform layer announces each exactly once while a
/// screen reader is active.
public struct EmptyFilterWheelRemoval: Equatable, Sendable {
    public let sequence: Int
    public let removedCount: Int

    public init(sequence: Int, removedCount: Int) {
        self.sequence = sequence
        self.removedCount = removedCount
    }
}
