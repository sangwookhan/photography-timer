// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Transient, view-facing record of a refused wheel change (Filter
/// Set contract FILTER-STACK-004). `sequence` increases per notice so
/// two identical rejections in a row still read as two events.
public struct FilterRejectionNotice: Equatable, Sendable {
    public let sequence: Int
    public let rejection: FilterStackRejection

    public init(sequence: Int, rejection: FilterStackRejection) {
        self.sequence = sequence
        self.rejection = rejection
    }

    public var text: String {
        FilterWheelPresenter.rejectionText(for: rejection)
    }
}
