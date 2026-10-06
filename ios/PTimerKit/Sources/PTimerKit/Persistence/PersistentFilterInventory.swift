// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// On-disk schema for the user's filter inventory (Filter Sets and
/// their physical items). Decoded per record through
/// `VersionedCollectionDecoder`: a Filter Set that fails to decode is
/// dropped while the rest survive, and a malformed item inside a set
/// is skipped without losing the set. Stable ids, names, colors,
/// order, kinds, original values/units, and CPL choices round-trip.
public struct PersistentFilterInventorySnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let filterSets: [PersistentFilterSetRecord]

    public init(schemaVersion: Int = currentSchemaVersion, filterSets: [PersistentFilterSetRecord]) {
        self.schemaVersion = schemaVersion
        self.filterSets = filterSets
    }

    public init(inventory: FilterInventory) {
        self.init(filterSets: inventory.filterSets.map(PersistentFilterSetRecord.init(filterSet:)))
    }

    /// Runtime inventory: records that do not restore (empty id or
    /// name) are skipped safely.
    public var restoredInventory: FilterInventory {
        FilterInventory(filterSets: filterSets.compactMap(\.restoredFilterSet))
    }

    public static func decode(from data: Data) -> SnapshotDecodeResult<PersistentFilterInventorySnapshot> {
        let result = VersionedCollectionDecoder.decodeRecords(
            PersistentFilterSetRecord.self,
            from: data,
            recordsKey: "filterSets",
            expectedSchemaVersion: currentSchemaVersion,
            idOf: { AnyHashable($0.id) }
        )
        return SnapshotDecodeResult(
            snapshot: PersistentFilterInventorySnapshot(filterSets: result.records),
            outcome: result.outcome,
            droppedRecordCount: result.droppedRecordCount
        )
    }
}

public struct PersistentFilterSetRecord: Codable, Equatable {
    public let id: String
    public let name: String
    /// `FilterSetColor.rawValue`; an unknown token restores as the
    /// default color rather than dropping the set.
    public let color: String
    public let items: [PersistentFilterItemRecord]

    public init(id: String, name: String, color: String, items: [PersistentFilterItemRecord]) {
        self.id = id
        self.name = name
        self.color = color
        self.items = items
    }

    public init(filterSet: FilterSet) {
        self.init(
            id: filterSet.id.rawValue,
            name: filterSet.name,
            color: filterSet.color.rawValue,
            items: filterSet.items.map(PersistentFilterItemRecord.init(item:))
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case items
    }

    /// Items decode leniently: one malformed item is skipped, the set
    /// and its remaining items survive.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(String.self, forKey: .color)
        var decodedItems: [PersistentFilterItemRecord] = []
        if var itemsContainer = try? container.nestedUnkeyedContainer(forKey: .items) {
            while !itemsContainer.isAtEnd {
                if let item = try? itemsContainer.decode(PersistentFilterItemRecord.self) {
                    decodedItems.append(item)
                } else {
                    _ = try? itemsContainer.superDecoder()
                }
            }
        }
        items = decodedItems
    }

    public var restoredFilterSet: FilterSet? {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedName.isEmpty else {
            return nil
        }
        var seen: Set<FilterItemID> = []
        let restoredItems = items.compactMap(\.restoredItem).filter { seen.insert($0.id).inserted }
        return FilterSet(
            id: FilterSetID(rawValue: trimmedID),
            name: trimmedName,
            color: PersistentFilterItemRecord.restoredColor(color) ?? .blue,
            items: restoredItems
        )
    }
}

public struct PersistentFilterItemRecord: Codable, Equatable {
    public let id: String
    public let name: String
    /// `FilterItemKind.rawValue`.
    public let kind: String
    /// Original registered value for Fixed / GND items.
    public let value: Double?
    /// `FilterValueUnit.rawValue` for Fixed / GND items.
    public let unit: String?
    /// The three CPL fields; `null` entries are empty fields.
    public let cplChoices: [Double?]?
    /// `FilterSetColor.rawValue` of a Color item's color. Additive: Color
    /// and Effect items store their loss in `value` (always stops, so
    /// `unit` stays `nil`) and pre-Color records omit this key.
    public let opticalColor: String?

    public init(id: String, name: String, kind: String, value: Double?, unit: String?, cplChoices: [Double?]?, opticalColor: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.value = value
        self.unit = unit
        self.cplChoices = cplChoices
        self.opticalColor = opticalColor
    }

    public init(item: FilterItem) {
        switch item.behavior {
        case .fixed(let value), .gnd(let value):
            self.init(id: item.id.rawValue, name: item.name, kind: item.behavior.kind.rawValue, value: value.value, unit: value.unit.rawValue, cplChoices: nil)
        case .cpl(let choices):
            self.init(id: item.id.rawValue, name: item.name, kind: item.behavior.kind.rawValue, value: nil, unit: nil, cplChoices: choices.fields)
        case .color(let loss, let color):
            self.init(id: item.id.rawValue, name: item.name, kind: item.behavior.kind.rawValue, value: loss.stops, unit: nil, cplChoices: nil, opticalColor: color.rawValue)
        case .effect(let loss):
            self.init(id: item.id.rawValue, name: item.name, kind: item.behavior.kind.rawValue, value: loss.stops, unit: nil, cplChoices: nil)
        }
    }

    /// `nil` when the record cannot restore as a well-formed item
    /// (unknown kind, missing or invalid value, no valid CPL choice,
    /// a Color item without a known optical color).
    public var restoredItem: FilterItem? {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedName.isEmpty,
              let kind = FilterItemKind(rawValue: kind) else {
            return nil
        }
        let behavior: FilterItemBehavior
        switch kind {
        case .fixed, .gnd:
            guard let value, let unitRaw = unit, let unit = FilterValueUnit(rawValue: unitRaw) else {
                return nil
            }
            let registered = FilterRegisteredValue(value: value, unit: unit)
            behavior = kind == .fixed ? .fixed(registered) : .gnd(registered)
        case .cpl:
            guard let cplChoices else {
                return nil
            }
            behavior = .cpl(CPLExposureLossChoices(fields: cplChoices))
        case .color:
            guard let value, let colorRaw = opticalColor, let color = Self.restoredColor(colorRaw) else {
                return nil
            }
            behavior = .color(FilterExposureLoss(stops: value), color)
        case .effect:
            guard let value else {
                return nil
            }
            behavior = .effect(FilterExposureLoss(stops: value))
        }
        let item = FilterItem(id: FilterItemID(rawValue: trimmedID), name: trimmedName, behavior: behavior)
        return item.isWellFormed ? item : nil
    }

    /// A persisted palette token — a Filter Set's color or a Color
    /// item's color. Tokens retired from the earlier twelve-color
    /// palette map to their nearest remaining hue (mint and cyan to
    /// teal, indigo to blue, brown to orange) so no set or item loses
    /// its color; the next save writes the current token. `nil` for an
    /// unknown token.
    static func restoredColor(_ raw: String) -> FilterSetColor? {
        if let color = FilterSetColor(rawValue: raw) {
            return color
        }
        switch raw {
        case "mint", "cyan": return .teal
        case "indigo": return .blue
        case "brown": return .orange
        default: return nil
        }
    }
}

/// Persistence boundary for the filter inventory. Real / no-op
/// implementations follow the `*Storing` / `NoOp*` pair convention.
public protocol FilterInventoryStoring {
    func loadSnapshot() -> PersistentFilterInventorySnapshot?
    func saveSnapshot(_ snapshot: PersistentFilterInventorySnapshot)
    func clearSnapshot()
}

public struct NoOpFilterInventoryStore: FilterInventoryStoring {
    public init() {}
    public func loadSnapshot() -> PersistentFilterInventorySnapshot? { nil }
    public func saveSnapshot(_ snapshot: PersistentFilterInventorySnapshot) {}
    public func clearSnapshot() {}
}
