// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// The fixed presentation order of Filter Sets and their items
/// (FILTER-SET-004, FILTER-ITEM-001). There is no manual reorder: a Set's
/// items read ND first, then Color, Effect, CPL, and GND, each kind
/// alphabetically by name; Available Sets read alphabetically by name.
/// Names compare the way the platform sorts them for the current
/// locale.
public enum FilterSetItemOrder {
    public static let kinds: [FilterItemKind] = [.fixed, .color, .effect, .cpl, .gnd]

    /// The auxiliary part of the same order, which is also the fixed
    /// auxiliary order of Main and Shooting Filters (FILTER-AUX-006).
    public static let auxiliaryKinds: [FilterItemKind] = kinds.filter(\.isAuxiliary)

    /// New Filter opens with ND selected (FILTER-ITEM-003).
    public static let newItemKind: FilterItemKind = .fixed

    public static func ordered(_ items: [FilterItem]) -> [FilterItem] {
        kinds.flatMap { kind in
            items.filter { $0.behavior.kind == kind }.sorted { precedes($0.name, $0.id.rawValue, $1.name, $1.id.rawValue) }
        }
    }

    public static func sortedByName(_ filterSets: [FilterSet]) -> [FilterSet] {
        filterSets.sorted { precedes($0.name, $0.id.rawValue, $1.name, $1.id.rawValue) }
    }

    /// Locale-aware name order; equal names keep a stable order by id.
    private static func precedes(_ lhsName: String, _ lhsID: String, _ rhsName: String, _ rhsID: String) -> Bool {
        switch lhsName.localizedStandardCompare(rhsName) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return lhsID < rhsID
        }
    }
}

/// One auxiliary item Shooting Filters offers, with the selected Filter
/// Set it comes from.
public struct OfferedAuxiliaryItem: Equatable, Sendable {
    public let filterSet: FilterSet
    public let item: FilterItem

    public init(filterSet: FilterSet, item: FilterItem) {
        self.filterSet = filterSet
        self.item = item
    }
}
