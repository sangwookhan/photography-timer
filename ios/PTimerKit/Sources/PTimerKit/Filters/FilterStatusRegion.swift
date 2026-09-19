// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// One source of the idle summary (FILTER-STACK-008): its name, how
/// many actual wheels it owns, and — for a Filter Set — the
/// user-selected source color shown as a cue beside the name.
/// Standard carries no color and is identified by text alone.
public struct FilterStatusSourceSummaryItem: Equatable, Sendable {
    public let source: FilterSource
    public let name: String
    public let count: Int
    public let color: FilterSetColor?

    public init(source: FilterSource, name: String, count: Int, color: FilterSetColor?) {
        self.source = source
        self.name = name
        self.count = count
        self.color = color
    }

    /// `Lee holder ×2` / `Standard`.
    public var text: String {
        count > 1 ? String(localized: "\(name) ×\(count)") : name
    }
}

/// The single stable status region of the mixed-stack interaction
/// (FILTER-STACK-007/008): exactly one visual row in every state. The
/// leading text is the idle source summary, the detailed item or
/// source, or a rejection reason; the trailing text is the localized
/// total, which always stays complete while the leading text yields
/// space and truncates at its tail. States replace or combine within
/// this one value — there is never a second bubble or a second line.
public struct FilterStatusRegionContent: Equatable, Sendable {
    public let primaryText: String?
    public let secondaryText: String?
    /// Structured idle summary (each source once, settled order, with
    /// its source-color cue); `primaryText` carries the same complete
    /// text for accessibility. `nil` for every other state.
    public let idleSourceSummary: [FilterStatusSourceSummaryItem]?
    /// True for a rejection reason; the view tints the leading text.
    public let isWarning: Bool
    /// True while the content stays until it changes: an interaction
    /// in progress (a wheel or Plus is moving, or a rejection is being
    /// reported) or the persistent idle source summary. False for the
    /// Standard-only idle total, which fades after a short interval
    /// while the region keeps its geometry.
    public let isHeld: Bool
    /// True for the persistent idle source summary of a stack with a
    /// Filter Set wheel: rendered at accessible secondary emphasis so
    /// moving and rejection content reads as the active state.
    public let isSecondaryEmphasis: Bool

    public init(primaryText: String?, secondaryText: String?, isWarning: Bool = false, isHeld: Bool, isSecondaryEmphasis: Bool = false, idleSourceSummary: [FilterStatusSourceSummaryItem]? = nil) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.isWarning = isWarning
        self.isHeld = isHeld
        self.isSecondaryEmphasis = isSecondaryEmphasis
        self.idleSourceSummary = idleSourceSummary
    }

    /// The persistent idle state: held, secondary, never a warning.
    public var isPersistentIdle: Bool {
        isHeld && isSecondaryEmphasis
    }

    public var isEmpty: Bool {
        primaryText == nil && secondaryText == nil
    }

    /// The complete content for accessibility: the full leading text
    /// (source summary, item detail, or rejection reason) and the
    /// total, regardless of how much of the leading text the row could
    /// show.
    public var accessibilityText: String {
        [primaryText, secondaryText].compactMap { $0 }.joined(separator: " · ")
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
/// Priority: a rejection replaces movement (reason, unchanged total);
/// Plus browsing shows the candidate source; a moving wheel shows its
/// expanded information (item, registered value, mode, contribution)
/// with the live total; otherwise the
/// persistent source summary with the total for a stack holding any
/// Filter Set wheel (FILTER-STACK-008), or the Standard-only idle
/// total when two or more wheels are stacked (ND-INTERACT-020).
public enum FilterStatusRegionPresenter {
    public static func content(
        moving: MovingWheelStatus?,
        browsingSourceName: String?,
        rejection: FilterRejectionNotice?,
        total: NDStackTotalDisplayState,
        idleSourceSummary: [FilterStatusSourceSummaryItem]? = nil
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
            return FilterStatusRegionContent(primaryText: moving.expandedLabel, secondaryText: totalText, isHeld: true)
        }
        if let idleSourceSummary, !idleSourceSummary.isEmpty {
            return FilterStatusRegionContent(
                primaryText: summaryText(idleSourceSummary),
                secondaryText: totalText,
                isHeld: true,
                isSecondaryEmphasis: true,
                idleSourceSummary: idleSourceSummary
            )
        }
        guard total.isVisibleCandidate else {
            return nil
        }
        return FilterStatusRegionContent(primaryText: nil, secondaryText: totalText, isHeld: false)
    }

    /// Idle source identity for a stack containing any Filter Set
    /// wheel (FILTER-STACK-008): each source once, in the wheels'
    /// settled left-to-right order, with its wheel count and — for a
    /// Filter Set — its user-selected source color; Standard carries
    /// no color. `nil` for a Standard-only stack, which keeps the
    /// existing ND status behavior. Sources are identified by text,
    /// never by color alone.
    public static func sourceSummary(
        wheels: [FilterWheel],
        sourceName: (FilterSource) -> String,
        sourceColor: (FilterSource) -> FilterSetColor?
    ) -> [FilterStatusSourceSummaryItem]? {
        guard wheels.contains(where: { $0.source != .standard }) else {
            return nil
        }
        var order: [FilterSource] = []
        var counts: [FilterSource: Int] = [:]
        for wheel in wheels {
            if counts[wheel.source] == nil {
                order.append(wheel.source)
            }
            counts[wheel.source, default: 0] += 1
        }
        return order.map { source in
            FilterStatusSourceSummaryItem(
                source: source,
                name: sourceName(source),
                count: counts[source] ?? 1,
                color: source == .standard ? nil : sourceColor(source)
            )
        }
    }

    /// `NiSi kit · Lee holder ×2 · Standard` — the summary as one string
    /// for accessibility.
    public static func summaryText(_ items: [FilterStatusSourceSummaryItem]) -> String {
        items.map(\.text).joined(separator: " · ")
    }

    /// Text-only convenience over `sourceSummary`.
    public static func sourceSummaryText(
        wheels: [FilterWheel],
        sourceName: (FilterSource) -> String
    ) -> String? {
        sourceSummary(wheels: wheels, sourceName: sourceName, sourceColor: { _ in nil }).map(summaryText)
    }

    public static func totalText(_ total: NDStackTotalDisplayState) -> String {
        if total.isAtMaximum {
            return String(localized: "Total \(total.totalStopsText) stops · Maximum")
        }
        return String(localized: "Total \(total.totalStopsText) stops")
    }
}

/// Owns the region's visible content and its timing so exactly one
/// content is ever displayed and a stale timer can never replace
/// newer content. Held content stays until replaced or cleared; the
/// Standard-only idle total fades after `fadeDelay`; and when a
/// movement or Plus browse settles into the persistent idle summary,
/// the settled expanded information lingers for the same interval
/// before the summary returns (FILTER-STACK-008). A rejection has its
/// own notice interval, so the summary returns as soon as it clears.
@MainActor
public final class TransientStatusRegionController: ObservableObject {
    @Published public private(set) var visibleContent: FilterStatusRegionContent?
    /// Fixed product interval for the idle total and the post-settle
    /// linger; a test seam only.
    public var fadeDelay: TimeInterval = 1.5
    private var timerTask: Task<Void, Never>?
    private var pendingContent: FilterStatusRegionContent?
    private var generation = 0

    public init() {}

    /// Applies the latest composed content. Any pending timer belongs
    /// to a previous state and is cancelled first.
    public func apply(_ content: FilterStatusRegionContent?) {
        timerTask?.cancel()
        timerTask = nil
        pendingContent = nil
        generation += 1
        guard let content else {
            visibleContent = nil
            return
        }
        if content.isPersistentIdle, let current = visibleContent, current.isHeld, !current.isWarning, !current.isPersistentIdle {
            // Settlement after movement or browsing: keep the expanded
            // information for the transient interval, then return to
            // the source summary.
            pendingContent = content
            schedule { $0.visibleContent = content }
            return
        }
        visibleContent = content
        guard !content.isHeld else {
            return
        }
        schedule { $0.visibleContent = nil }
    }

    private func schedule(_ body: @escaping @MainActor (TransientStatusRegionController) -> Void) {
        let token = generation
        timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.fadeDelay ?? 0) * 1_000_000_000))
            guard let self, !Task.isCancelled, self.generation == token else {
                return
            }
            self.pendingContent = nil
            body(self)
        }
    }

    /// Test seam: fires the pending timer as if the interval elapsed,
    /// with the same token check the timer applies.
    func fireFadeIfPending(token: Int? = nil) {
        guard timerTask != nil else { return }
        if let token, token != generation { return }
        timerTask?.cancel()
        timerTask = nil
        visibleContent = pendingContent
        pendingContent = nil
    }

    var currentGeneration: Int { generation }
}
