import XCTest
import PTimerCore
@testable import PTimer

/// Edit flow + selector top-of-list affordances. Covers the
/// prefilled editor, upsert-on-save behavior, the explicit
/// "New custom film" row, the "No film" top row anchor, and
/// stable list ordering after selection.
@MainActor
final class CustomFilmEditAndSelectorUXTests: XCTestCase {

    // MARK: - Edit prefill / upsert

    func test_editorFormState_fromExistingFilm_prefillsEveryField() throws {
        let film = makeFormulaFilm(
            id: "edit-source",
            stockName: "Edit Source",
            iso: 200,
            exponent: 1.42,
            coefficient: 1.10,
            offset: 0.5,
            sourceType: .communityReference,
            profileName: "Personal Provia",
            notes: "Original notes"
        )
        let state = try XCTUnwrap(CustomFilmEditorFormState.from(film: film))
        XCTAssertEqual(state.profileName, "Personal Provia")
        XCTAssertEqual(state.filmLabel, "Edit Source")
        XCTAssertEqual(state.isoText, "200")
        XCTAssertEqual(state.sourceType, .communityReference)
        XCTAssertEqual(state.notes, "Original notes")
        XCTAssertEqual(state.exponentText, "1.42")
        // Legacy custom profile with coefficient = 1.10 but no
        // anchor metadata round-trips as Base Tm = 1, Base Tc =
        // 1.10 (mathematically the same formula).
        XCTAssertEqual(state.baseTmText, "1")
        XCTAssertEqual(state.baseTcText, "1.1")
        XCTAssertEqual(state.offsetSecondsText, "0.5")
    }

    func test_editorFormState_fromExistingFilm_rejectsNonCustom() {
        let preset = FilmIdentity(
            id: "preset",
            kind: .preset,
            canonicalStockName: "Preset",
            manufacturer: "Fuji",
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .current,
            profiles: [],
            userMetadata: nil
        )
        XCTAssertNil(CustomFilmEditorFormState.from(film: preset))
    }

    func test_addCustomFilm_withSameID_upsertsInPlace() {
        let library = CustomFilmLibrary()
        let original = makeFormulaFilm(
            id: "stable-id",
            stockName: "Original",
            iso: 100,
            exponent: 1.30
        )
        library.add(original)
        XCTAssertEqual(library.customFilms.map(\.id), ["stable-id"])

        let edited = makeFormulaFilm(
            id: "stable-id",
            stockName: "Edited",
            iso: 200,
            exponent: 1.45
        )
        library.add(edited)

        // Same id, replaced in place: one entry, new stock name.
        XCTAssertEqual(library.customFilms.count, 1)
        XCTAssertEqual(library.customFilms.first?.canonicalStockName, "Edited")
        XCTAssertEqual(library.customFilms.first?.iso, 200)
    }

    // MARK: - Quick Access removal + explicit Create row

    func test_filmSelectorEntries_noQuickAccessSection() {
        let viewModel = makeViewModel()
        viewModel.addCustomFilm(makeFormulaFilm(id: "alpha", stockName: "Alpha"))

        // No section should ever carry the legacy "Quick access"
        // pseudo-manufacturer label after the PTIMER-84 UX pass.
        let hasQuickAccess = viewModel.filmSelectorSections.contains {
            $0.manufacturer == "Quick access"
        }
        XCTAssertFalse(hasQuickAccess)
    }

    func test_filmSelectorEntries_doesNotDuplicateCustomFilm() {
        let viewModel = makeViewModel()
        viewModel.addCustomFilm(makeFormulaFilm(id: "alpha", stockName: "Alpha"))

        let alphaEntries = viewModel.filmSelectorEntries.filter { $0.id == "alpha" }
        XCTAssertEqual(alphaEntries.count, 1, "Custom film must appear exactly once")
    }

    func test_filmSelectorEntries_includesCreateCustomFilmRow_belowNoFilm() {
        let viewModel = makeViewModel()
        let entries = viewModel.filmSelectorEntries
        guard let noFilmIndex = entries.firstIndex(where: { $0.id == "no-film" }),
              let createIndex = entries.firstIndex(where: { $0.isCreateCustomFilmAction }) else {
            return XCTFail("Both 'No film' and Create rows must exist")
        }
        XCTAssertEqual(createIndex, noFilmIndex + 1)
        XCTAssertEqual(
            entries[createIndex].id,
            ExposureCalculatorViewModel.createCustomFilmEntryID
        )
    }

    func test_createCustomFilmRow_isNeverMarkedSelected() {
        let viewModel = makeViewModel()
        viewModel.addCustomFilm(makeFormulaFilm(id: "selected", stockName: "Selected"))
        let film = viewModel.customFilms.first!
        viewModel.selectPresetFilm(film)
        // The active selection should be on the canonical custom
        // film id — never on the create-action row id.
        XCTAssertEqual(viewModel.selectedSelectorEntryID, "selected")
        XCTAssertNotEqual(
            viewModel.selectedSelectorEntryID,
            ExposureCalculatorViewModel.createCustomFilmEntryID
        )
    }

    // MARK: - Stable list order

    func test_customFilmList_orderStableAcrossSelectionChanges() {
        let viewModel = makeViewModel()
        viewModel.addCustomFilm(makeFormulaFilm(id: "alpha", stockName: "Alpha"))
        viewModel.addCustomFilm(makeFormulaFilm(id: "bravo", stockName: "Bravo"))
        viewModel.addCustomFilm(makeFormulaFilm(id: "charlie", stockName: "Charlie"))

        let baselineOrder = viewModel.filmSelectorEntries.map(\.id)
        // Select a film in the middle of the list — the order
        // must not reshuffle so the photographer's scroll position
        // and visual scanning stays stable.
        viewModel.selectPresetFilm(viewModel.customFilms.first { $0.id == "bravo" }!)
        XCTAssertEqual(viewModel.filmSelectorEntries.map(\.id), baselineOrder)
    }

    // MARK: - No film row anchor

    func test_filmSelectorEntries_firstEntryIsNoFilm() {
        let viewModel = makeViewModel()
        viewModel.addCustomFilm(makeFormulaFilm(id: "custom", stockName: "Custom"))
        XCTAssertEqual(viewModel.filmSelectorEntries.first?.id, "no-film")
    }

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            customFilmLibrary: CustomFilmLibrary()
        )
    }

    private func makeFormulaFilm(
        id: String,
        stockName: String,
        iso: Int = 100,
        exponent: Double = 1.30,
        coefficient: Double? = nil,
        offset: Double? = nil,
        sourceType: CustomProfileSourceType = .userDefined,
        profileName: String = "Custom",
        notes: String = ""
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(
            coefficientSeconds: coefficient ?? 1,
            referenceMeteredTimeSeconds: 1,
            exponent: exponent,
            offsetSeconds: offset ?? 0,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "\(id)-profile",
            name: profileName,
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            notes: [],
            userMetadata: UserEditableMetadata(
                notes: notes.isEmpty ? [] : [notes],
                customSourceType: sourceType
            ),
            sourceEvidence: []
        )
        return FilmIdentity(
            id: id,
            kind: .custom,
            canonicalStockName: stockName,
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: iso,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: sourceType)
        )
    }
}
