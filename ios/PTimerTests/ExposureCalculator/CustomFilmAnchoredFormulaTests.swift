import XCTest
@testable import PTimer

/// Covers the anchored
/// `Tc = baseTc · (Tm / baseTm)^exponent + offset` shape
/// expressed through the shared `ReciprocityFormula` model. The
/// editor's `Base Tm` maps to `referenceMeteredTimeSeconds`,
/// `Base Tc` to `coefficientSeconds`, and the range fields land
/// on `noCorrectionThroughSeconds` / `sourceRangeThroughSeconds`.
@MainActor
final class CustomFilmAnchoredFormulaTests: XCTestCase {

    // MARK: - Defaults

    func test_defaults_areOneOneZero() {
        let state = CustomFilmEditorFormState()
        XCTAssertEqual(state.baseTmText, "1")
        XCTAssertEqual(state.baseTcText, "1")
        XCTAssertEqual(state.offsetSecondsText, "")
    }

    func test_validate_defaultAnchors_storesUnitCoefficient() throws {
        let state = CustomFilmEditorFormState(
            profileName: "Default",
            filmLabel: "Default",
            isoText: "100",
            exponentText: "1.33",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard case .success(let film) = state.validate(),
              case .formula(let rule) = film.profiles.first?.rules.last else {
            return XCTFail("Expected validated film with a trailing formula rule")
        }
        // With baseTm = baseTc = 1, the shared formula encodes
        // exactly what the photographer typed.
        XCTAssertEqual(rule.formula.coefficientSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.referenceMeteredTimeSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.exponent, 1.33, accuracy: 0.0001)
        XCTAssertEqual(rule.formula.offsetSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.noCorrectionThroughSeconds, 1, accuracy: 1e-9)
        XCTAssertNil(rule.formula.sourceRangeThroughSeconds)
    }

    // MARK: - T-MAX 100 example from the spec

    func test_tmax100_anchorPair_persistsOnSharedFormula() throws {
        // Spec example:
        //   Base Tm = 0.1s, Base Tc = 0.1s, Exponent = 1.0966
        //   Display: Tc = 0.1 × (Tm / 0.1)^1.0966
        // Both anchors live directly on the formula — no derived
        // coefficient, no metadata side channel.
        let state = CustomFilmEditorFormState(
            profileName: "Personal T-MAX 100",
            filmLabel: "T-MAX 100",
            isoText: "100",
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            noCorrectionThroughText: "1",
            validThroughText: "",
            manufacturerText: "Kodak"
        )
        guard case .success(let film) = state.validate(),
              case .formula(let rule) = film.profiles.first?.rules.last else {
            return XCTFail("Expected validated film")
        }
        XCTAssertEqual(rule.formula.coefficientSeconds, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.referenceMeteredTimeSeconds, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.exponent, 1.0966, accuracy: 1e-6)
    }

    // MARK: - Round trip via from(film:)

    func test_fromFilm_readsAnchorsFromSharedFormula() throws {
        let formula = ReciprocityFormula(
            coefficientSeconds: 0.1,
            referenceMeteredTimeSeconds: 0.1,
            exponent: 1.0966,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "p",
            name: "Personal T-MAX 100",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            notes: [],
            userMetadata: UserEditableMetadata(
                customSourceType: .personalTest,
                customManufacturer: "Kodak"
            )
        )
        let film = FilmIdentity(
            id: "f",
            kind: .custom,
            canonicalStockName: "Kodak T-MAX 100",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customManufacturer: "Kodak")
        )

        let state = try XCTUnwrap(CustomFilmEditorFormState.from(film: film))
        XCTAssertEqual(state.baseTmText, "0.1")
        XCTAssertEqual(state.baseTcText, "0.1")
        XCTAssertEqual(state.exponentText, "1.0966")
        XCTAssertEqual(state.manufacturerText, "Kodak")
    }

    // MARK: - Preview presenter uses anchored math

    func test_previewPresenter_usesBaseTmAndBaseTc() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        // At Tm = 8s: Tc = 0.1 · (8 / 0.1)^1.0966 ≈ 0.1 · 80^1.0966 ≈ 12.66s.
        guard let row = CustomFilmEditorPreviewPresenter
            .rows(form: form, samples: [8])
            .first(where: { $0.meteredSeconds == 8 }) else {
            return XCTFail("Expected 8s row")
        }
        XCTAssertEqual(row.status, .formulaApplied)
        let expected = 0.1 * pow(8.0 / 0.1, 1.0966)
        XCTAssertEqual(row.correctedSeconds ?? -1, expected, accuracy: 0.05)
    }

    func test_previewPresenter_unlimitedValidThrough_doesNotEmitBeyondRangeRows() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(form: form)
        XCTAssertFalse(rows.contains { $0.status == .beyondSourceRange })
    }

    func test_previewPresenter_finiteValidThrough_emitsBeyondRangeRows() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            noCorrectionThroughText: "1",
            validThroughText: "30"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: [10, 60, 300]
        )
        // Samples past 30s (60s, 300s) become beyond-valid.
        XCTAssertTrue(rows.contains { $0.meteredSeconds == 60 && $0.status == .beyondSourceRange })
        XCTAssertTrue(rows.contains { $0.meteredSeconds == 300 && $0.status == .beyondSourceRange })
    }

    // MARK: - Calculation integration

    func test_selectedCustomFilm_calculatesUsingAnchorPair() throws {
        let state = CustomFilmEditorFormState(
            profileName: "T-MAX 100",
            filmLabel: "T-MAX 100",
            isoText: "100",
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            noCorrectionThroughText: "1",
            validThroughText: "",
            manufacturerText: "Kodak"
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected validated film")
        }
        let library = CustomFilmLibrary()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            customFilmLibrary: library
        )
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(viewModel.filmSelectorEntries.first { $0.id == film.id }!)
        viewModel.baseShutter = 8.0
        viewModel.ndStop = 0

        guard let resultState = viewModel.filmModeExposureResultState,
              let corrected = resultState.correctedExposure.correctedExposureSeconds else {
            return XCTFail("Expected quantified corrected exposure")
        }
        let expected = 0.1 * pow(8.0 / 0.1, 1.0966)
        XCTAssertEqual(corrected, expected, accuracy: 0.05)
    }

    func test_anchorRoundsTripThroughLibraryUpsert() throws {
        let state = CustomFilmEditorFormState(
            profileName: "Round-trip",
            filmLabel: "Round-trip",
            isoText: "100",
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected validated film")
        }
        let library = CustomFilmLibrary()
        library.add(film)
        guard let stored = library.customFilms.first,
              case .formula(let rule) = stored.profiles.first?.rules.first else {
            return XCTFail("Expected stored custom film with formula rule")
        }
        XCTAssertEqual(rule.formula.coefficientSeconds, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.referenceMeteredTimeSeconds, 0.1, accuracy: 1e-9)
    }
}
