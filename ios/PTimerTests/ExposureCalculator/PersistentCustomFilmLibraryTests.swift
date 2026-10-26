// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Save / reload coverage for the concrete production
/// `UserDefaultsCustomFilmLibraryStore` (against an isolated
/// `UserDefaults(suiteName:)`). These stay app-hosted because the
/// concrete store lives in the app target; the injected in-memory /
/// library-rule round-trips moved off-simulator to
/// `CustomFilmLibraryReloadTests` in PTimerKitTests.
@MainActor
final class PersistentCustomFilmLibraryTests: XCTestCase {

    private func predecessorFixtureData(named name: String) throws -> Data {
        var repositoryRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            repositoryRoot.deleteLastPathComponent()
        }
        let fixtureURL = repositoryRoot
            .appendingPathComponent("shared/test-fixtures/PTIMER-243/ios/predecessor-1.1.2", isDirectory: true)
            .appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
    }

    func test_malformedPayload_failsSafeToEmptyLibrary() {
        let suiteName = "ptimer.tests.custom-film-library.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create suite UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Plant a malformed payload directly so the next load hits
        // the decoder's failure branch. The store must swallow the
        // error and surface an empty library, not crash.
        let key = "ptimer.exposure-calculator.custom-films.snapshot"
        defaults.set(Data("not-json".utf8), forKey: key)

        let store = UserDefaultsCustomFilmLibraryStore(
            userDefaults: defaults,
            snapshotKey: key
        )
        let library = CustomFilmLibrary(store: store)

        XCTAssertTrue(library.isEmpty)

        // After a successful save, subsequent loads should now
        // succeed — the malformed bytes have been replaced.
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "recovered", stockName: "Recovered"))
        let reloaded = CustomFilmLibrary(store: store)
        XCTAssertEqual(reloaded.customFilms.map(\.id), ["recovered"])
    }

    func test_userDefaultsStore_persistsAcrossDistinctInstances() {
        let suiteName = "ptimer.tests.custom-film-library.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create suite UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storeKey = "ptimer.exposure-calculator.custom-films.snapshot"
        let firstStore = UserDefaultsCustomFilmLibraryStore(
            userDefaults: defaults,
            snapshotKey: storeKey
        )
        let firstLibrary = CustomFilmLibrary(store: firstStore)
        firstLibrary.add(CustomFilmTestSupport.makeCustomFilm(id: "persisted", stockName: "P"))

        // A new store instance with the same UserDefaults must
        // observe the persisted payload — same backing storage.
        let secondStore = UserDefaultsCustomFilmLibraryStore(
            userDefaults: defaults,
            snapshotKey: storeKey
        )
        let secondLibrary = CustomFilmLibrary(store: secondStore)
        XCTAssertEqual(secondLibrary.customFilms.map(\.id), ["persisted"])
    }

    func test_presetCatalogStoreKey_isDistinctFromCustomLibraryKey() {
        // Custom library writes under a dedicated UserDefaults key,
        // separate from `ptimer.exposure-calculator.context.snapshot`
        // / the camera-slot session key, so clearing the custom
        // library cannot stomp other persisted surfaces.
        let suiteName = "ptimer.tests.custom-film-library.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create suite UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Plant a sentinel under the calculator-context key.
        let calculatorContextKey = "ptimer.exposure-calculator.context.snapshot"
        defaults.set(Data("preset-sentinel".utf8), forKey: calculatorContextKey)

        let store = UserDefaultsCustomFilmLibraryStore(userDefaults: defaults)
        let library = CustomFilmLibrary(store: store)
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "custom", stockName: "Custom"))

        XCTAssertEqual(
            defaults.data(forKey: calculatorContextKey),
            Data("preset-sentinel".utf8),
            "The custom-film library writer must not overwrite unrelated persistence keys."
        )
    }

    func test_PTIMER243_predecessorStoresRestoreAndEditorSavePreservesLinkedFormula() throws {
        let suiteName = "ptimer.tests.PTIMER243.predecessor.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let customKey = "ptimer.tests.PTIMER243.custom-films"
        let managedCameraKey = "ptimer.tests.PTIMER243.managed-cameras"
        let timerStateKey = "ptimer.tests.PTIMER243.timer-state"
        let timerMetadataKey = "ptimer.tests.PTIMER243.timer-metadata"
        let customData = try predecessorFixtureData(named: "custom-film-library.json")
        let cameraData = try predecessorFixtureData(named: "managed-camera-list.json")
        let timerData = try predecessorFixtureData(named: "timer-state.json")
        let metadataData = try predecessorFixtureData(named: "timer-metadata.json")
        userDefaults.set(customData, forKey: customKey)
        userDefaults.set(cameraData, forKey: managedCameraKey)
        userDefaults.set(timerData, forKey: timerStateKey)
        userDefaults.set(metadataData, forKey: timerMetadataKey)

        let rawLibrary = try XCTUnwrap(JSONSerialization.jsonObject(with: customData) as? [String: Any])
        let rawFilms = try XCTUnwrap(rawLibrary["films"] as? [[String: Any]])
        XCTAssertEqual(rawFilms.count, 3)
        for film in rawFilms {
            XCTAssertNil(film["polarity"], "The predecessor payload must keep the classification keys absent.")
            XCTAssertNil(film["color"], "The predecessor payload must keep the classification keys absent.")
        }

        let libraryStore = UserDefaultsCustomFilmLibraryStore(userDefaults: userDefaults, snapshotKey: customKey)
        let library = CustomFilmLibrary(store: libraryStore)
        XCTAssertEqual(library.customFilms.map(\.id), [
            "ios-legacy-formula",
            "ios-legacy-table",
            "ios-legacy-linked-formula",
        ])

        let legacyFormula = try XCTUnwrap(library.film(withID: "ios-legacy-formula"))
        XCTAssertEqual(legacyFormula.polarity, .negative)
        XCTAssertEqual(legacyFormula.color, .blackAndWhite)
        let formulaProfile = try XCTUnwrap(legacyFormula.profiles.first)
        XCTAssertEqual(formulaProfile.id, "ios-legacy-formula-profile")
        XCTAssertEqual(formulaProfile.source.kind, .userDefined)
        XCTAssertEqual(formulaProfile.source.authority, .userDefined)
        let formulaRule = try XCTUnwrap(formulaProfile.rules.first)
        guard case let .formula(formulaPayload) = formulaRule else {
            return XCTFail("Expected predecessor Formula profile")
        }
        XCTAssertEqual(formulaPayload.formula.formulaFamily, .modifiedSchwarzschild)
        XCTAssertEqual(formulaPayload.formula.coefficientSeconds, 1)
        XCTAssertEqual(formulaPayload.formula.referenceMeteredTimeSeconds, 1)
        XCTAssertEqual(formulaPayload.formula.exponent, 1.3)
        XCTAssertEqual(formulaPayload.formula.offsetSeconds, 0)
        XCTAssertEqual(formulaPayload.formula.noCorrectionThroughSeconds, 1)
        XCTAssertNil(formulaPayload.formula.sourceRangeThroughSeconds)

        let legacyTable = try XCTUnwrap(library.film(withID: "ios-legacy-table"))
        XCTAssertEqual(legacyTable.polarity, .negative)
        XCTAssertEqual(legacyTable.color, .blackAndWhite)
        let tableProfile = try XCTUnwrap(legacyTable.profiles.first)
        XCTAssertEqual(tableProfile.id, "ios-legacy-table-profile")
        XCTAssertEqual(tableProfile.source.kind, .userDefined)
        XCTAssertEqual(tableProfile.source.authority, .userDefined)
        let tableRuleValue = try XCTUnwrap(tableProfile.rules.first)
        guard case let .tableInterpolation(tableRule) = tableRuleValue else {
            return XCTFail("Expected predecessor Table profile")
        }
        XCTAssertEqual(tableRule.anchors.map(\.meteredSeconds), [1, 10, 100])
        XCTAssertEqual(tableRule.anchors.map(\.correctedSeconds), [2, 80, 600])
        XCTAssertEqual(tableRule.noCorrectionThroughSeconds, 0.5)
        XCTAssertEqual(tableRule.sourceRangeThroughSeconds, 100)

        let linkedFormula = try XCTUnwrap(library.film(withID: "ios-legacy-linked-formula"))
        XCTAssertEqual(linkedFormula.polarity, .negative)
        XCTAssertEqual(linkedFormula.color, .blackAndWhite)
        XCTAssertEqual(linkedFormula.userMetadata?.referenceTableFilmID, legacyTable.id)
        let linkedProfile = try XCTUnwrap(linkedFormula.profiles.first)
        XCTAssertEqual(linkedProfile.id, "ios-legacy-linked-formula")
        XCTAssertEqual(linkedProfile.source.kind, .userDefined)
        XCTAssertEqual(linkedProfile.source.authority, .userDefined)
        let linkedRuleValue = try XCTUnwrap(linkedProfile.rules.first)
        guard case let .formula(linkedFormulaPayload) = linkedRuleValue else {
            return XCTFail("Expected predecessor Table-derived Formula profile")
        }
        XCTAssertEqual(linkedFormulaPayload.formula.coefficientSeconds, 2.6436)
        XCTAssertEqual(linkedFormulaPayload.formula.referenceMeteredTimeSeconds, 1)
        XCTAssertEqual(linkedFormulaPayload.formula.exponent, 1.2386)
        XCTAssertEqual(linkedFormulaPayload.formula.offsetSeconds, 0)
        XCTAssertEqual(linkedFormulaPayload.formula.noCorrectionThroughSeconds, 0.5)
        XCTAssertEqual(linkedFormulaPayload.formula.sourceRangeThroughSeconds, 100)

        let cameraStore = UserDefaultsCameraSlotSessionStore(userDefaults: userDefaults, managedKey: managedCameraKey)
        guard case let .loaded(cameraSnapshot) = cameraStore.loadManagedList() else {
            return XCTFail("Expected predecessor managed camera list")
        }
        XCTAssertEqual(cameraSnapshot.activeCameraIDRaw, "camera2")
        let camera1 = try XCTUnwrap(cameraSnapshot.cameras.first { $0.idRaw == "camera1" }?.calculator)
        XCTAssertEqual(camera1.selectedPresetFilmID, legacyTable.id)
        XCTAssertEqual(camera1.selectedProfileID, tableProfile.id)
        XCTAssertEqual(camera1.baseShutterSeconds, 10)
        let camera2 = try XCTUnwrap(cameraSnapshot.cameras.first { $0.idRaw == "camera2" }?.calculator)
        XCTAssertEqual(camera2.selectedPresetFilmID, linkedFormula.id)
        XCTAssertEqual(camera2.selectedProfileID, linkedProfile.id)
        XCTAssertEqual(camera2.baseShutterSeconds, 30)

        let metadataStore = UserDefaultsTimerMetadataStore(userDefaults: userDefaults, snapshotKey: timerMetadataKey)
        let metadata = try XCTUnwrap(metadataStore.loadSnapshot())
        let metadataByID = Dictionary(uniqueKeysWithValues: metadata.timers.map { ($0.id, $0) })
        let runningID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let pausedID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let completedID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        XCTAssertEqual(metadataByID[runningID]?.name, "Legacy running")
        XCTAssertEqual(metadataByID[runningID]?.basisSummary, "Camera 2 · Legacy Table Formula")
        XCTAssertEqual(metadataByID[runningID]?.cameraSlotIDRaw, "camera2")
        XCTAssertEqual(metadataByID[runningID]?.filmDisplayName, "Legacy Table Formula")
        XCTAssertEqual(metadataByID[pausedID]?.cameraSlotIDRaw, "camera1")
        XCTAssertEqual(metadataByID[pausedID]?.filmDisplayName, "Legacy Table")
        XCTAssertEqual(metadataByID[completedID]?.cameraSlotIDRaw, "camera1")
        XCTAssertEqual(metadataByID[completedID]?.filmDisplayName, "Legacy Table")

        var currentDate = Date(timeIntervalSinceReferenceDate: 814_728_000)
        let timerStore = UserDefaultsTimerPersistenceStore(userDefaults: userDefaults, snapshotKey: timerStateKey)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: timerStore
        )
        let running = try XCTUnwrap(timerManager.timers.first { $0.id == runningID })
        XCTAssertEqual(running.status(at: currentDate), .running)
        XCTAssertEqual(running.duration, 3600)
        XCTAssertEqual(running.startDate, Date(timeIntervalSinceReferenceDate: 814_727_876.481561))
        XCTAssertEqual(running.endDate, Date(timeIntervalSinceReferenceDate: 814_731_476.481561))
        XCTAssertEqual(running.remainingTime(at: currentDate), 3476.481561, accuracy: 0.000001)
        let paused = try XCTUnwrap(timerManager.timers.first { $0.id == pausedID })
        XCTAssertEqual(paused.status(at: currentDate), .paused)
        XCTAssertEqual(paused.duration, 180)
        XCTAssertEqual(paused.pausedRemainingTime, 120)
        XCTAssertEqual(paused.pausedAt, Date(timeIntervalSinceReferenceDate: 814_727_876.481561))
        let completed = try XCTUnwrap(timerManager.timers.first { $0.id == completedID })
        XCTAssertEqual(completed.status(at: currentDate), .completed)
        XCTAssertEqual(completed.duration, 60)
        XCTAssertEqual(completed.endDate, Date(timeIntervalSinceReferenceDate: 814_727_816.481561))

        currentDate = Date(timeIntervalSinceReferenceDate: 814_731_477)
        timerManager.tick(now: currentDate)
        let completedRunningTimer = try XCTUnwrap(timerManager.timers.first { $0.id == runningID })
        XCTAssertEqual(completedRunningTimer.status(at: currentDate), .completed)
        XCTAssertEqual(completedRunningTimer.remainingTime(at: currentDate), 0)
        let stillPaused = try XCTUnwrap(timerManager.timers.first { $0.id == pausedID })
        XCTAssertEqual(stillPaused.status(at: currentDate), .paused)
        XCTAssertEqual(stillPaused.remainingTime(at: currentDate), 120)

        var editState = try XCTUnwrap(CustomFilmEditorFormState.from(film: linkedFormula))
        XCTAssertEqual(editState.polarity, .negative)
        XCTAssertEqual(editState.color, .blackAndWhite)
        XCTAssertEqual(editState.referenceTableFilmID, legacyTable.id)
        editState.polarity = .positive
        editState.color = .color
        var stableIDs = [linkedProfile.id, linkedFormula.id]
        let editedFormula = try editState.validate(idGenerator: { stableIDs.removeFirst() }).get()
        library.add(editedFormula)

        let reopenedLibrary = CustomFilmLibrary(
            store: UserDefaultsCustomFilmLibraryStore(userDefaults: userDefaults, snapshotKey: customKey)
        )
        XCTAssertEqual(reopenedLibrary.customFilms.map(\.id), library.customFilms.map(\.id))
        let restoredLinkedFormula = try XCTUnwrap(reopenedLibrary.film(withID: linkedFormula.id))
        XCTAssertEqual(restoredLinkedFormula.polarity, .positive)
        XCTAssertEqual(restoredLinkedFormula.color, .color)
        XCTAssertEqual(restoredLinkedFormula.profiles.first?.id, linkedProfile.id)
        XCTAssertEqual(restoredLinkedFormula.userMetadata?.referenceTableFilmID, legacyTable.id)
        let restoredLinkedRuleValue = try XCTUnwrap(restoredLinkedFormula.profiles.first?.rules.first)
        guard case let .formula(restoredLinkedRule) = restoredLinkedRuleValue else {
            return XCTFail("Expected linked Formula after editor/model save")
        }
        XCTAssertEqual(restoredLinkedRule.formula.coefficientSeconds, 2.6436)
        XCTAssertEqual(restoredLinkedRule.formula.referenceMeteredTimeSeconds, 1)
        XCTAssertEqual(restoredLinkedRule.formula.exponent, 1.2386)
        XCTAssertEqual(restoredLinkedRule.formula.noCorrectionThroughSeconds, 0.5)
        XCTAssertEqual(restoredLinkedRule.formula.sourceRangeThroughSeconds, 100)
        let unchangedTable = try XCTUnwrap(reopenedLibrary.film(withID: legacyTable.id))
        XCTAssertEqual(unchangedTable.polarity, .negative)
        XCTAssertEqual(unchangedTable.color, .blackAndWhite)
        XCTAssertEqual(unchangedTable.profiles.first?.id, tableProfile.id)
    }
}
