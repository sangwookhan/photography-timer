// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// The single transient status region of the mixed-stack interaction
/// (FILTER-STACK-008): one primary line (expanded item or source, or a
/// rejection reason) and one secondary line (the live contribution and
/// total). States replace or combine within this one value — there is
/// never a second bubble.
public struct FilterStatusRegionContent: Equatable, Sendable {
    public let primaryText: String?
    public let secondaryText: String?
    /// True for a rejection reason; the view tints the primary line.
    public let isWarning: Bool
    /// True while an interaction is in progress (a wheel or Plus is
    /// moving, or a rejection is being reported): the content stays
    /// until it changes. False for the idle total, which fades after a
    /// short interval while the region keeps its geometry.
    public let isHeld: Bool

    public init(primaryText: String?, secondaryText: String?, isWarning: Bool = false, isHeld: Bool) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.isWarning = isWarning
        self.isHeld = isHeld
    }

    public var isEmpty: Bool {
        primaryText == nil && secondaryText == nil
    }
}

/// What a moving wheel contributes to the region: its expanded label
/// and its live contribution in canonical stops.
public struct MovingWheelStatus: Equatable, Sendable {
    public let expandedLabel: String
    public let contributionStops: Double

    public init(expandedLabel: String, contributionStops: Double) {
        self.expandedLabel = expandedLabel
        self.contributionStops = contributionStops
    }
}

/// Pure composition of the region content from the interaction facts.
/// Priority: a rejection replaces movement (reason + unchanged total);
/// Plus browsing shows the candidate source; a moving wheel shows its
/// expanded information plus `+contribution · Total`; otherwise the
/// idle total when two or more wheels are stacked (ND-INTERACT-020).
public enum FilterStatusRegionPresenter {
    public static func content(
        moving: MovingWheelStatus?,
        browsingSourceName: String?,
        rejection: FilterRejectionNotice?,
        total: NDStackTotalDisplayState
    ) -> FilterStatusRegionContent? {
        let totalText = totalText(total)
        if let rejection {
            return FilterStatusRegionContent(
                primaryText: rejection.text,
                secondaryText: totalText,
                isWarning: true,
                isHeld: true
            )
        }
        if let browsingSourceName {
            return FilterStatusRegionContent(primaryText: browsingSourceName, secondaryText: totalText, isHeld: true)
        }
        if let moving {
            let contribution = FilterWheelPresenter.stopsText(moving.contributionStops)
            return FilterStatusRegionContent(
                primaryText: moving.expandedLabel,
                secondaryText: String(localized: "+\(contribution) · \(totalText)"),
                isHeld: true
            )
        }
        guard total.isVisibleCandidate else {
            return nil
        }
        return FilterStatusRegionContent(primaryText: nil, secondaryText: totalText, isHeld: false)
    }

    public static func totalText(_ total: NDStackTotalDisplayState) -> String {
        if total.isAtMaximum {
            return String(localized: "Total \(total.totalStopsText) stops · Maximum")
        }
        return String(localized: "Total \(total.totalStopsText) stops")
    }
}

/// Owns the region's visible content and its fade timing so exactly
/// one content is ever displayed and a stale hide task can never
/// remove newer content. Held content stays until replaced or
/// cleared; unheld content (the idle total) fades after `fadeDelay`.
@MainActor
public final class TransientStatusRegionController: ObservableObject {
    @Published public private(set) var visibleContent: FilterStatusRegionContent?
    /// Fixed product interval for the idle total; a test seam only.
    public var fadeDelay: TimeInterval = 1.5
    private var fadeTask: Task<Void, Never>?
    private var generation = 0

    public init() {}

    /// Applies the latest composed content. Any pending fade belongs
    /// to a previous state and is cancelled first.
    public func apply(_ content: FilterStatusRegionContent?) {
        fadeTask?.cancel()
        fadeTask = nil
        generation += 1
        guard let content else {
            visibleContent = nil
            return
        }
        visibleContent = content
        guard !content.isHeld else {
            return
        }
        let token = generation
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.fadeDelay ?? 0) * 1_000_000_000))
            guard let self, !Task.isCancelled, self.generation == token else {
                return
            }
            self.visibleContent = nil
        }
    }

    /// Test seam: fires the pending fade as if the interval elapsed,
    /// with the same token check the timer applies.
    func fireFadeIfPending(token: Int? = nil) {
        guard fadeTask != nil else { return }
        if let token, token != generation { return }
        fadeTask?.cancel()
        fadeTask = nil
        visibleContent = nil
    }

    var currentGeneration: Int { generation }
}
