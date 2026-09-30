// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// One mounted auxiliary filter as the Main summary shows it
/// (FILTER-AUX-002): its identity, its current contribution, and the
/// detail that keeps a registered value or mode from being mistaken
/// for the contribution. Pure value; the view owns fonts and colors.
public struct AuxiliaryFilterSummaryItemDisplay: Equatable, Sendable {
    public let itemID: FilterItemID
    /// The item's registered name (`Soft GND 3`, `CPL`, `Red 25A`).
    public let name: String
    /// Behavior type as text (`CPL`, `GND`, `Color`, `Effect`).
    public let kindLabel: String
    /// Current contribution in canonical stops, plain decimal (`1.5`,
    /// `0`).
    public let contributionText: String
    /// The line under the name: a GND's mode and registered density
    /// (`Record only · 3 stops`), a Color filter's optical color name,
    /// or `nil` when the contribution alone describes the item.
    public let detailText: String?
    /// The same detail as separate parts (`Record only`, `3 stops`), so
    /// a narrow column can break between parts instead of inside one.
    /// Empty when there is no detail.
    public let detailSegments: [String]
    /// Swatch for a Color filter's optical color; `nil` otherwise.
    public let opticalColor: FilterOpticalColor?
    /// The owning set's user-selected color, shown as the source cue.
    public let sourceColor: FilterSetColor
    /// Complete spoken description: name, type or mode, contribution.
    public let accessibilityText: String

    public init(itemID: FilterItemID, name: String, kindLabel: String, contributionText: String, detailSegments: [String], opticalColor: FilterOpticalColor?, sourceColor: FilterSetColor, accessibilityText: String) {
        self.itemID = itemID
        self.name = name
        self.kindLabel = kindLabel
        self.contributionText = contributionText
        self.detailSegments = detailSegments
        self.detailText = detailSegments.isEmpty ? nil : detailSegments.joined(separator: " · ")
        self.opticalColor = opticalColor
        self.sourceColor = sourceColor
        self.accessibilityText = accessibilityText
    }
}

/// The Main summary space (FILTER-AUX-001/002): every mounted
/// auxiliary item with its identity and contribution, readable without
/// a tap. `nil` while nothing is mounted, so the space is hidden.
public struct AuxiliaryFilterSummaryDisplayState: Equatable, Sendable {
    public let items: [AuxiliaryFilterSummaryItemDisplay]
    /// Spoken label of the summary button: the title followed by every
    /// item's description (FILTER-A11Y-001).
    public let accessibilityLabel: String

    public init(items: [AuxiliaryFilterSummaryItemDisplay], accessibilityLabel: String) {
        self.items = items
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Pure-value transform from the resolved mounted auxiliary filters
/// into the Main summary. Contributions stay in stops regardless of
/// the ND notation (ND-004): they are labeled contributions, not
/// notation displays.
public enum AuxiliaryFilterSummaryPresenter {
    /// `Auxiliary filters` — the summary's title and the popup tab.
    public static var title: String {
        String(localized: "Auxiliary filters")
    }

    public static func displayState(for rows: [ResolvedAuxiliaryFilter]) -> AuxiliaryFilterSummaryDisplayState? {
        guard !rows.isEmpty else {
            return nil
        }
        let items = rows.map(itemDisplay(for:))
        let spoken = ([title] + items.map(\.accessibilityText)).joined(separator: ", ")
        return AuxiliaryFilterSummaryDisplayState(items: items, accessibilityLabel: spoken)
    }

    public static func itemDisplay(for row: ResolvedAuxiliaryFilter) -> AuxiliaryFilterSummaryItemDisplay {
        let contribution = FilterWheelPresenter.decimalStopsValue(row.contributionStops)
        let contributionSpoken = FilterWheelPresenter.stopsText(row.contributionStops)
        let kind = row.item.behavior.kind
        let detail: [String]
        let semanticType: String
        switch row.mount.choice {
        case .cplLoss:
            detail = []
            semanticType = FilterWheelPresenter.kindName(.cpl)
        case .gnd(let mode):
            // Record only: the registered density stays visible beside
            // the mode so a 0 is never read as a 0-stop filter. Apply
            // full value: the contribution already is the registered
            // density, so the mode alone distinguishes it.
            switch mode {
            case .recordOnly:
                let registered = row.item.behavior.registeredValue.map(FilterWheelPresenter.registeredValueText)
                    ?? FilterWheelPresenter.stopsText(row.registeredStops)
                detail = [FilterWheelPresenter.gndModeName(mode), registered]
            case .applyFullValue:
                detail = [FilterWheelPresenter.gndModeName(mode)]
            }
            semanticType = "\(FilterWheelPresenter.kindName(.gnd)) \(FilterWheelPresenter.gndModeName(mode))"
        case .registeredLoss:
            if let color = row.item.behavior.opticalColor {
                detail = [FilterWheelPresenter.opticalColorName(color)]
                semanticType = "\(FilterWheelPresenter.kindName(.color)) \(FilterWheelPresenter.opticalColorName(color))"
            } else {
                detail = []
                semanticType = FilterWheelPresenter.kindName(kind)
            }
        }
        return AuxiliaryFilterSummaryItemDisplay(
            itemID: row.item.id,
            name: row.item.name,
            kindLabel: FilterWheelPresenter.kindName(kind),
            contributionText: contribution,
            detailSegments: detail,
            opticalColor: row.item.behavior.opticalColor,
            sourceColor: row.filterSetColor,
            accessibilityText: "\(row.item.name), \(semanticType), \(contributionSpoken)"
        )
    }
}

/// What the Plus wheel can settle on (FILTER-PLUS-001): an ND Filter
/// Source that adds a wheel, or the Auxiliary filters action that opens
/// the shooting popup without adding anything.
public enum FilterPlusChoice: Hashable, Sendable {
    case source(FilterSource)
    case auxiliaryFilters

    public var source: FilterSource? {
        if case .source(let source) = self {
            return source
        }
        return nil
    }

    /// Standard, the candidate ND sources, then the auxiliary action
    /// last so a downward browse from Standard reaches it directly.
    public static func choices(for sources: [FilterSource]) -> [FilterPlusChoice] {
        sources.map(FilterPlusChoice.source) + [.auxiliaryFilters]
    }
}
