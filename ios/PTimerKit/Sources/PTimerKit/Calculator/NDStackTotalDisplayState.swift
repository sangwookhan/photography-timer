// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Transient Total-overlay content for the ND filter wheel stack
/// (PTIMER-199 §4.6). Computed, not stored: the view model derives it
/// from the model's EFFECTIVE ND value (live wheel + committed
/// others), always expressed in stops — sums like 6.6 + 6.6 = 13.2
/// have no standard OD / ND-factor label. Visibility TIMING (fade-in,
/// idle fade-out, longer display after an add) is view-layer
/// ephemeral state; this value only carries the content and the
/// visibility precondition.
public struct NDStackTotalDisplayState: Equatable, Sendable {
    /// Stops-notation value text for the effective sum ("19", "13.2").
    public let totalStopsText: String

    /// True when the sum sits at the 30-stop structural maximum; the
    /// overlay appends the Maximum marker.
    public let isAtMaximum: Bool

    /// Number of wheels in the stack.
    public let wheelCount: Int

    /// The overlay only ever shows for an actual stack — with one
    /// wheel the total equals the wheel value and stays hidden.
    public var isVisibleCandidate: Bool {
        wheelCount >= 2
    }

    public init(totalStopsText: String, isAtMaximum: Bool, wheelCount: Int) {
        self.totalStopsText = totalStopsText
        self.isAtMaximum = isAtMaximum
        self.wheelCount = wheelCount
    }

    /// Builds the display state from the effective step and wheel
    /// count. The total is formatted as PLAIN stops here rather than
    /// through `NDNotationFormatter`: the stops-mode formatter's
    /// fractional branch renders third-stop mixed fractions and would
    /// misread arbitrary preset sums (6.6 + 6.6 = 13.2 became
    /// "13 1/3"). Sums of ladder values are always whole or
    /// one-decimal, so whole → integer, otherwise one decimal.
    public init(effectiveStep: NDStep, wheelCount: Int) {
        let totalStopsText: String
        if let whole = effectiveStep.wholeStops {
            totalStopsText = "\(whole)"
        } else {
            totalStopsText = String(format: "%.1f", effectiveStep.stops)
        }

        self.init(
            totalStopsText: totalStopsText,
            isAtMaximum: abs(
                effectiveStep.stops - Double(ExposureScale.maximumWholeNDStops)
            ) <= ExposureCalculator.stabilityEpsilon,
            wheelCount: wheelCount
        )
    }
}
