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

/// The passive contents hint of an Available Filter Set row
/// (FILTER-SET-001): every kind the set holds with its registered item
/// count, in the fixed kind order — `ND ×3 · Color ×2 · CPL`, a count of
/// one without ×1, absent kinds left out — or `Empty`. Counts are items,
/// never stops, mounts, or CPL choices.
public enum FilterSetContentsHint {
    public struct Entry: Equatable, Sendable {
        public let kind: FilterItemKind
        public let count: Int

        public init(kind: FilterItemKind, count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    public static func entries(of filterSet: FilterSet) -> [Entry] {
        FilterSetItemOrder.kinds.compactMap { kind in
            let count = filterSet.items.filter { $0.behavior.kind == kind }.count
            return count > 0 ? Entry(kind: kind, count: count) : nil
        }
    }

    public static func text(of filterSet: FilterSet) -> String {
        let entries = entries(of: filterSet)
        guard !entries.isEmpty else {
            return String(localized: "Empty")
        }
        return entries.map { entry in
            let name = FilterWheelPresenter.kindName(entry.kind)
            return entry.count > 1 ? "\(name) ×\(entry.count)" : name
        }
        .joined(separator: " · ")
    }
}

/// The Plus ND source preferred after an Apply adds Filter Sets while
/// Plus is on Standard (FILTER-PLUS-006): among the selected Sets that
/// hold ND items, the one with the most registered ND items, an ND-only
/// Set before a mixed one on a tie, then by name; equal names keep the
/// selection order. `nil` when no selected Set holds an ND item.
public enum PreferredNDSource {
    public static func winner(among selected: [FilterSet]) -> FilterSetID? {
        let eligible = selected.enumerated().compactMap { offset, filterSet -> (FilterSet, Int, Int)? in
            let ndCount = filterSet.items.filter { $0.behavior.kind == .fixed }.count
            return ndCount > 0 ? (filterSet, ndCount, offset) : nil
        }
        return eligible.min { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }
            let lhsNDOnly = lhs.0.auxiliaryItems.isEmpty
            let rhsNDOnly = rhs.0.auxiliaryItems.isEmpty
            if lhsNDOnly != rhsNDOnly {
                return lhsNDOnly
            }
            switch lhs.0.name.localizedStandardCompare(rhs.0.name) {
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            case .orderedSame:
                return lhs.2 < rhs.2
            }
        }?.0.id
    }
}
