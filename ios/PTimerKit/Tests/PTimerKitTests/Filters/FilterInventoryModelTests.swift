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
        XCTAssertEqual(model.filterSets.map(\.id), [first.id, second.id])
        XCTAssertNil(model.createFilterSet(name: "   ", color: .blue), "A blank name creates nothing.")

        model.renameFilterSet(id: first.id, name: "  Lee 100  ")
        model.recolorFilterSet(id: first.id, color: .green)
        model.moveFilterSets(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(model.filterSets.map(\.id), [second.id, first.id])
        XCTAssertEqual(model.filterSet(withID: first.id)?.name, "Lee 100")
        XCTAssertEqual(model.filterSet(withID: first.id)?.color, .green)
        XCTAssertEqual(model.inventory.sources, [.standard, .filterSet(second.id), .filterSet(first.id)])
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
        XCTAssertTrue(model.filterSets.isEmpty)
    }

    // MARK: Persistence

    func testInventoryRoundTripsThroughTheStore() throws {
        let store = InMemoryFilterInventoryStore()
        let model = FilterInventoryModel(store: store)
        let set = try XCTUnwrap(model.createFilterSet(name: "Kit", color: .teal))
        let fixed = FilterItem(name: "ND1000", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, nil, 2.5])))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 0.6, unit: .opticalDensity)))
        model.addItem(fixed, to: set.id)
        model.addItem(cpl, to: set.id)
        model.addItem(gnd, to: set.id)

        let data = try JSONEncoder().encode(try XCTUnwrap(store.stored))
        let decoded = PersistentFilterInventorySnapshot.decode(from: data)
        XCTAssertEqual(decoded.outcome, .loaded)
        XCTAssertEqual(decoded.snapshot.restoredInventory, model.inventory)

        let restored = FilterInventoryModel(store: store)
        XCTAssertEqual(restored.inventory, model.inventory)
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
        XCTAssertEqual(inventory.filterSets[0].items.map(\.id.rawValue), ["i1"], "Unknown kind and invalid CPL choices drop only that item.")
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
