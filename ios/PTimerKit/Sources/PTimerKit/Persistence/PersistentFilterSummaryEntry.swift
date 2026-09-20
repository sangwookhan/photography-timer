// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// On-disk shape of one captured filter summary entry
/// (FILTER-PERSIST-003). The Core `FilterSummaryEntry` stays a plain
/// value; this record owns the serialized field names and the raw
/// string tokens of every enum so a Core rename can never silently
/// invalidate stored timers. Entries decode independently: a
/// malformed or unknown-token entry is dropped and the remaining
/// entries survive (`decodeLossyArray`).
public struct PersistentFilterSummaryEntry: Codable, Equatable {
    public let sourceKind: String
    public let filterSetID: String?
    public let filterSetName: String?
    public let itemID: String?
    public let itemName: String?
    public let itemKind: String?
    public let originalValue: Double?
    public let originalUnit: String?
    public let canonicalStops: Double?
    public let calculationMode: String?
    public let contributedStops: Double

    public init(_ entry: FilterSummaryEntry) {
        sourceKind = entry.sourceKind.rawValue
        filterSetID = entry.filterSetID
        filterSetName = entry.filterSetName
        itemID = entry.itemID
        itemName = entry.itemName
        itemKind = entry.itemKind?.rawValue
        originalValue = entry.originalValue
        originalUnit = entry.originalUnit?.rawValue
        canonicalStops = entry.canonicalStops
        calculationMode = entry.calculationMode?.rawValue
        contributedStops = entry.contributedStops
    }

    /// The domain value, or `nil` when a required token is unknown.
    /// Optional tokens that fail to map degrade to `nil` on the entry
    /// rather than discarding it.
    public var entry: FilterSummaryEntry? {
        guard let kind = FilterSummaryEntry.SourceKind(rawValue: sourceKind),
              contributedStops.isFinite else {
            return nil
        }
        return FilterSummaryEntry(
            sourceKind: kind,
            filterSetID: filterSetID,
            filterSetName: filterSetName,
            itemID: itemID,
            itemName: itemName,
            itemKind: itemKind.flatMap(FilterItemKind.init(rawValue:)),
            originalValue: originalValue,
            originalUnit: originalUnit.flatMap(FilterValueUnit.init(rawValue:)),
            canonicalStops: canonicalStops,
            calculationMode: calculationMode.flatMap(FilterSummaryEntry.CalculationMode.init(rawValue:)),
            contributedStops: contributedStops
        )
    }

    /// Decodes the array under `key` entry by entry, skipping the ones
    /// that fail to decode or map, so one damaged record never erases
    /// the whole captured summary. Returns `nil` when the key is absent
    /// or holds something other than an array.
    static func decodeLossyArray<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> [FilterSummaryEntry]? {
        guard var entries = try? container.nestedUnkeyedContainer(forKey: key) else {
            return nil
        }
        var decoded: [FilterSummaryEntry] = []
        while !entries.isAtEnd {
            if let record = try? entries.decode(PersistentFilterSummaryEntry.self) {
                if let entry = record.entry {
                    decoded.append(entry)
                }
            } else {
                _ = try? entries.superDecoder()
            }
        }
        return decoded
    }
}
