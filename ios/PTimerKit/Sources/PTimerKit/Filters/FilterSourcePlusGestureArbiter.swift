// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Decides what one touch on the Plus wheel means (FILTER-PLUS-001,
/// FILTER-PLUS-003 / FR-1.13): a tap adds the displayed source, a
/// stationary long press opens Filter Set management, and vertical
/// travel browses sources and, on release, adds exactly one wheel from
/// the final snapped source when it differs from the starting source.
/// The three never compete: the long press may complete only while the
/// touch has stayed within the stationary tolerance for its whole
/// duration; crossing the drag activation threshold cancels a pending
/// long press at once and hands the touch to browsing, after which
/// management can never open on release, however long the touch then
/// lasts or pauses. Intermediate candidates and a return to the
/// starting source add nothing.
///
/// Pure value: the view feeds it the touch's translation, the long
/// press deadline, and the release, and renders what it reports.
public struct FilterSourcePlusGestureArbiter: Equatable, Sendable {
    /// How the touch is currently classified.
    public enum Phase: Equatable, Sendable {
        /// Down, within the stationary tolerance, before the deadline.
        case pressing
        /// Moved past the stationary tolerance but not yet to the drag
        /// threshold: the long press is cancelled, browsing has not
        /// started. Releasing here does nothing.
        case unsettled
        /// Vertical drag won: browsing sources.
        case browsing
        /// The stationary long press completed: management opened.
        case managing
    }

    /// What the release of the touch means.
    public enum ReleaseOutcome: Equatable, Sendable {
        /// A tap: add one wheel for the displayed source.
        case add
        /// The browse settled on a different source: add one wheel
        /// for it.
        case addBrowsed(index: Int)
        /// Management already opened during the press; nothing more.
        case managed
        /// Neither a tap nor a changed browse: nothing happens (a
        /// browse that returned to its starting source ends here).
        case none
    }

    /// Hold duration for the management long press.
    public static let longPressDuration: TimeInterval = 0.5
    /// Movement the long press tolerates; beyond it the press can no
    /// longer complete as a long press.
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
        case .managing:
            return false
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

    /// The long press deadline elapsed. Returns true when management
    /// should open: only while the touch is still a stationary press.
    public mutating func deadlineElapsed() -> Bool {
        guard phase == .pressing else { return false }
        phase = .managing
        return true
    }

    /// The touch ended.
    public func released() -> ReleaseOutcome {
        switch phase {
        case .managing:
            return .managed
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
