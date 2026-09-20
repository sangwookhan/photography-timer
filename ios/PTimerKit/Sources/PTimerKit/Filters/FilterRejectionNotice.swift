// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Transient, view-facing record of a refused wheel change (Filter
/// Set contract FILTER-STACK-004) or a refused Plus addition
/// (FILTER-PLUS-003/005). `sequence` increases per notice so two
/// identical rejections in a row still read as two events.
public struct FilterRejectionNotice: Equatable, Sendable {
    public let sequence: Int
    /// The refused wheel change; `nil` for a refused addition.
    public let rejection: FilterStackRejection?
    /// Why the Plus addition was refused; `nil` for a wheel change.
    public let addUnavailability: FilterAddUnavailability?

    public init(sequence: Int, rejection: FilterStackRejection) {
        self.sequence = sequence
        self.rejection = rejection
        self.addUnavailability = nil
    }

    public init(sequence: Int, addUnavailability: FilterAddUnavailability) {
        self.sequence = sequence
        self.rejection = nil
        self.addUnavailability = addUnavailability
    }

    /// The reason as the status region shows it.
    public var text: String {
        if let rejection {
            return FilterWheelPresenter.rejectionText(for: rejection)
        }
        if let addUnavailability {
            return FilterWheelPresenter.addUnavailabilityText(for: addUnavailability)
        }
        return ""
    }
}
