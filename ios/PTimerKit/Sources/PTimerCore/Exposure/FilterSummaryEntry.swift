// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Immutable per-wheel summary captured when a timer starts. Carries
/// enough to reconstruct the shot basis — source kind, Filter Set id
/// and name, item id and name, the original registered value and
/// unit, canonical stops, the selected calculation mode, and the
/// stops actually contributed. Later inventory edits never rewrite a
/// captured entry.
public struct FilterSummaryEntry: Hashable, Sendable {
    public enum SourceKind: String, Sendable {
        case standard
        case filterSet
    }

    public enum CalculationMode: String, Sendable {
        case fixed
        case cplLoss
        case gndRecordOnly
        case gndApplyFullValue
    }

    public let sourceKind: SourceKind
    public let filterSetID: String?
    public let filterSetName: String?
    public let itemID: String?
    public let itemName: String?
    public let itemKind: FilterItemKind?
    public let originalValue: Double?
    public let originalUnit: FilterValueUnit?
    public let canonicalStops: Double?
    public let calculationMode: CalculationMode?
    public let contributedStops: Double

    public init(
        sourceKind: SourceKind,
        filterSetID: String? = nil,
        filterSetName: String? = nil,
        itemID: String? = nil,
        itemName: String? = nil,
        itemKind: FilterItemKind? = nil,
        originalValue: Double? = nil,
        originalUnit: FilterValueUnit? = nil,
        canonicalStops: Double?,
        calculationMode: CalculationMode? = nil,
        contributedStops: Double
    ) {
        self.sourceKind = sourceKind
        self.filterSetID = filterSetID
        self.filterSetName = filterSetName
        self.itemID = itemID
        self.itemName = itemName
        self.itemKind = itemKind
        self.originalValue = originalValue
        self.originalUnit = originalUnit
        self.canonicalStops = canonicalStops
        self.calculationMode = calculationMode
        self.contributedStops = contributedStops
    }

    /// Captures `stack` against `inventory` as it stands right now,
    /// in main-row order: every mounted auxiliary filter first, then
    /// every wheel. Empty wheels are omitted (nothing mounted);
    /// Record-only GNDs are kept with a 0-stop contribution. Color and
    /// Effect items record `fixed` as their mode — they contribute
    /// their registered loss — with the item kind telling them apart.
    public static func summary(for stack: FilterStack, inventory: FilterInventory) -> [FilterSummaryEntry] {
        let auxiliary = stack.auxiliaryRows.map { row -> FilterSummaryEntry in
            let mode: CalculationMode
            switch row.mount.choice {
            case .cplLoss: mode = .cplLoss
            case .gnd(.recordOnly): mode = .gndRecordOnly
            case .gnd(.applyFullValue): mode = .gndApplyFullValue
            case .registeredLoss: mode = .fixed
            }
            let registered = row.item.behavior.registeredValue
            return FilterSummaryEntry(
                sourceKind: .filterSet,
                filterSetID: row.mount.filterSetID.rawValue,
                filterSetName: row.filterSetName,
                itemID: row.mount.itemID.rawValue,
                itemName: row.item.name,
                itemKind: row.item.behavior.kind,
                originalValue: registered?.value,
                originalUnit: registered?.unit,
                canonicalStops: row.registeredStops,
                calculationMode: mode,
                contributedStops: row.contributionStops
            )
        }
        let wheels = zip(stack.wheels, stack.rows).compactMap { wheel, row -> FilterSummaryEntry? in
            switch wheel.selection {
            case .standard(let step):
                return FilterSummaryEntry(
                    sourceKind: .standard,
                    canonicalStops: step.stops,
                    contributedStops: step.stops
                )
            case .empty:
                return nil
            case .item(let selection):
                let filterSet = wheel.source.filterSetID.flatMap(inventory.filterSet(withID:))
                let item = row.item
                let registered = item?.behavior.registeredValue
                return FilterSummaryEntry(
                    sourceKind: .filterSet,
                    filterSetID: wheel.source.filterSetID?.rawValue,
                    filterSetName: filterSet?.name,
                    itemID: selection.itemID.rawValue,
                    itemName: item?.name,
                    itemKind: item?.behavior.kind,
                    originalValue: registered?.value,
                    originalUnit: registered?.unit,
                    canonicalStops: row.registeredStops,
                    calculationMode: .fixed,
                    contributedStops: row.contributionStops
                )
            }
        }
        return auxiliary + wheels
    }
}
