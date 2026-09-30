// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Filter Set management (FILTER-SET-001…004, FILTER-ITEM-001/002)
/// and inventory persistence (FILTER-PERSIST-001/002).
@MainActor
final class FilterInventoryModelTests: XCTestCase {

    func testCreatedFilterSetsAppendInUserOrderAndKeepIDsThroughRenameRecolorReorder() throws {
        let model = FilterInventoryModel()
        let first = try XCTUnwrap(model.createFilterSet(name: "Lee", color: .red))
        let second = try XCTUnwrap(model.createFilterSet(name: "NiSi", color: .red), "Duplicate colors are allowed.")
        XCTAssertEqual(model.filterSets.map(\.id), [.defaultSet, first.id, second.id], "Default comes first.")
        XCTAssertNil(model.createFilterSet(name: "   ", color: .blue), "A blank name creates nothing.")

        model.renameFilterSet(id: first.id, name: "  Lee 100  ")
        model.recolorFilterSet(id: first.id, color: .green)
        model.moveFilterSets(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(model.filterSets.map(\.id), [.defaultSet, second.id, first.id], "A set dropped above Default still follows it.")
        XCTAssertEqual(model.filterSet(withID: first.id)?.name, "Lee 100")
        XCTAssertEqual(model.filterSet(withID: first.id)?.color, .green)
        XCTAssertEqual(model.inventory.sources, [.standard, .filterSet(.defaultSet), .filterSet(second.id), .filterSet(first.id)])
    }

    /// FILTER-SET-002/004: the built-in Default Filter Set always
    /// exists, comes first, keeps its id through rename and recolor, and
    /// cannot be deleted. An inventory stored before it existed gains it
    /// ahead of the user's sets without reordering them.
    func testDefaultFilterSetIsBuiltInFirstEditableAndNeverDeleted() throws {
        let store = InMemoryFilterInventoryStore()
        let model = FilterInventoryModel(store: store)
        XCTAssertEqual(model.filterSets, [FilterInventory.defaultFilterSet])
        XCTAssertEqual(model.filterSets[0].name, "Default")
        XCTAssertTrue(model.filterSets[0].items.isEmpty)

        model.renameFilterSet(id: .defaultSet, name: "Bag")
        model.recolorFilterSet(id: .defaultSet, color: .green)
        let nd = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        model.addItem(nd, to: .defaultSet)
        model.deleteFilterSet(id: .defaultSet)
        XCTAssertEqual(model.filterSets.map(\.id), [.defaultSet], "Default is never deleted.")

        let restored = FilterInventoryModel(store: store)
        let restoredDefault = try XCTUnwrap(restored.filterSet(withID: .defaultSet))
        XCTAssertEqual(restoredDefault.name, "Bag")
        XCTAssertEqual(restoredDefault.color, .green)
        XCTAssertEqual(restoredDefault.items, [nd])

        let json = """
        { "schemaVersion": 1, "filterSets": [
            { "id": "s1", "name": "Lee", "color": "red", "items": [] },
            { "id": "s2", "name": "NiSi", "color": "blue", "items": [] } ] }
        """
        let older = InMemoryFilterInventoryStore()
        older.stored = PersistentFilterInventorySnapshot.decode(from: Data(json.utf8)).snapshot
        XCTAssertEqual(FilterInventoryModel(store: older).filterSets.map(\.id.rawValue), ["default", "s1", "s2"])
    }

    func testColorSuggestionDiffersFromThePreviousSuggestion() {
        let model = FilterInventoryModel()
        var previous = model.suggestCreationColor()
        for _ in 0..<50 {
            let next = model.suggestCreationColor()
            XCTAssertNotEqual(next, previous)
            previous = next
        }
    }

    func testItemsAddUpdateMoveDeleteWithinASet() throws {
        let model = FilterInventoryModel()
        let set = try XCTUnwrap(model.createFilterSet(name: "Holder", color: .blue))
        let a = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        let b = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        model.addItem(a, to: set.id)
        model.addItem(b, to: set.id)
        XCTAssertEqual(model.filterSet(withID: set.id)?.items.map(\.id), [a.id, b.id], "Equal items are separate physical filters.")

        var edited = a
        edited.name = "Hoya ND8"
        edited.behavior = .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity))
        model.updateItem(edited)
        XCTAssertEqual(model.item(withID: a.id)?.item, edited)

        model.moveItems(in: set.id, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(model.filterSet(withID: set.id)?.items.map(\.id), [b.id, a.id])

        model.deleteItem(id: b.id)
        XCTAssertEqual(model.filterSet(withID: set.id)?.items.map(\.id), [a.id])

        let malformed = FilterItem(name: "", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        model.addItem(malformed, to: set.id)
        XCTAssertEqual(model.filterSet(withID: set.id)?.items.count, 1, "Malformed items are refused.")

        model.deleteFilterSet(id: set.id)
        XCTAssertEqual(model.filterSets.map(\.id), [.defaultSet])
    }

    // MARK: Persistence

    func testInventoryRoundTripsThroughTheStore() throws {
        let store = InMemoryFilterInventoryStore()
        let model = FilterInventoryModel(store: store)
        let set = try XCTUnwrap(model.createFilterSet(name: "Kit", color: .teal))
        let fixed = FilterItem(name: "ND1000", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, nil, 2.5])))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 0.6, unit: .opticalDensity)))
        let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
        let night = FilterItem(name: "Night", behavior: .effect(FilterExposureLoss(stops: 0)))
        model.addItem(fixed, to: set.id)
        model.addItem(cpl, to: set.id)
        model.addItem(gnd, to: set.id)
        model.addItem(red, to: set.id)
        model.addItem(night, to: set.id)

        let redRecord = try XCTUnwrap(store.stored?.filterSets.first { $0.id == set.id.rawValue }?.items.first { $0.id == red.id.rawValue })
        XCTAssertEqual(redRecord.kind, "color")
        XCTAssertEqual(redRecord.opticalColor, "red")
        XCTAssertEqual(redRecord.value, 3)
        XCTAssertNil(redRecord.unit, "Color / Effect loss is always stops.")

        let data = try JSONEncoder().encode(try XCTUnwrap(store.stored))
        let decoded = PersistentFilterInventorySnapshot.decode(from: data)
        XCTAssertEqual(decoded.outcome, .loaded)
        XCTAssertEqual(decoded.snapshot.restoredInventory, model.inventory)

        let restored = FilterInventoryModel(store: store)
        XCTAssertEqual(restored.inventory, model.inventory)
    }

    /// Palette tokens survive the palette change: `yellowGreen` (from an
    /// earlier Draft Color item) is a palette color again, and tokens
    /// retired from the twelve-color palette map to their nearest
    /// remaining hue for both Filter Sets and Color items. Nothing is
    /// dropped, and the next save writes the current token.
    func testRetiredAndDraftPaletteTokensRestoreWithoutLoss() throws {
        let json = """
        {
          "schemaVersion": 1,
          "filterSets": [
            { "id": "s1", "name": "Mint kit", "color": "mint",
              "items": [
                { "id": "i1", "name": "X1 Yellow-green", "kind": "color", "value": 1.5, "opticalColor": "yellowGreen" },
                { "id": "i2", "name": "Brown", "kind": "color", "value": 1, "opticalColor": "brown" },
                { "id": "i3", "name": "Red 25A", "kind": "color", "value": 3, "opticalColor": "red" }
              ] },
            { "id": "s2", "name": "Cyan kit", "color": "cyan", "items": [] },
            { "id": "s3", "name": "Indigo kit", "color": "indigo", "items": [] },
            { "id": "s4", "name": "Brown kit", "color": "brown", "items": [] }
          ]
        }
        """
        let result = PersistentFilterInventorySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .loaded)
        let inventory = result.snapshot.restoredInventory
        XCTAssertEqual(inventory.filterSets.map(\.color), [.teal, .teal, .blue, .orange])
        let items = try XCTUnwrap(inventory.filterSets.first).items
        XCTAssertEqual(items.map(\.id.rawValue), ["i1", "i2", "i3"])
        XCTAssertEqual(items.map(\.behavior.opticalColor), [.yellowGreen, .orange, .red])
        XCTAssertEqual(items[0].name, "X1 Yellow-green")

        let resaved = PersistentFilterInventorySnapshot(inventory: inventory)
        XCTAssertEqual(resaved.filterSets.map(\.color), ["teal", "teal", "blue", "orange"])
        XCTAssertEqual(resaved.filterSets.first?.items.map(\.opticalColor), ["yellowGreen", "orange", "red"])
    }

    func testMalformedSetIsDroppedAndMalformedItemIsSkipped() throws {
        let json = """
        {
          "schemaVersion": 1,
          "filterSets": [
            { "id": "s1", "name": "Good", "color": "nonsense-color",
              "items": [
                { "id": "i1", "name": "ND8", "kind": "fixed", "value": 3, "unit": "stops" },
                { "id": "i2", "name": "Bad kind", "kind": "prism", "value": 3, "unit": "stops" },
                { "id": "i3", "name": "CPL", "kind": "cpl", "cplChoices": [1, null, 12] },
                { "id": "i4", "name": "Red", "kind": "color", "value": 2 },
                { "id": "i5", "name": "Night", "kind": "effect", "value": 0.5 },
                "not an object"
              ] },
            { "id": 42, "name": "Broken" }
          ]
        }
        """
        let result = PersistentFilterInventorySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.droppedRecordCount, 1)
        let inventory = result.snapshot.restoredInventory
        XCTAssertEqual(inventory.filterSets.count, 1)
        XCTAssertEqual(inventory.filterSets[0].color, .blue, "Unknown color token falls back instead of dropping the set.")
        XCTAssertEqual(inventory.filterSets[0].items.map(\.id.rawValue), ["i1", "i5"], "Unknown kind, invalid CPL choices, and a Color item without an optical color drop only that item.")
        XCTAssertEqual(inventory.filterSets[0].items[1].behavior, .effect(FilterExposureLoss(stops: 0.5)))
    }
}

/// In-memory inventory store exposing the stored snapshot for
/// on-disk-shape assertions.
final class InMemoryFilterInventoryStore: FilterInventoryStoring {
    var stored: PersistentFilterInventorySnapshot?
    func loadSnapshot() -> PersistentFilterInventorySnapshot? { stored }
    func saveSnapshot(_ snapshot: PersistentFilterInventorySnapshot) { stored = snapshot }
    func clearSnapshot() { stored = nil }
}
