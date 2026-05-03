import XCTest
@testable import PTimer

/// Direct unit tests for `FilmSelectionModel`. These cover the
/// film-selection slice in isolation;
/// `ExposureCalculatorViewModelFilmModeTests` and
/// `ExposureCalculatorViewModelContextPersistenceTests` cover the same
/// behavior end-to-end through the view-model facade.
final class FilmSelectionModelTests: XCTestCase {

    // MARK: - Default state

    @MainActor
    func testDefaultStateIsNoSelectionWithCatalogAvailable() {
        let model = makeModel()

        XCTAssertNil(model.selectedPresetFilm)
        XCTAssertNil(model.selectedProfileOverride)
        XCTAssertEqual(model.availablePresetFilms, model.presetFilms)
        XCTAssertFalse(model.presetFilms.isEmpty)
    }

    // MARK: - Selection

    @MainActor
    func testSelectPresetFilmSetsActiveFilmAndPersistsSnapshot() throws {
        let store = SpyContextPersistenceStore()
        let model = makeModel(contextPersistenceStore: store, baseShutterSeconds: 1.0 / 15.0, ndStop: 4)
        let film = try XCTUnwrap(model.presetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        model.selectPresetFilm(film)

        XCTAssertEqual(model.selectedPresetFilm?.id, film.id)
        XCTAssertNil(model.selectedProfileOverride)
        // Persistence snapshot pulls calc inputs from the closures and
        // bundles them with the selected film id.
        XCTAssertEqual(
            store.savedSnapshots.last,
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 1.0 / 15.0,
                ndStop: 4
            )
        )
    }

    @MainActor
    func testClearSelectedPresetFilmResetsSelectionAndPersistsCleared() throws {
        let store = SpyContextPersistenceStore()
        let model = makeModel(contextPersistenceStore: store)
        let film = try XCTUnwrap(model.presetFilms.first)
        model.selectPresetFilm(film)
        XCTAssertNotNil(model.selectedPresetFilm)

        model.clearSelectedPresetFilm()

        XCTAssertNil(model.selectedPresetFilm)
        XCTAssertNil(model.selectedProfileOverride)
        // Last snapshot retains the calc inputs but drops the film id —
        // the model writes a normalized full snapshot rather than
        // calling `clearSnapshot`.
        XCTAssertEqual(store.savedSnapshots.last?.selectedPresetFilmID, nil)
    }

    @MainActor
    func testSelectEntryAppliesProfileOverride() throws {
        let store = SpyContextPersistenceStore()
        let model = makeModel(contextPersistenceStore: store)
        let film = try XCTUnwrap(model.presetFilms.first { $0.id == "kodak-portra-400" })
        let unofficialProfile = try XCTUnwrap(UnofficialPracticalProfiles.profile(forFilmID: film.id))
        let entry = FilmSelectorEntry(
            id: unofficialProfile.id,
            primaryText: film.canonicalStockName,
            secondaryText: "Unofficial",
            film: film,
            profileOverride: unofficialProfile
        )

        model.selectEntry(entry)

        XCTAssertEqual(model.selectedPresetFilm?.id, film.id)
        XCTAssertEqual(model.selectedProfileOverride?.id, unofficialProfile.id)
    }

    // MARK: - Persistence round-trip

    @MainActor
    func testRestoreContextResolvesValidFilmAndReturnsCalcInputs() throws {
        let presetFilms = LaunchPresetFilmCatalog.films
        let film = try XCTUnwrap(presetFilms.first { $0.canonicalStockName == "Tri-X 400" })
        let store = SpyContextPersistenceStore(
            initialSnapshot: PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 1.0 / 15.0,
                ndStop: 4
            )
        )
        let model = makeModel(presetFilms: presetFilms, contextPersistenceStore: store)

        let restored = try XCTUnwrap(model.restoreContext())

        XCTAssertFalse(restored.hadInvalidFilmReference)
        XCTAssertEqual(restored.selectedPresetFilm?.id, film.id)
        XCTAssertEqual(restored.baseShutterSeconds, 1.0 / 15.0)
        XCTAssertEqual(restored.ndStop, 4)
        XCTAssertEqual(model.selectedPresetFilm?.id, film.id)
    }

    @MainActor
    func testRestoreContextWithUnknownFilmIDClearsSnapshot() {
        let store = SpyContextPersistenceStore(
            initialSnapshot: PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: "missing-film-id",
                baseShutterSeconds: 1,
                ndStop: 4
            )
        )
        let model = makeModel(contextPersistenceStore: store)

        let restored = model.restoreContext()

        XCTAssertEqual(restored?.hadInvalidFilmReference, true)
        XCTAssertNil(model.selectedPresetFilm)
        XCTAssertGreaterThanOrEqual(store.clearCount, 1)
    }

    @MainActor
    func testRestoreContextReturnsNilWhenStoreIsEmpty() {
        let store = SpyContextPersistenceStore()
        let model = makeModel(contextPersistenceStore: store)

        XCTAssertNil(model.restoreContext())
    }

    // MARK: - Authority label

    @MainActor
    func testFilmRowAuthorityLabelMapsAuthorityValuesToTextOrNil() throws {
        let presetFilms = LaunchPresetFilmCatalog.films
        let officialProfile = try XCTUnwrap(
            presetFilms
                .first { $0.canonicalStockName == "Tri-X 400" }?
                .profiles
                .first
        )

        XCTAssertEqual(
            FilmSelectionModel.filmRowAuthorityLabel(for: officialProfile),
            "Official guidance"
        )
        XCTAssertNil(FilmSelectionModel.filmRowAuthorityLabel(for: nil))
    }

    // MARK: - ISO row text

    @MainActor
    func testFilmRowISOTextRendersStructuredISOFromFilmIdentity() {
        let film = FilmIdentity(
            id: "fp4-plus-test",
            kind: .preset,
            canonicalStockName: "FP4 Plus",
            manufacturer: "ILFORD / HARMAN",
            brandLabel: "ILFORD FP4 PLUS",
            aliases: ["FP4+"],
            iso: 125,
            productionStatus: .current,
            profiles: [],
            userMetadata: nil
        )

        // Non-standard box speeds (125, 80, 20, ...) round-trip exactly because
        // the value is stored on the identity rather than inferred from text.
        XCTAssertEqual(FilmSelectionModel.filmRowISOText(for: film), "ISO 125")
    }
}

// MARK: - Test doubles

private final class SpyContextPersistenceStore: ExposureCalculatorContextPersistenceStoring {
    private var loadedSnapshot: PersistentExposureCalculatorContextSnapshot?
    private(set) var savedSnapshots: [PersistentExposureCalculatorContextSnapshot] = []
    private(set) var clearCount: Int = 0

    init(initialSnapshot: PersistentExposureCalculatorContextSnapshot? = nil) {
        self.loadedSnapshot = initialSnapshot
    }

    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot? {
        loadedSnapshot
    }

    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot) {
        savedSnapshots.append(snapshot)
    }

    func clearSnapshot() {
        clearCount += 1
        loadedSnapshot = nil
    }
}

@MainActor
private func makeModel(
    presetFilms: [FilmIdentity] = LaunchPresetFilmCatalog.films,
    contextPersistenceStore: ExposureCalculatorContextPersistenceStoring = NoOpExposureCalculatorContextPersistenceStore(),
    baseShutterSeconds: Double = 1.0 / 30.0,
    ndStop: Int = 0
) -> FilmSelectionModel {
    FilmSelectionModel(
        presetFilms: presetFilms,
        contextPersistenceStore: contextPersistenceStore,
        currentBaseShutterSeconds: { baseShutterSeconds },
        currentNDStop: { ndStop }
    )
}
