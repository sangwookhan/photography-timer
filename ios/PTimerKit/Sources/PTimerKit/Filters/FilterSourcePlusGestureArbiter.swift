// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Decides what one touch on the Plus wheel means (FILTER-PLUS-001,
/// FILTER-PLUS-003 / FR-1.13): a tap adds the displayed source, and
/// vertical travel browses sources and, on release, adds exactly one
/// wheel from the final snapped source when it differs from the
/// starting source. A touch that leaves the stationary tolerance
/// without reaching the drag threshold is neither. Intermediate
/// candidates and a return to the starting source add nothing.
///
/// Pure value: the view feeds it the touch's translation and the
/// release, and renders what it reports.
public struct FilterSourcePlusGestureArbiter: Equatable, Sendable {
    /// How the touch is currently classified.
    public enum Phase: Equatable, Sendable {
        /// Down, within the stationary tolerance.
        case pressing
        /// Moved past the stationary tolerance but not yet to the drag
        /// threshold: no longer a tap, not yet a browse. Releasing
        /// here does nothing.
        case unsettled
        /// Vertical drag won: browsing sources.
        case browsing
    }

    /// What the release of the touch means.
    public enum ReleaseOutcome: Equatable, Sendable {
        /// A tap: add one wheel for the displayed source.
        case add
        /// The browse settled on a different source: add one wheel
        /// for it.
        case addBrowsed(index: Int)
        /// Neither a tap nor a changed browse: nothing happens (a
        /// browse that returned to its starting source ends here).
        case none
    }

    /// Movement a tap tolerates.
    public static let stationaryTolerance: CGFloat = 4
    /// Movement at which the touch becomes a browse (drag activation).
    public static let browseThreshold: CGFloat = 8
    /// Vertical travel per source step while browsing.
    public static let stepDistance: CGFloat = 26

    public private(set) var phase: Phase = .pressing
    public private(set) var maxTravel: CGFloat = 0
    /// The browsed source index while `phase == .browsing`.
    public private(set) var candidateIndex: Int?
    private let settledIndex: Int
    private let sourceCount: Int

    public init(settledIndex: Int, sourceCount: Int) {
        self.settledIndex = settledIndex
        self.sourceCount = sourceCount
    }

    /// The touch moved. Returns true when the browsed candidate changed
    /// (the view reports it and plays the selection haptic).
    @discardableResult
    public mutating func moved(translation: CGSize) -> Bool {
        maxTravel = max(maxTravel, abs(translation.height), abs(translation.width))
        switch phase {
        case .pressing, .unsettled:
            if maxTravel >= Self.browseThreshold {
                phase = .browsing
            } else if maxTravel > Self.stationaryTolerance {
                phase = .unsettled
                return false
            } else {
                return false
            }
        case .browsing:
            break
        }
        // Drag up reveals the next source, drag down the previous one,
        // mirroring a wheel's row travel.
        let steps = Int((-translation.height / Self.stepDistance).rounded())
        let next = min(max(settledIndex + steps, 0), max(sourceCount - 1, 0))
        guard next != candidateIndex else { return false }
        candidateIndex = next
        return true
    }

    /// The touch ended.
    public func released() -> ReleaseOutcome {
        switch phase {
        case .browsing:
            guard let candidateIndex, candidateIndex != settledIndex else { return .none }
            return .addBrowsed(index: candidateIndex)
        case .pressing:
            return .add
        case .unsettled:
            return .none
        }
    }
}
