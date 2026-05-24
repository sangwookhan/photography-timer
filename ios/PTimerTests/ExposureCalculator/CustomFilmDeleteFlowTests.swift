import XCTest
@testable import PTimer

/// Delete flow coverage. Asserts the `deleteCustomFilm` surface
/// drops the entry, falls back safely when the deleted profile
/// was active, persists the deletion across reloads, and leaves
/// running/completed timer snapshots intact.
@MainActor
final class CustomFilmDeleteFlowTests: XCTestCase {

    func test_deleteCustomFilm_removesFromSelectorEntries() {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        let film = CustomFilmLibraryTests.makeCustomFilm(id: "to-delete", stockName: "To delete")
        viewModel.addCustomFilm(film)
        XCTAssertTrue(viewModel.customFilms.map(\.id).contains("to-delete"))

        viewModel.deleteCustomFilm(id: "to-delete")

        XCTAssertFalse(viewModel.customFilms.map(\.id).contains("to-delete"))
        XCTAssertFalse(viewModel.filmSelectorEntries.contains { $0.id == "to-delete" })
    }

    func test_deleteCurrentlySelectedCustomFilm_clearsSelection() {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        let film = CustomFilmLibraryTests.makeCustomFilm(id: "selected", stockName: "Selected")
        viewModel.addCustomFilm(film)
        let entry = viewModel.filmSelectorEntries.first { $0.id == "selected" }!
        viewModel.selectEntry(entry)
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, "selected")

        viewModel.deleteCustomFilm(id: "selected")

        XCTAssertNil(viewModel.selectedPresetFilm, "Deleting the active custom film must clear the selection.")
        XCTAssertNil(viewModel.selectedSelectorEntryID)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
    }

    func test_deleteUnselectedCustomFilm_doesNotChangeActiveSelection() {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        let stays = CustomFilmLibraryTests.makeCustomFilm(id: "stays", stockName: "Stays")
        let drops = CustomFilmLibraryTests.makeCustomFilm(id: "drops", stockName: "Drops")
        viewModel.addCustomFilm(stays)
        viewModel.addCustomFilm(drops)
        let staysEntry = viewModel.filmSelectorEntries.first { $0.id == "stays" }!
        viewModel.selectEntry(staysEntry)

        viewModel.deleteCustomFilm(id: "drops")

        XCTAssertEqual(viewModel.selectedPresetFilm?.id, "stays")
    }

    func test_deletionPersists_acrossLibraryReload() {
        let store = SharedInMemoryStore()
        let viewModelA = makeViewModel(library: CustomFilmLibrary(store: store))
        viewModelA.addCustomFilm(CustomFilmLibraryTests.makeCustomFilm(id: "keep", stockName: "Keep"))
        viewModelA.addCustomFilm(CustomFilmLibraryTests.makeCustomFilm(id: "drop", stockName: "Drop"))
        viewModelA.deleteCustomFilm(id: "drop")

        // Build a fresh ViewModel against the same store — the
        // deletion must survive the reload because the library
        // wrote back through the store on remove.
        let viewModelB = makeViewModel(library: CustomFilmLibrary(store: store))
        XCTAssertEqual(viewModelB.customFilms.map(\.id), ["keep"])
    }

    func test_deletingActiveCustomFilm_leavesAlreadyStartedTimerSnapshotIntact() throws {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        let film = customFormulaFilm(id: "running-source", profileName: "Running source")
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(viewModel.filmSelectorEntries.first { $0.id == "running-source" }!)
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0
        viewModel.startFilmCorrectedExposureTimer()

        let original = try XCTUnwrap(
            viewModel.timers.first { $0.status == .running }?.identitySnapshot
        )

        viewModel.deleteCustomFilm(id: "running-source")

        let postDelete = try XCTUnwrap(
            viewModel.timers.first { $0.status == .running }?.identitySnapshot
        )
        XCTAssertEqual(postDelete, original)
        XCTAssertEqual(postDelete.filmDisplayName, "Custom Stock")
        XCTAssertEqual(postDelete.filmProfileQualifier, "Custom")
        XCTAssertNotNil(postDelete.customProfileSummary)
    }

    func test_deleteCustomFilm_doesNotTouchPresetCatalog() throws {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        let presetCountBefore = viewModel.availablePresetFilms.count

        let film = CustomFilmLibraryTests.makeCustomFilm(id: "custom", stockName: "Custom")
        viewModel.addCustomFilm(film)
        viewModel.deleteCustomFilm(id: "custom")

        XCTAssertEqual(viewModel.availablePresetFilms.count, presetCountBefore)
        // Sanity-check a representative preset is still in the
        // selector — preset behavior must remain unchanged after
        // any custom-library mutation.
        XCTAssertTrue(viewModel.availablePresetFilms.contains { $0.canonicalStockName == "Provia 100F" })
    }

    // MARK: - Helpers

    private func makeViewModel(library: CustomFilmLibrary) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            customFilmLibrary: library
        )
    }

    private func customFormulaFilm(
        id: String,
        profileName: String
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(exponent: 1.30, noCorrectionThroughSeconds: 1)
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
            userMetadata: UserEditableMetadata(customSourceType: .personalTest),
            sourceEvidence: []
        )
        return FilmIdentity(
            id: id,
            kind: .custom,
            canonicalStockName: "Custom Stock",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest)
        )
    }
}

@MainActor
private final class SharedInMemoryStore: CustomFilmLibraryStoring {
    private var snapshot: PersistentCustomFilmLibrarySnapshot?

    func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot? { snapshot }
    func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot) { self.snapshot = snapshot }
    func clearSnapshot() { snapshot = nil }
}
