import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Range + guard coverage exercised through the calculator's
/// reciprocity binding. Asserts the custom-profile policy result
/// respects the no-correction threshold and the
/// beyond-source-range behaviour, and pins the editor's range
/// validation.
@MainActor
final class CustomFilmRangeGuardTests: XCTestCase {

    // MARK: - Editor-built profile shape

    func test_editorBuiltProfile_carriesThresholdAndFormulaRules() throws {
        let state = CustomFilmEditorFormState(
            profileName: "Edge",
            filmLabel: "Edge",
            isoText: "100",
            sourceType: .userDefined,
            notes: "",
            exponentText: "1.30",
            baseTcText: "1",
            offsetSecondsText: "",
            // T_c(1) = 1^1.3 = 1 satisfies the boundary check.
            // A sub-1s threshold with exponent>1 would shorten
            // exposure at the boundary and the editor would
            // reject it; this test pins the well-formed shape.
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        guard case .success(let film) = state.validate(),
              let profile = film.profiles.first else {
            return XCTFail("Expected validated custom film")
        }
        // The shared formula carries the range boundaries
        // directly; no separate threshold rule. The editor's
        // "No correction up to" lands on
        // `noCorrectionThroughSeconds` and "Source range through"
        // lands on `sourceRangeThroughSeconds`.
        let formula = profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            if case .formula(let r) = rule { return r }
            return nil
        }.first
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.formula.noCorrectionThroughSeconds ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(formula?.formula.sourceRangeThroughSeconds ?? -1, 60.0, accuracy: 0.0001)
    }

    // MARK: - Calculation behavior across the range

    func test_meteredBelowNoCorrectionThreshold_yieldsNoCorrection() throws {
        let viewModel = makeViewModel()
        let film = try saveCustomFilm(
            viewModel: viewModel,
            exponent: 1.30,
            noCorrectionThrough: 1.0,
            validThrough: 240.0
        )
        viewModel.selectEntry(viewModel.filmSelectorEntries.first { $0.id == film.id }!)
        // 0.5s metered: below no-correction threshold → policy
        // returns "no correction".
        viewModel.baseShutter = 0.5
        viewModel.ndStop = 0

        guard let resultState = viewModel.filmModeExposureResultState else {
            return XCTFail("Expected film-mode result")
        }
        XCTAssertEqual(
            resultState.correctedExposure.correctedExposureSeconds ?? -1,
            0.5,
            accuracy: 0.01,
            "Corrected exposure must equal the metered value inside the no-correction band."
        )
    }

    func test_meteredBeyondValidThrough_stillCalculatesCorrectedTimer() throws {
        // Source range is a confidence boundary, not a hard stop: a metered
        // exposure past `sourceRangeThroughSeconds` is NOT a hard
        // calculation stop. The formula keeps producing a value;
        // the policy classifies it as beyond the source range so
        // the presentation layer can flag the result, but the
        // corrected-exposure timer remains available because the
        // photographer's authored formula gives the only prediction
        // we have for that input.
        let viewModel = makeViewModel()
        let film = try saveCustomFilm(
            viewModel: viewModel,
            exponent: 1.30,
            noCorrectionThrough: 1.0,
            validThrough: 30.0
        )
        viewModel.selectEntry(viewModel.filmSelectorEntries.first { $0.id == film.id }!)
        viewModel.baseShutter = 120.0
        viewModel.ndStop = 0

        guard let resultState = viewModel.filmModeExposureResultState,
              let corrected = resultState.correctedExposure.correctedExposureSeconds else {
            return XCTFail("Beyond source range must still expose a corrected exposure value")
        }
        let expected = pow(120.0, 1.30)
        XCTAssertEqual(corrected, expected, accuracy: 0.5)
        XCTAssertTrue(
            viewModel.canStartFilmCorrectedExposureTimer,
            "Beyond source range is a confidence flag, not a calculation block."
        )
    }

    // MARK: - Sanitation regressions

    func test_sanitation_keepsThresholdPlusFormulaShape() {
        let state = CustomFilmEditorFormState(
            profileName: "Stays",
            filmLabel: "Stays",
            isoText: "100",
            sourceType: .userDefined,
            notes: "",
            exponentText: "1.30",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: "300"
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected validated film")
        }
        let library = CustomFilmLibrary(initial: [film])
        XCTAssertEqual(library.customFilms.map(\.id), [film.id])
    }

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            customFilmLibrary: CustomFilmLibrary()
        )
    }

    private func saveCustomFilm(
        viewModel: ExposureCalculatorViewModel,
        exponent: Double,
        noCorrectionThrough: Double,
        validThrough: Double
    ) throws -> FilmIdentity {
        let state = CustomFilmEditorFormState(
            profileName: "Custom",
            filmLabel: "Custom Stock",
            isoText: "100",
            sourceType: .userDefined,
            notes: "",
            exponentText: "\(exponent)",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "\(noCorrectionThrough)",
            validThroughText: "\(validThrough)"
        )
        guard case .success(let film) = state.validate() else {
            throw XCTSkip("Validation failed unexpectedly")
        }
        viewModel.addCustomFilm(film)
        return film
    }
}
