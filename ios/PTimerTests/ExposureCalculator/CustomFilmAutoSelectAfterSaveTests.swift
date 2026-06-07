import XCTest
import PTimerCore
@testable import PTimer

/// PTIMER-84 selector-flow behaviors:
///   * New custom film save flow auto-selects the saved film
///   * Edit-save of the currently selected custom film preserves
///     the selection and refreshes the in-memory identity
///   * Saving an unrelated edit does not change the active
///     selection
@MainActor
final class CustomFilmAutoSelectAfterSaveTests: XCTestCase {

    func test_newCustomFilmFlow_addThenSelect_marksFilmAsSelected() {
        let viewModel = makeViewModel()
        let film = makeCustomFilm(id: "fresh-1", stockName: "Fresh One")

        // Replays the screen's onSave block for the New-custom flow:
        // add then immediately auto-select.
        viewModel.addCustomFilm(film)
        viewModel.selectPresetFilm(film)

        XCTAssertEqual(viewModel.selectedSelectorEntryID, "fresh-1")
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, "fresh-1")
        XCTAssertEqual(viewModel.selectedPresetFilm?.kind, .custom)
    }

    func test_editSaveOfSelectedFilm_preservesSelection_withUpdatedIdentity() {
        let viewModel = makeViewModel()
        let original = makeCustomFilm(id: "edit-1", stockName: "Original", exponent: 1.30)
        viewModel.addCustomFilm(original)
        viewModel.selectPresetFilm(original)

        // Upsert with same id but a different exponent / stock name.
        let updated = makeCustomFilm(id: "edit-1", stockName: "Updated", exponent: 1.55)
        viewModel.addCustomFilm(updated)

        // Selection by id stays, and the active identity now
        // points at the updated FilmIdentity (verified through the
        // canonical stock name and the formula exponent).
        XCTAssertEqual(viewModel.selectedSelectorEntryID, "edit-1")
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, "edit-1")
        XCTAssertEqual(viewModel.selectedPresetFilm?.canonicalStockName, "Updated")
        let activeExponent = viewModel.selectedPresetFilm?.profiles.first?.rules
            .compactMap { rule -> Double? in
                if case .formula(let r) = rule { return r.formula.exponent }
                return nil
            }
            .first
        XCTAssertEqual(activeExponent ?? 0, 1.55, accuracy: 1e-9)
    }

    func test_editSaveOfDifferentFilm_doesNotChangeSelection() {
        let viewModel = makeViewModel()
        let active = makeCustomFilm(id: "active", stockName: "Active")
        let other = makeCustomFilm(id: "other", stockName: "Other")
        viewModel.addCustomFilm(active)
        viewModel.addCustomFilm(other)
        viewModel.selectPresetFilm(active)

        // Upsert an unrelated film — the active selection must
        // stay on `active`, not jump to `other`.
        let otherUpdated = makeCustomFilm(id: "other", stockName: "Other v2")
        viewModel.addCustomFilm(otherUpdated)

        XCTAssertEqual(viewModel.selectedSelectorEntryID, "active")
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, "active")
    }

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            customFilmLibrary: CustomFilmLibrary()
        )
    }

    private func makeCustomFilm(
        id: String,
        stockName: String,
        exponent: Double = 1.30
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(
            exponent: exponent,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "\(id)-profile",
            name: stockName,
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))]
        )
        return FilmIdentity(
            id: id,
            kind: .custom,
            canonicalStockName: stockName,
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: nil
        )
    }
}
