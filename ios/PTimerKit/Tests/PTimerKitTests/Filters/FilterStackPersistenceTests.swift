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
    /// The self-cleaning timer is the only cleanup path
    /// (FILTER-STACK-006) — there is no on-demand command. Tests
    /// shorten `ndWheelCleanupDelay` when they build the view model
    /// and then wait here for one fire. The window also covers the
    /// reshaping animation, which the fire-time judgment waits out.
    private func awaitCleanupFire() async {
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

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
        // Settled order (FILTER-STACK-005): Lee (10 + registered 3) leads
        // Standard 6.6; the persisted order restores as is.
        XCTAssertEqual(restored.filterWheels, [
            FilterWheel(source: .filterSet(set.id), selection: select(item)),
            FilterWheel(source: .filterSet(set.id), selection: select(gnd, .gnd(.recordOnly))),
            .standard(NDStep(stops: 6.6)),
        ])
        XCTAssertEqual(restored.ndStep.stops, 16.6, accuracy: 1e-9)
        XCTAssertEqual(restored.ndFilterSteps[0].stops, 10, "ND1000 restores as exactly 10 stops.")
        XCTAssertEqual(restored.selectedFilterSource, .filterSet(set.id))
    }

    func testDowngradeFieldsCarryStandardWheelsOnly() async throws {
        let sessionStore = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = FilterItem(name: "X", behavior: .fixed(FilterRegisteredValue(value: 12, unit: .stops)))
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(sessionStore: sessionStore, inventoryModel: inventory)
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.setNDFilterStep(NDStep(stops: 3), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)

        let slot = try XCTUnwrap(sessionStore.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(slot.ndStack?.compactMap(\.ndStop), [3], "ndStack lists Standard wheels only.")
        XCTAssertEqual(slot.ndStop, 3, "The legacy scalar is the strongest Standard wheel.")
        XCTAssertEqual(slot.filterStack?.count, 2)
        XCTAssertEqual(slot.filterStack?[0].itemID, item.id.rawValue, "The set group (12) leads Standard 3.")
        XCTAssertEqual(slot.lastFilterSourceKind, "filterSet")
        XCTAssertEqual(slot.lastFilterSetID, set.id.rawValue)

        // A stack with no Standard wheel still degrades to one valid
        // Standard 0 wheel for older builds.
        await awaitCleanupFire()
        viewModel.setWheelSelection(.standard(NDStep(stops: 0)), at: 1)
        // [item 12, standard 0] keeps the set group first; clean the zero.
        await awaitCleanupFire()
        let onlyItem = try XCTUnwrap(sessionStore.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(onlyItem.filterStack?.count, 1)
        XCTAssertEqual(onlyItem.ndStack?.compactMap(\.ndStop), [0])
        XCTAssertEqual(onlyItem.ndStop, 0)
    }

    // MARK: FILTER-STACK-005 — a group reorder keeps identity, sum, and persistence

    func testGroupReorderPreservesWheelIdentitySelectionTotalCameraIndependenceAndPersistence() throws {
        let sessionStore = InMemoryMixedSessionStore()
        let inventoryStore = InMemoryFilterInventoryStore()
        let inventory = FilterInventoryModel(store: inventoryStore)
        let nisi = try XCTUnwrap(inventory.createFilterSet(name: "NiSi", color: .red))
        let lee = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .green))
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        let nd8 = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        inventory.addItem(nd1000, to: nisi.id)
        inventory.addItem(nd8, to: lee.id)
        inventory.addItem(cpl, to: lee.id)

        let viewModel = makeViewModel(sessionStore: sessionStore, inventoryModel: inventory)
        viewModel.setNDFilterStep(NDStep(stops: 2), at: 0)
        let standardID = viewModel.ndFilterWheelIDs[0]
        viewModel.selectFilterSource(.filterSet(lee.id))
        viewModel.addFilterWheel()
        let nd8ID = viewModel.ndFilterWheelIDs[1]
        viewModel.setWheelSelection(select(nd8), at: 1)
        // Lee (3) leads Standard (2).
        XCTAssertEqual(viewModel.ndFilterWheelIDs, [nd8ID, standardID])
        viewModel.addFilterWheel()
        let cplID = viewModel.ndFilterWheelIDs[2]
        viewModel.setWheelSelection(select(cpl, .cplLoss(1)), at: 2)
        // Lee (3 + 1) stays contiguous ahead of Standard (2); CPL after ND8.
        XCTAssertEqual(viewModel.ndFilterWheelIDs, [nd8ID, cplID, standardID])

        viewModel.selectFilterSource(.filterSet(nisi.id))
        viewModel.addFilterWheel()
        let nisiID = viewModel.ndFilterWheelIDs[3]
        viewModel.setWheelSelection(select(nd1000), at: 3)

        // NiSi (10) > Lee (4) > Standard (2): identity follows the wheel.
        XCTAssertEqual(viewModel.ndFilterWheelIDs, [nisiID, nd8ID, cplID, standardID])
        XCTAssertEqual(viewModel.filterWheels.map(\.source), [.filterSet(nisi.id), .filterSet(lee.id), .filterSet(lee.id), .standard])
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(nd1000), select(nd8), select(cpl, .cplLoss(1)), .standard(NDStep(stops: 2))])
        XCTAssertEqual(viewModel.ndStep.stops, 16, accuracy: 1e-9)
        XCTAssertFalse(viewModel.canRemoveEmptyFilterWheel, "No cleanable wheel appeared through sorting.")

        // Another camera is untouched.
        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])
        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.ndFilterWheelIDs.count, 4)
        XCTAssertEqual(viewModel.filterWheels.map(\.source), [.filterSet(nisi.id), .filterSet(lee.id), .filterSet(lee.id), .standard])

        // The settled order is what persists and restores.
        let slot = try XCTUnwrap(sessionStore.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(slot.filterStack?.map(\.itemID), [nd1000.id.rawValue, nd8.id.rawValue, cpl.id.rawValue, nil])
        let restored = makeViewModel(sessionStore: sessionStore, inventoryModel: FilterInventoryModel(store: inventoryStore))
        XCTAssertEqual(restored.filterWheels, viewModel.filterWheels)
        XCTAssertEqual(restored.ndStep.stops, 16, accuracy: 1e-9)
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
