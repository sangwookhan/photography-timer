// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Mixed-stack persistence (FILTER-PERSIST-001/002, FILTER-PLUS-004):
/// relaunch round-trip of the wheels and the last Filter Source, the
/// Standard-only downgrade fields, legacy restore, and stale-reference
/// recovery.
@MainActor
final class FilterStackPersistenceTests: XCTestCase {
    private func select(_ item: FilterItem, _ choice: FilterRowChoice = .fixed) -> FilterWheelSelection {
        .item(FilterRowSelection(itemID: item.id, choice: choice))
    }

    func testMixedStackAndLastSourceSurviveRelaunch() throws {
        let sessionStore = InMemoryMixedSessionStore()
        let inventoryStore = InMemoryFilterInventoryStore()
        let inventory = FilterInventoryModel(store: inventoryStore)
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let item = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        inventory.addItem(item, to: set.id)
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        inventory.addItem(gnd, to: set.id)

        let viewModel = makeViewModel(sessionStore: sessionStore, inventoryModel: inventory)
        viewModel.setNDFilterStep(NDStep(stops: 6.6), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 2)
        XCTAssertEqual(viewModel.ndStep.stops, 16.6, accuracy: 1e-9)

        let restored = makeViewModel(
            sessionStore: sessionStore,
            inventoryModel: FilterInventoryModel(store: inventoryStore)
        )
        XCTAssertEqual(restored.filterWheels, [
            .standard(NDStep(stops: 6.6)),
            FilterWheel(source: .filterSet(set.id), selection: select(item)),
            FilterWheel(source: .filterSet(set.id), selection: select(gnd, .gnd(.recordOnly))),
        ])
        XCTAssertEqual(restored.ndStep.stops, 16.6, accuracy: 1e-9)
        XCTAssertEqual(restored.ndFilterSteps[1].stops, 10, "ND1000 restores as exactly 10 stops.")
        XCTAssertEqual(restored.selectedFilterSource, .filterSet(set.id))
    }

    func testDowngradeFieldsCarryStandardWheelsOnly() throws {
        let sessionStore = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = FilterItem(name: "X", behavior: .fixed(FilterRegisteredValue(value: 12, unit: .stops)))
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(sessionStore: sessionStore, inventoryModel: inventory)
        viewModel.setNDFilterStep(NDStep(stops: 3), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)

        let slot = try XCTUnwrap(sessionStore.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(slot.ndStack?.compactMap(\.ndStop), [3], "ndStack lists Standard wheels only.")
        XCTAssertEqual(slot.ndStop, 3, "The legacy scalar is the strongest Standard wheel.")
        XCTAssertEqual(slot.filterStack?.count, 2)
        XCTAssertEqual(slot.filterStack?[1].itemID, item.id.rawValue)
        XCTAssertEqual(slot.lastFilterSourceKind, "filterSet")
        XCTAssertEqual(slot.lastFilterSetID, set.id.rawValue)

        // A stack with no Standard wheel still degrades to one valid
        // Standard 0 wheel for older builds.
        viewModel.cleanupEmptyFilterWheels()
        viewModel.setWheelSelection(.standard(NDStep(stops: 0)), at: 0)
        // [item 12, standard 0] sorts Standard first: [0, item]; clean the zero.
        viewModel.cleanupEmptyFilterWheels()
        let onlyItem = try XCTUnwrap(sessionStore.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(onlyItem.filterStack?.count, 1)
        XCTAssertEqual(onlyItem.ndStack?.compactMap(\.ndStop), [0])
        XCTAssertEqual(onlyItem.ndStop, 0)
    }

    func testLegacyStandardOnlySnapshotStillRestores() {
        let sessionStore = InMemoryMixedSessionStore()
        sessionStore.stored = PersistentCameraSlotSessionSnapshot(
            schemaVersion: 1,
            activeSlotIDRaw: CameraSlotID.camera1.rawValue,
            slots: [
                PersistentCameraSlotCalculatorSnapshot(
                    slotIDRaw: CameraSlotID.camera1.rawValue,
                    selectedPresetFilmID: nil,
                    selectedProfileID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 10,
                    ndStack: [
                        PersistentNDFilterWheelSnapshot(ndStop: 10),
                        PersistentNDFilterWheelSnapshot(ndStop: nil, ndStopsExact: 6.6),
                    ]
                ),
            ]
        )
        let viewModel = makeViewModel(sessionStore: sessionStore, inventoryModel: FilterInventoryModel())
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 10)), .standard(NDStep(stops: 6.6))])
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)
    }

    func testStaleFilterSetAndItemReferencesRecoverSafely() throws {
        let sessionStore = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let unknownSet = FilterSetID.generate()
        sessionStore.stored = PersistentCameraSlotSessionSnapshot(
            schemaVersion: 1,
            activeSlotIDRaw: CameraSlotID.camera1.rawValue,
            slots: [
                PersistentCameraSlotCalculatorSnapshot(
                    slotIDRaw: CameraSlotID.camera1.rawValue,
                    selectedPresetFilmID: nil,
                    selectedProfileID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 2,
                    ndStack: [PersistentNDFilterWheelSnapshot(ndStop: 2)],
                    filterStack: [
                        PersistentFilterWheelSnapshot(sourceKind: "standard", ndStop: 2),
                        PersistentFilterWheelSnapshot(sourceKind: "filterSet", filterSetID: unknownSet.rawValue),
                        PersistentFilterWheelSnapshot(sourceKind: "filterSet", filterSetID: set.id.rawValue, itemID: "gone", rowKind: "fixed"),
                    ],
                    lastFilterSourceKind: "filterSet",
                    lastFilterSetID: unknownSet.rawValue
                ),
            ]
        )
        let viewModel = makeViewModel(sessionStore: sessionStore, inventoryModel: inventory)
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 2)), .empty(in: set.id)])
        XCTAssertEqual(viewModel.selectedFilterSource, .standard, "A vanished last source falls back to Standard.")
    }

    func testCorruptedMixedStackFallsBackToTheLegacyStandardPath() {
        let sessionStore = InMemoryMixedSessionStore()
        sessionStore.stored = PersistentCameraSlotSessionSnapshot(
            schemaVersion: 1,
            activeSlotIDRaw: CameraSlotID.camera1.rawValue,
            slots: [
                PersistentCameraSlotCalculatorSnapshot(
                    slotIDRaw: CameraSlotID.camera1.rawValue,
                    selectedPresetFilmID: nil,
                    selectedProfileID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 4,
                    ndStack: [PersistentNDFilterWheelSnapshot(ndStop: 4)],
                    // Off-ladder Standard wheel: structural corruption.
                    filterStack: [PersistentFilterWheelSnapshot(sourceKind: "standard", ndStop: 4, ndStopsExact: 4.4)]
                ),
            ]
        )
        let viewModel = makeViewModel(sessionStore: sessionStore, inventoryModel: FilterInventoryModel())
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 4))])
    }

    func testMalformedFilterStackDecodesAsAbsent() throws {
        let json = """
        {"slotIDRaw":"camera1","ndStop":5,"filterStack":"nope","lastFilterSourceKind":7}
        """
        let decoded = try JSONDecoder().decode(PersistentCameraSlotCalculatorSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.filterStack)
        XCTAssertNil(decoded.lastFilterSourceKind)
        XCTAssertEqual(decoded.ndStop, 5)
    }

    // MARK: Helpers

    private func makeViewModel(
        sessionStore: CameraSlotSessionPersistenceStoring,
        inventoryModel: FilterInventoryModel
    ) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: inventoryModel
        )
    }
}

final class InMemoryMixedSessionStore: CameraSlotSessionPersistenceStoring {
    var stored: PersistentCameraSlotSessionSnapshot?
    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { stored }
    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) { stored = snapshot }
    func clearSnapshot() { stored = nil }
}
