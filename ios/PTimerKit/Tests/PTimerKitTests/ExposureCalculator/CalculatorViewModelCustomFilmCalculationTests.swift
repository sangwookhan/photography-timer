// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Integration coverage for the calculation path when a custom
/// power-law profile is selected. The existing
/// `ReciprocityCalculationPolicyEvaluator` already accepts any
/// authority — these tests pin the end-to-end flow so a future
/// change to the binding / presentation chain cannot silently
/// mask custom-profile predictions.
@MainActor
final class CustomFilmCalculationFlowTests: XCTestCase {

    // MARK: - Selection routes through the formula path

    func test_selectedCustomFilm_producesQuantifiedCorrectedExposure() {
        let viewModel = makeViewModel()
        let film = customFilm(exponent: 1.30, iso: 100)
        viewModel.addCustomFilm(film)
        let entry = entry(for: film.id, in: viewModel)
        viewModel.selectEntry(entry)

        // Drive the base shutter to a 5 s metered exposure (no ND
        // applied) so the formula evaluates inside its no-range
        // region: T_c = 5^1.30 ≈ 8.10 s.
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0

        guard let resultState = viewModel.filmModeExposureResultState else {
            return XCTFail("Expected film-mode result state for selected custom film")
        }
        XCTAssertTrue(resultState.hasQuantifiedCorrectedExposure)
        guard let correctedSeconds = resultState.correctedExposure.correctedExposureSeconds else {
            return XCTFail("Expected a quantified corrected exposure value")
        }

        let expected = pow(5.0, 1.30)
        XCTAssertEqual(correctedSeconds, expected, accuracy: 0.01)
    }

    func test_customProfile_correctedExposureExceedsAdjustedForPositiveExponent() {
        let viewModel = makeViewModel()
        let film = customFilm(exponent: 1.45, iso: 100)
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 10.0
        viewModel.ndStop = 0

        guard let resultState = viewModel.filmModeExposureResultState,
              let correctedSeconds = resultState.correctedExposure.correctedExposureSeconds else {
            return XCTFail("Expected quantified corrected exposure")
        }
        XCTAssertGreaterThan(
            correctedSeconds,
            resultState.adjustedShutterSeconds,
            "For a power-law formula with exponent > 1 the corrected exposure must exceed the metered exposure."
        )
    }

    func test_customProfile_correctedExposureScalesWithCoefficientAndOffset() {
        let viewModel = makeViewModel()
        let film = customFilm(
            exponent: 1.30,
            coefficient: 1.10,
            offsetSeconds: 0.5,
            iso: 100
        )
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0

        guard let resultState = viewModel.filmModeExposureResultState,
              let correctedSeconds = resultState.correctedExposure.correctedExposureSeconds else {
            return XCTFail("Expected quantified corrected exposure")
        }

        // T_c = 1.10 * 5^1.30 + 0.5 = ~9.41 s.
        let expected = 1.10 * pow(5.0, 1.30) + 0.5
        XCTAssertEqual(correctedSeconds, expected, accuracy: 0.01)
    }

    // MARK: - Presentation flags the source as custom, not official

    func test_customSelection_presentationUsesCustomShortLabel() {
        let viewModel = makeViewModel()
        let film = customFilm(exponent: 1.30, iso: 100)
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0

        guard let bindingState = viewModel.filmReciprocityBindingState else {
            return XCTFail("Expected a binding state for the selected custom film")
        }
        XCTAssertEqual(bindingState.profile.source.authority, .userDefined)
        let label = bindingState.presentation.shortLabel.lowercased()
        XCTAssertTrue(
            label.contains("custom"),
            "Custom profile presentation must carry a 'Custom' qualifier, got '\(bindingState.presentation.shortLabel)'."
        )
    }

    func test_customSelection_filmSelectionDisplayState_subtitleIsCustom() {
        let viewModel = makeViewModel()
        let film = customFilm(exponent: 1.30, iso: 100)
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))

        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, film.canonicalStockName)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.secondaryText, "Custom")
    }

    // MARK: - Preset regression

    func test_presetFilmCalculation_isUnaffectedByCustomLibraryUsage() throws {
        let viewModel = makeViewModel()
        let provia = try presetFilm(named: "Provia 100F", viewModel: viewModel)

        // Capture the preset's adjusted/corrected baseline before
        // any custom film is added.
        viewModel.selectPresetFilm(provia)
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0
        let baselineAdjusted = viewModel.filmModeExposureResultState?.adjustedShutterSeconds
        let baselineCorrected = viewModel.filmModeExposureResultState?
            .correctedExposure.correctedExposureSeconds

        // Add a custom film and switch away/back. The preset's
        // result for the same inputs must match the captured
        // baseline byte-for-byte.
        let custom = customFilm(exponent: 1.30, iso: 100)
        viewModel.addCustomFilm(custom)
        viewModel.selectEntry(entry(for: custom.id, in: viewModel))
        viewModel.selectPresetFilm(provia)
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0

        XCTAssertEqual(
            viewModel.filmModeExposureResultState?.adjustedShutterSeconds,
            baselineAdjusted
        )
        XCTAssertEqual(
            viewModel.filmModeExposureResultState?.correctedExposure.correctedExposureSeconds,
            baselineCorrected
        )
    }

    func test_presetFilmCalculation_neverShowsCustomAuthorityLabel() throws {
        let viewModel = makeViewModel()
        let provia = try presetFilm(named: "Provia 100F", viewModel: viewModel)
        viewModel.selectPresetFilm(provia)
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0

        guard let bindingState = viewModel.filmReciprocityBindingState else {
            return XCTFail("Expected a binding state for the Provia preset")
        }
        XCTAssertEqual(bindingState.profile.source.authority, .official)
        XCTAssertFalse(
            bindingState.presentation.shortLabel.lowercased().contains("custom"),
            "Preset short label must not contain 'Custom'."
        )
    }

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            customFilmLibrary: CustomFilmLibrary()
        )
    }

    private func entry(for filmID: String, in viewModel: ExposureCalculatorViewModel) -> FilmSelectorEntry {
        guard let entry = viewModel.filmSelectorEntries.first(where: { $0.id == filmID }) else {
            preconditionFailure("Selector entry not built for film id \(filmID)")
        }
        return entry
    }

    private func customFilm(
        exponent: Double,
        coefficient: Double? = nil,
        offsetSeconds: Double? = nil,
        iso: Int
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(
            coefficientSeconds: coefficient ?? 1,
            referenceMeteredTimeSeconds: 1,
            exponent: exponent,
            offsetSeconds: offsetSeconds ?? 0,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "custom-profile-\(UUID().uuidString)",
            name: "Custom",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            notes: [],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest),
            sourceEvidence: []
        )
        return FilmIdentity(
            id: "custom-film-\(UUID().uuidString)",
            kind: .custom,
            canonicalStockName: "Custom Stock",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: iso,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest)
        )
    }

    private func presetFilm(
        named stockName: String,
        viewModel: ExposureCalculatorViewModel
    ) throws -> FilmIdentity {
        guard let film = viewModel.availablePresetFilms.first(where: {
            $0.canonicalStockName == stockName
        }) else {
            throw XCTSkip("Preset film '\(stockName)' is not in the launch catalog")
        }
        return film
    }
}
