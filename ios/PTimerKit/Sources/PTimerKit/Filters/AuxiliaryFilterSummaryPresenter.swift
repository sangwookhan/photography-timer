// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// One selected filter in the Selected filters panel of Shooting
/// Filters (FILTER-FLOW-003): the whole name, the type apart from it,
/// and the current contribution or GND mode. Pure value.
public struct SelectedFilterRowDisplayState: Equatable, Sendable, Identifiable {
    public let itemID: FilterItemID
    /// The item's registered name, never shortened.
    public let name: String
    /// Behavior type as text (`Color`, `Effect`, `CPL`, `GND`).
    public let kindLabel: String
    /// Swatch for a Color filter's optical color; `nil` otherwise.
    public let opticalColor: FilterSetColor?
    /// `1.5 stops`, or a GND's `Record only · 0 stops`.
    public let valueText: String

    public var id: FilterItemID { itemID }
}

/// One mounted auxiliary filter as the Main summary shows it
/// (FILTER-AUX-002): one compact row with a short identifier and the
/// current contribution. Modes, registered densities, and other
/// metadata stay in the shooting popup. Pure value; the view owns
/// fonts and colors.
public struct AuxiliaryFilterSummaryItemDisplay: Equatable, Sendable {
    public let itemID: FilterItemID
    /// The item's registered name (`Soft GND 3`, `CPL`, `Red 25A`).
    public let name: String
    /// Behavior type as text (`CPL`, `GND`, `Color`, `Effect`).
    public let kindLabel: String
    /// Current contribution in canonical stops, plain decimal (`1.5`,
    /// `0`).
    public let contributionText: String
    /// The row's identifier, longest first: the view shows the first
    /// one that fits the column, never a truncated one. See
    /// `AuxiliaryFilterSummaryPresenter.compactLabels`.
    public let compactLabels: [String]
    /// Swatch for a Color filter's optical color; `nil` otherwise.
    public let opticalColor: FilterSetColor?
    /// The owning set's user-selected color, shown as the source cue.
    public let sourceColor: FilterSetColor
    /// Complete spoken description: name, type or mode, contribution.
    public let accessibilityText: String

    public init(itemID: FilterItemID, name: String, kindLabel: String, contributionText: String, compactLabels: [String], opticalColor: FilterSetColor?, sourceColor: FilterSetColor, accessibilityText: String) {
        self.itemID = itemID
        self.name = name
        self.kindLabel = kindLabel
        self.contributionText = contributionText
        self.compactLabels = compactLabels
        self.opticalColor = opticalColor
        self.sourceColor = sourceColor
        self.accessibilityText = accessibilityText
    }
}

/// The Main summary space (FILTER-AUX-001/002): every mounted
/// auxiliary item with its identity and contribution, readable without
/// a tap. `nil` while nothing is mounted, so the space is hidden.
public struct AuxiliaryFilterSummaryDisplayState: Equatable, Sendable {
    /// How many rows Main shows individually; the rest are counted in
    /// the `+ N more` line (FILTER-AUX-002).
    public static let visibleItemLimit = 3

    /// Every mounted item, in display order.
    public let items: [AuxiliaryFilterSummaryItemDisplay]
    /// Spoken label of the summary button: the title followed by every
    /// item's description, including the ones not shown (FILTER-A11Y-001).
    public let accessibilityLabel: String

    public init(items: [AuxiliaryFilterSummaryItemDisplay], accessibilityLabel: String) {
        self.items = items
        self.accessibilityLabel = accessibilityLabel
    }

    /// The first three items in display order, each shown as a row.
    public var visibleItems: [AuxiliaryFilterSummaryItemDisplay] {
        Array(items.prefix(Self.visibleItemLimit))
    }

    /// How many mounted items are not shown individually; 0 when all fit.
    public var hiddenItemCount: Int {
        max(0, items.count - Self.visibleItemLimit)
    }

    /// `+ 2 more` when items are hidden; `nil` otherwise.
    public var moreText: String? {
        hiddenItemCount > 0 ? String(localized: "+ \(hiddenItemCount) more") : nil
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
        let items = rows.map { itemDisplay(for: $0, among: rows) }
        let spoken = ([title] + items.map(\.accessibilityText)).joined(separator: ", ")
        return AuxiliaryFilterSummaryDisplayState(items: items, accessibilityLabel: spoken)
    }

    /// The Selected filters panel of Shooting Filters (FILTER-FLOW-003,
    /// FILTER-GND-003): every selected filter in Main's order, each with
    /// its whole user-defined name, its type, and its contribution — a
    /// GND also its mode. Names are never shortened here; only the view
    /// may truncate one that does not fit.
    public static func selectedFilterRows(for rows: [ResolvedAuxiliaryFilter]) -> [SelectedFilterRowDisplayState] {
        rows.map { row in
            let contribution = FilterWheelPresenter.stopsText(row.contributionStops)
            let valueText: String
            if case .gnd(let mode) = row.mount.choice {
                valueText = "\(FilterWheelPresenter.gndModeName(mode)) · \(contribution)"
            } else {
                valueText = contribution
            }
            return SelectedFilterRowDisplayState(
                itemID: row.item.id,
                name: row.item.name,
                kindLabel: FilterWheelPresenter.kindName(row.item.behavior.kind),
                opticalColor: row.item.behavior.opticalColor,
                valueText: valueText
            )
        }
    }

    /// One row of the summary. `rows` are all mounted items, so the
    /// identifier can tell two items of the same kind apart.
    public static func itemDisplay(for row: ResolvedAuxiliaryFilter, among rows: [ResolvedAuxiliaryFilter]) -> AuxiliaryFilterSummaryItemDisplay {
        let contributionSpoken = FilterWheelPresenter.stopsText(row.contributionStops)
        let kind = row.item.behavior.kind
        let semanticType: String
        switch row.mount.choice {
        case .cplLoss:
            semanticType = FilterWheelPresenter.kindName(.cpl)
        case .gnd(let mode):
            semanticType = "\(FilterWheelPresenter.kindName(.gnd)) \(FilterWheelPresenter.gndModeName(mode))"
        case .registeredLoss:
            if let color = row.item.behavior.opticalColor {
                semanticType = "\(FilterWheelPresenter.kindName(.color)) \(FilterWheelPresenter.opticalColorName(color))"
            } else {
                semanticType = FilterWheelPresenter.kindName(kind)
            }
        }
        return AuxiliaryFilterSummaryItemDisplay(
            itemID: row.item.id,
            name: row.item.name,
            kindLabel: FilterWheelPresenter.kindName(kind),
            contributionText: FilterWheelPresenter.decimalStopsValue(row.contributionStops),
            compactLabels: compactLabels(for: row, among: rows),
            opticalColor: row.item.behavior.opticalColor,
            sourceColor: row.filterSetColor,
            accessibilityText: "\(row.item.name), \(semanticType), \(contributionSpoken)"
        )
    }

    /// The deterministic concise-name rule for a compact Main row,
    /// longest candidate first; the view shows the first that fits.
    /// - A CPL is identified as `CPL` when it is the only mounted CPL;
    ///   with two, by name so they stay distinct.
    /// - A GND, Color, or Effect item is identified by name
    ///   (FILTER-AUX-006: a GND by its distinguishing name, so equal
    ///   Hard and Soft densities never read alike).
    /// - A name's candidates are the whole name, then the words before
    ///   the first word that contains a digit (`Soft GND 2` → `Soft GND`,
    ///   `MARUMI Red 25A` → `MARUMI Red`), then the first word
    ///   (`MARUMI`). A shortened candidate that another mounted item of
    ///   the same kind would also show is left out, so rows never read
    ///   the same.
    public static func compactLabels(for row: ResolvedAuxiliaryFilter, among rows: [ResolvedAuxiliaryFilter]) -> [String] {
        let kind = row.item.behavior.kind
        let sameKind = rows.filter { $0.item.behavior.kind == kind }
        if kind == .cpl, sameKind.count == 1 {
            return [FilterWheelPresenter.kindName(kind)]
        }
        let others = sameKind.filter { $0.item.id != row.item.id }.map { nameCandidates($0.item.name) }
        let candidates = nameCandidates(row.item.name)
        guard let whole = candidates.first else {
            return [row.item.name]
        }
        let shortened = candidates.dropFirst().filter { candidate in
            !others.contains { $0.contains(candidate) }
        }
        return [whole] + shortened
    }

    private static func nameCandidates(_ name: String) -> [String] {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else {
            return []
        }
        var candidates = [words.joined(separator: " ")]
        let leading = words.prefix { word in !word.contains(where: \.isNumber) }
        if !leading.isEmpty, leading.count < words.count {
            candidates.append(leading.joined(separator: " "))
        }
        if words.count > 1, candidates.last != first {
            candidates.append(first)
        }
        return candidates
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
