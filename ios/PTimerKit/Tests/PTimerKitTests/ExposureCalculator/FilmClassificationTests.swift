// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
import PTimerCore
import PTimerKit

final class FilmClassificationTests: XCTestCase {
    @MainActor
    func testReciprocityDetailsIdentityLineShowsAllFourClassificationsAndISO() throws {
        let viewModel = makeFilmModeViewModel()
        for polarity in FilmPolarity.allCases {
            for color in FilmColor.allCases {
                var form = makeForm(table: false)
                form.polarity = polarity
                form.color = color
                let film = try save(form, id: "\(polarity.rawValue)-\(color.rawValue)")
                viewModel.addCustomFilm(film)
                viewModel.selectPresetFilm(film)

                let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
                let colorLabel = color == .color ? "film-color-value" : "Black & White"
                let polarityLabel = String(localized: polarity == .positive ? "Positive" : "Negative")
                XCTAssertEqual(details.classificationAndISO, "\(colorLabel) \(polarityLabel) · ISO 100")
                XCTAssertTrue(details.subtitle?.contains(film.canonicalStockName) == true)
            }
        }
    }

    func testFourCombinationsSaveReopenAndRestoreForBothKinds() throws {
        for table in [false, true] {
            for polarity in FilmPolarity.allCases {
                for color in FilmColor.allCases {
                    var form = makeForm(table: table)
                    form.polarity = polarity
                    form.color = color
                    let film = try save(form)
                    let data = try JSONEncoder().encode(PersistentCustomFilmLibrarySnapshot(films: [film]))
                    let restored = PersistentCustomFilmLibrarySnapshot.decode(from: data)
                    XCTAssertEqual(restored.outcome, .loaded)
                    XCTAssertEqual(restored.snapshot.films, [film])
                    let reopened = try XCTUnwrap(CustomFilmEditorFormState.from(film: restored.snapshot.films[0]))
                    XCTAssertEqual(reopened.polarity, polarity)
                    XCTAssertEqual(reopened.color, color)
                    XCTAssertEqual(try save(reopened), film)
                    var edited = reopened
                    edited.polarity = polarity == .positive ? .negative : .positive
                    XCTAssertEqual(try save(edited).color, color)
                    edited = reopened
                    edited.color = color == .color ? .blackAndWhite : .color
                    XCTAssertEqual(try save(edited).polarity, polarity)
                    XCTAssertEqual(try save(reopened), film, "A discarded working copy cannot mutate saved data")
                }
            }
        }
    }

    func testLegacyMissingFieldsFallbackIndependentlyPreservingEveryOtherField() throws {
        for table in [false, true] {
            var form = makeForm(table: table)
            form.polarity = .positive
            form.color = .color
            let original = try save(form)
            let encoded = try JSONEncoder().encode(original)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            for missing in [["polarity"], ["color"], ["polarity", "color"]] {
                var legacy = object
                for key in missing { legacy.removeValue(forKey: key) }
                let data = try JSONSerialization.data(withJSONObject: ["films": [legacy]])
                let result = PersistentCustomFilmLibrarySnapshot.decode(from: data)
                XCTAssertEqual(result.outcome, .loaded)
                let film = try XCTUnwrap(result.snapshot.films.first)
                XCTAssertEqual(film.polarity, missing.contains("polarity") ? .negative : .positive)
                XCTAssertEqual(film.color, missing.contains("color") ? .blackAndWhite : .color)
                var roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(film)) as? [String: Any])
                roundTrip.removeValue(forKey: "polarity")
                roundTrip.removeValue(forKey: "color")
                var expected = object
                expected.removeValue(forKey: "polarity")
                expected.removeValue(forKey: "color")
                XCTAssertEqual(NSDictionary(dictionary: roundTrip), NSDictionary(dictionary: expected))
                XCTAssertEqual(try JSONDecoder().decode(FilmIdentity.self, from: JSONEncoder().encode(film)), film)
            }
        }
    }

    func testUnknownAndNullValuesDropOnlyTheirRecord() throws {
        let film = try save(makeForm(table: false))
        let good = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(film)) as? [String: Any])
        for key in ["polarity", "color"] {
            for invalid in ["future" as Any, NSNull()] {
                var bad = good
                bad["id"] = "bad"
                bad[key] = invalid
                let data = try JSONSerialization.data(withJSONObject: ["films": [bad, good]])
                let result = PersistentCustomFilmLibrarySnapshot.decode(from: data)
                XCTAssertEqual(result.outcome, .degraded)
                XCTAssertEqual(result.droppedRecordCount, 1)
                XCTAssertEqual(result.snapshot.films, [film])
            }
        }
    }

    func testDefaultsSwitchValidationAndFormulaRecoveryPreserveChoices() throws {
        let fresh = CustomFilmEditorFormState()
        XCTAssertEqual(fresh.polarity, .negative)
        XCTAssertEqual(fresh.color, .blackAndWhite)
        var form = makeForm(table: false)
        form.polarity = .positive
        form.color = .color
        let opening = form.formulaSnapshot
        form = form.switching(toCalculationKind: .table).switching(toCalculationKind: .formula)
        form.isoText = "invalid"
        if case .success = form.validate() { XCTFail("Invalid ISO must fail") }
        form.isoText = "100"
        form = form.applyingFormulaSnapshot(CustomFilmEditorFormState.resetDefaultsFormulaSnapshot)
        form = form.applyingFormulaSnapshot(opening)
        XCTAssertEqual(try save(form).polarity, .positive)
        XCTAssertEqual(try save(form).color, .color)
    }

    @MainActor
    func testTableFormulaInheritanceAndIndependentEditsAndDeletion() throws {
        var form = makeForm(table: true)
        form.polarity = .positive
        form.color = .color
        let table = try save(form)
        var seed = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))
        XCTAssertEqual(seed.polarity, .positive)
        XCTAssertEqual(seed.color, .color)
        seed.color = .blackAndWhite
        let formula = try save(seed, id: "derived")
        XCTAssertEqual(formula.userMetadata?.referenceTableFilmID, table.id)
        let library = CustomFilmLibrary(initial: [table, formula])
        library.remove(id: table.id)
        XCTAssertEqual(library.film(withID: formula.id), formula)
        XCTAssertEqual(table.color, .color)
        XCTAssertEqual(formula.color, .blackAndWhite)
    }

    @MainActor
    func testClassificationEditPreservesCamerasResultsAndCapturedTimers() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let manager = RuntimeBackedTimerManaging(dateProvider: { now })
        let vm = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: manager)
        let original = try save(makeForm(table: false))
        vm.addCustomFilm(original)
        vm.selectCameraSlot(.camera2)
        vm.selectPresetFilm(original)
        vm.selectCameraSlot(.camera1)
        vm.selectPresetFilm(original)
        vm.baseShutter = 2
        vm.startFilmCorrectedExposureTimer()
        now = now.addingTimeInterval(10)
        manager.tick(now: now)
        vm.baseShutter = 20
        vm.startFilmCorrectedExposureTimer()
        let pausedID = try XCTUnwrap(vm.timers.first { $0.status == .running }?.id)
        vm.pauseTimer(id: pausedID)
        vm.startFilmCorrectedExposureTimer()
        let timers = vm.timers
        XCTAssertTrue(timers.contains { $0.status == .completed })
        XCTAssertTrue(timers.contains { $0.status == .paused })
        XCTAssertTrue(timers.contains { $0.status == .running })
        let result = vm.filmModePrimaryResultSeconds
        let eligible = vm.canStartFilmCorrectedExposureTimer
        var edited = try XCTUnwrap(CustomFilmEditorFormState.from(film: original))
        edited.polarity = .positive
        edited.color = .color
        vm.addCustomFilm(try save(edited))
        XCTAssertEqual(vm.selectedPresetFilm?.id, original.id)
        XCTAssertEqual(vm.cameraSlotPageState(for: .camera2).selectedFilm?.id, original.id)
        XCTAssertEqual(vm.selectedPresetFilm?.polarity, .positive)
        XCTAssertEqual(vm.filmModePrimaryResultSeconds, result)
        XCTAssertEqual(vm.canStartFilmCorrectedExposureTimer, eligible)
        XCTAssertEqual(vm.timers, timers)
        vm.selectCameraSlot(.camera2)
        XCTAssertEqual(vm.selectedPresetFilm?.id, original.id)
        XCTAssertEqual(vm.selectedPresetFilm?.color, .color)
    }

    @MainActor
    func testPresetIdentityRetainsClassificationAcrossEveryPrimaryAndAlternate() {
        let vm = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: FakeTimerManaging())
        for film in LaunchPresetFilmCatalogV2.films {
            vm.selectPresetFilm(film)
            for profile in film.profiles + AlternateReciprocityModels.alternates(forFilmID: film.id) {
                vm.selectProfileVariant(profileID: profile.id)
                XCTAssertEqual(vm.selectedPresetFilm, film)
            }
        }
        vm.clearSelectedPresetFilm()
        XCTAssertNil(vm.selectedPresetFilm)
    }

    private func makeForm(table: Bool) -> CustomFilmEditorFormState {
        var form = CustomFilmEditorFormState(
            filmLabel: "Classification", isoText: "100", sourceType: .personalTest,
            notes: "Keep notes", exponentText: "1.3", manufacturerText: "Acme",
            referenceURLText: "https://example.com/source", referenceTableFilmID: table ? nil : "reference"
        )
        if table {
            form = form.switching(toCalculationKind: .table)
            form.tableRows = [
                CustomFilmTableAnchorRowInput(meteredText: "1", correctedText: "2"),
                CustomFilmTableAnchorRowInput(meteredText: "10", correctedText: "40"),
            ]
        }
        return form
    }

    private func save(_ form: CustomFilmEditorFormState, id: String = "film") throws -> FilmIdentity {
        guard case let .success(film) = form.validate(idGenerator: { id }) else {
            throw NSError(domain: "Invalid classification fixture", code: 1)
        }
        return film
    }
}
