// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Filter Set management (FILTER-SET-001…004, FILTER-ITEM-001/002)
/// and inventory persistence (FILTER-PERSIST-001/002).
@MainActor
final class FilterInventoryModelTests: XCTestCase {

    func testCreatedFilterSetsKeepIDsThroughRenameAndRecolor() throws {
        let model = FilterInventoryModel()
        XCTAssertTrue(model.filterSets.isEmpty, "No built-in Set (FILTER-SET-002 retired).")
        let first = try XCTUnwrap(model.createFilterSet(name: "Lee", color: .red))
        let second = try XCTUnwrap(model.createFilterSet(name: "NiSi", color: .red), "Duplicate colors are allowed.")
        XCTAssertEqual(model.filterSets.map(\.id), [first.id, second.id])
        XCTAssertNil(model.createFilterSet(name: "   ", color: .blue), "A blank name creates nothing.")

        model.renameFilterSet(id: first.id, name: "  Lee 100  ")
        model.recolorFilterSet(id: first.id, color: .green)

        XCTAssertEqual(model.filterSets.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.filterSet(withID: first.id)?.name, "Lee 100")
        XCTAssertEqual(model.filterSet(withID: first.id)?.color, .green)
        XCTAssertEqual(model.inventory.sources, [.standard, .filterSet(first.id), .filterSet(second.id)])
    }

    /// FILTER-SET-008: a fresh installation starts with the given
    /// inventory, written at once, so it is offered only once: Samples the
    /// user deleted stay deleted after a relaunch, and a saved empty
    /// inventory stays empty.
    func testFreshInstallSeedsTheInitialInventoryOnce() throws {
        let store = InMemoryFilterInventoryStore()
        let samples = FilterInventory.samples()
        let model = FilterInventoryModel(store: store, initial: samples)
        XCTAssertEqual(model.inventory, samples)
        XCTAssertEqual(store.stored?.restoredInventory, samples, "The seed is written at once.")

        let edited = try XCTUnwrap(samples.filterSets.first)
        model.renameFilterSet(id: edited.id, name: "My ND")
        XCTAssertEqual(FilterInventoryModel(store: store, initial: FilterInventory.samples()).filterSet(withID: edited.id)?.name, "My ND", "An edited Sample is not overwritten.")

        for filterSet in samples.filterSets {
            model.deleteFilterSet(id: filterSet.id)
        }
        XCTAssertTrue(FilterInventoryModel(store: store, initial: FilterInventory.samples()).filterSets.isEmpty, "Deleted Samples are not seeded again.")
    }

    /// FILTER-SET-009: an upgrade keeps the saved inventory as it is: no
    /// Samples, and a former Default Set is ordinary inventory with its
    /// id, name, color, and place, which can be deleted.
    func testUpgradeKeepsAFormerDefaultAsAnOrdinarySet() throws {
        let json = """
        { "schemaVersion": 1, "filterSets": [
            { "id": "default", "name": "Default", "color": "blue", "items": [] },
            { "id": "s1", "name": "Lee", "color": "red", "items": [] } ] }
        """
        let store = InMemoryFilterInventoryStore()
        store.stored = PersistentFilterInventorySnapshot.decode(from: Data(json.utf8)).snapshot
        let model = FilterInventoryModel(store: store, initial: FilterInventory.samples())
        XCTAssertEqual(model.filterSets.map(\.id.rawValue), ["default", "s1"], "No Samples on upgrade.")
        let former = try XCTUnwrap(model.filterSet(withID: FilterSetID(rawValue: "default")))
        XCTAssertEqual(former.name, "Default")
        XCTAssertEqual(former.color, .blue)

        model.deleteFilterSet(id: former.id)
        XCTAssertEqual(model.filterSets.map(\.id.rawValue), ["s1"], "A former Default can be deleted.")
    }

    /// FILTER-SET-008: an upgrade that never saved an inventory gets the
    /// Samples once, like a fresh installation; a saved empty inventory
    /// and a payload that cannot be read count as saved and get none.
    func testSamplesAreSeededOnlyWhenNoInventoryWasEverSaved() throws {
        let neverSaved = InMemoryFilterInventoryStore()
        XCTAssertEqual(
            FilterInventoryModel(store: neverSaved, initial: FilterInventory.samples()).filterSets.map(\.name),
            FilterInventory.samples().filterSets.map(\.name),
            "Upgrade with nothing saved: Samples."
        )

        let savedEmpty = InMemoryFilterInventoryStore()
        savedEmpty.stored = PersistentFilterInventorySnapshot(inventory: .empty)
        XCTAssertTrue(FilterInventoryModel(store: savedEmpty, initial: FilterInventory.samples()).filterSets.isEmpty, "A saved empty inventory stays empty.")
        XCTAssertEqual(savedEmpty.saveCount, 0)

        for payload in ["not json", #"{ "schemaVersion": 99, "filterSets": [] }"#] {
            let unreadable = InMemoryFilterInventoryStore()
            unreadable.stored = PersistentFilterInventorySnapshot.decode(from: Data(payload.utf8)).snapshot
            XCTAssertTrue(FilterInventoryModel(store: unreadable, initial: FilterInventory.samples()).filterSets.isEmpty, "An unreadable payload is not a fresh installation: \(payload)")
            XCTAssertEqual(unreadable.saveCount, 0, "Nothing is written over it.")
        }
    }

    /// FILTER-SET-008: the Samples and their registered values; the
    /// Extended items convert through the shared ND-factor mapping
    /// (ND-011), ND400 by log2 without snapping.
    func testSamplesHoldTheApprovedItems() throws {
        let samples = FilterInventory.samples()
        XCTAssertEqual(samples.filterSets.map(\.name), ["Sample ND", "Sample ND — Extended", "Sample Aux Filter Set"])
        XCTAssertTrue(samples.filterSets.allSatisfy { $0.items.allSatisfy(\.isWellFormed) })
        XCTAssertEqual(Set(samples.filterSets.map(\.id)).count, 3)

        let nd = samples.filterSets[0].items
        XCTAssertEqual(nd.map(\.name), ["ND8", "ND64", "ND1000"])
        XCTAssertEqual(nd.compactMap(\.behavior.registeredValue).map(\.value), [3, 6, 10])

        let extended = samples.filterSets[1].items
        XCTAssertEqual(extended.map(\.name), ["ND100", "ND200", "ND400", "ND100k"])
        let stops = extended.compactMap { $0.behavior.registeredValue?.canonicalStops }
        XCTAssertEqual(stops.count, 4)
        XCTAssertEqual(stops[0], 6.6, accuracy: 1e-9)
        XCTAssertEqual(stops[1], 7.6, accuracy: 1e-9)
        XCTAssertEqual(stops[2], log2(400), accuracy: 1e-9)
        XCTAssertEqual(stops[3], 16.6, accuracy: 1e-9)

        let aux = samples.filterSets[2].items
        XCTAssertEqual(aux.map(\.name), ["CPL", "B+W 091 Red Dark", "B+W 040 Orange", "B+W 022 Yellow", "GND 2 stops"])
        XCTAssertEqual(aux[0].behavior, .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        XCTAssertEqual(aux[1].behavior, .color(FilterExposureLoss(stops: 3), .red))
        XCTAssertEqual(aux[2].behavior, .color(FilterExposureLoss(stops: 2), .orange))
        XCTAssertEqual(aux[3].behavior, .color(FilterExposureLoss(stops: 1), .yellow))
        XCTAssertEqual(aux[4].behavior, .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
    }

    /// FILTER-ITEM-009: a proposed New Filter Set and its filter are
    /// made in one change with one saved snapshot, so no Set-only state is
    /// published or saved; a refused save changes and writes nothing.
    func testProposedFilterSetIsCreatedTogetherWithItsFilter() throws {
        let store = InMemoryFilterInventoryStore()
        let model = FilterInventoryModel(store: store)
        var published: [FilterInventory] = []
        let observation = model.$inventory.dropFirst().sink { published.append($0) }
        defer { observation.cancel() }
        let item = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))

        XCTAssertNil(model.createFilterSet(name: "  ", color: .teal, holding: item), "A blank name creates nothing.")
        let illFormed = FilterItem(name: " ", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        XCTAssertNil(model.createFilterSet(name: "New Filter Set", color: .teal, holding: illFormed), "An invalid filter creates nothing.")
        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(store.saveCount, 0, "A refused save writes nothing.")

        let created = try XCTUnwrap(model.createFilterSet(name: " New Filter Set ", color: .teal, holding: item))
        XCTAssertEqual(created.name, "New Filter Set")
        XCTAssertEqual(created.items, [item])
        XCTAssertEqual(published.map { $0.filterSets.map(\.items) }, [[[item]]], "One published change, never a Set without its filter.")
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.stored?.restoredInventory, model.inventory)

        XCTAssertNil(model.createFilterSet(name: "Other", color: .red, holding: item), "An item id already in use creates nothing.")
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(model.filterSets.count, 1)
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

        // FILTER-ITEM-009: an existing item moves to another set with
        // its id and edits, in one change.
        let other = try XCTUnwrap(model.createFilterSet(name: "Pouch", color: .orange))
        var renamed = edited
        renamed.name = "Hoya GND"
        model.moveItem(renamed, to: other.id)
        XCTAssertEqual(model.filterSet(withID: set.id)?.items.map(\.id), [b.id])
        XCTAssertEqual(model.filterSet(withID: other.id)?.items, [renamed])
        XCTAssertEqual(model.item(withID: a.id)?.filterSet.id, other.id)
        model.moveItem(renamed, to: other.id)
        XCTAssertEqual(model.filterSet(withID: other.id)?.items.count, 1, "Moving into its own set changes nothing.")
        model.moveItem(renamed, to: set.id)
        XCTAssertEqual(model.filterSet(withID: set.id)?.items.map(\.id), [b.id, a.id])

        model.deleteItem(id: b.id)
        XCTAssertEqual(model.filterSet(withID: set.id)?.items.map(\.id), [a.id])

        let malformed = FilterItem(name: "", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        model.addItem(malformed, to: set.id)
        XCTAssertEqual(model.filterSet(withID: set.id)?.items.count, 1, "Malformed items are refused.")

        model.deleteFilterSet(id: set.id)
        XCTAssertEqual(model.filterSets.map(\.id), [other.id])
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
    private(set) var saveCount = 0
    func loadSnapshot() -> PersistentFilterInventorySnapshot? { stored }
    func saveSnapshot(_ snapshot: PersistentFilterInventorySnapshot) {
        stored = snapshot
        saveCount += 1
    }
    func clearSnapshot() { stored = nil }
}
