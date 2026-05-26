import XCTest
@testable import PTimer

/// Edit flow + selector header "+" + Quick Access alias
/// coverage. Covers the prefilled editor, upsert-on-save
/// behavior, the Quick Access section's aliasing rule, and the
/// "No film" top row anchor.
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

    // MARK: - Quick Access aliasing

    func test_quickAccessSection_appearsAfterNoFilm_beforePresets() {
        let viewModel = makeViewModel()
        viewModel.addCustomFilm(makeFormulaFilm(id: "alpha", stockName: "Alpha"))

        let sections = viewModel.filmSelectorSections
        let noFilmIndex = sections.firstIndex { $0.entries.contains { $0.id == "no-film" } }
        let quickIndex = sections.firstIndex {
            $0.manufacturer == ExposureCalculatorViewModel.quickAccessSectionManufacturerLabel
        }
        let firstPresetIndex = sections.firstIndex { section in
            // Skip Custom Films + Quick Access sections.
            guard let manufacturer = section.manufacturer else { return false }
            return manufacturer != ExposureCalculatorViewModel.customFilmsSectionManufacturerLabel
                && manufacturer != ExposureCalculatorViewModel.quickAccessSectionManufacturerLabel
        }

        XCTAssertNotNil(quickIndex, "Quick Access section must appear when custom films exist")
        if let noFilmIndex, let quickIndex, let firstPresetIndex {
            XCTAssertLessThan(noFilmIndex, quickIndex)
            XCTAssertLessThan(quickIndex, firstPresetIndex)
        }
    }

    func test_quickAccessAlias_routesToSameSelectionIdentity() {
        let viewModel = makeViewModel()
        viewModel.addCustomFilm(makeFormulaFilm(id: "shared", stockName: "Shared"))

        let entries = viewModel.filmSelectorEntries
        guard let canonical = entries.first(where: { $0.id == "shared" }),
              let alias = entries.first(where: { $0.aliasOfOriginalID == "shared" }) else {
            return XCTFail("Both canonical and alias rows must exist for the same film")
        }
        XCTAssertEqual(alias.film?.id, canonical.film?.id)
        XCTAssertEqual(
            alias.manufacturer,
            ExposureCalculatorViewModel.quickAccessSectionManufacturerLabel
        )

        // Selecting the alias must produce the same selected
        // canonical entry id as selecting the original.
        viewModel.selectEntry(alias)
        XCTAssertEqual(viewModel.selectedSelectorEntryID, "shared")
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, "shared")
    }

    func test_quickAccessSection_omittedWhenEmpty() {
        let viewModel = makeViewModel()
        // No custom films, nothing selected → Quick Access is
        // empty and the section must not appear at all so users
        // do not see a redundant blank header.
        let hasQuickAccess = viewModel.filmSelectorSections.contains {
            $0.manufacturer == ExposureCalculatorViewModel.quickAccessSectionManufacturerLabel
        }
        XCTAssertFalse(hasQuickAccess)
    }

    func test_quickAccessSection_includesSelectedPresetWhenChosen() throws {
        let viewModel = makeViewModel()
        let provia = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Provia 100F" }
        )
        viewModel.selectPresetFilm(provia)

        let quickEntries = viewModel.filmSelectorSections
            .first { $0.manufacturer == ExposureCalculatorViewModel.quickAccessSectionManufacturerLabel }?
            .entries ?? []
        XCTAssertTrue(quickEntries.contains { $0.aliasOfOriginalID == provia.id })
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
