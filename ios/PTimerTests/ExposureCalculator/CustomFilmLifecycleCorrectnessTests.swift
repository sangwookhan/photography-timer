import XCTest
import PTimerCore
@testable import PTimer

/// Lifecycle correctness coverage. Pins selection restore,
/// inactive-slot scrub on delete, and persistence sanitation so
/// a custom film never resurfaces as a dangling reference after
/// relaunch or deletion.
@MainActor
final class CustomFilmLifecycleCorrectnessTests: XCTestCase {

    // MARK: - Selection restore

    func test_customFilmSelection_restoresOnRelaunchViaSessionStore() {
        let libraryStore = InMemoryCustomLibraryStore()
        let sessionStore = InMemoryCameraSlotSessionStore()
        let calculatorStore = InMemoryCalculatorContextStore()

        // Round 1: create + select a custom film, then let
        // persistence write through.
        let library1 = CustomFilmLibrary(store: libraryStore)
        let vm1 = makeViewModel(
            library: library1,
            calculatorContextStore: calculatorStore,
            sessionStore: sessionStore
        )
        let film = CustomFilmLibraryTests.makeCustomFilm(id: "saved-custom", stockName: "Saved")
        vm1.addCustomFilm(film)
        vm1.selectEntry(vm1.filmSelectorEntries.first { $0.id == "saved-custom" }!)
        // Force a persistence write by touching the base shutter
        // (mirrors the real-world flow where any state change
        // flushes the session snapshot).
        vm1.baseShutter = 4.0

        // Round 2: a fresh library + ViewModel against the same
        // stores. The custom library reloads from disk, and the
        // session restore must resolve the persisted film id
        // against both the preset catalog and the rehydrated
        // custom library.
        let library2 = CustomFilmLibrary(store: libraryStore)
        let vm2 = makeViewModel(
            library: library2,
            calculatorContextStore: calculatorStore,
            sessionStore: sessionStore
        )

        XCTAssertEqual(vm2.customFilms.map(\.id), ["saved-custom"])
        XCTAssertEqual(vm2.selectedPresetFilm?.id, "saved-custom")
        XCTAssertEqual(vm2.selectedPresetFilm?.kind, .custom)
    }

    func test_legacyCalculatorContextRestore_resolvesCustomFilmID() {
        let libraryStore = InMemoryCustomLibraryStore()
        // Pre-seed the legacy single-context store with a custom
        // film id so the session-less restore path also has to
        // resolve through the custom library.
        let legacyStore = InMemoryCalculatorContextStore()
        legacyStore.saveSnapshot(
            PersistentCalculatorContextSnapshot(
                selectedPresetFilmID: "legacy-custom",
                baseShutterSeconds: 6.0,
                ndStop: 0
            )
        )
        let library = CustomFilmLibrary(store: libraryStore)
        library.add(CustomFilmLibraryTests.makeCustomFilm(id: "legacy-custom", stockName: "Legacy"))

        let vm = makeViewModel(
            library: library,
            calculatorContextStore: legacyStore,
            sessionStore: NoOpCameraSlotSessionPersistenceStore()
        )

        XCTAssertEqual(vm.selectedPresetFilm?.id, "legacy-custom")
    }

    // MARK: - Delete cleanup

    func test_deleteCustomFilm_scrubsInactiveCameraSlotSnapshots() {
        let sessionStore = InMemoryCameraSlotSessionStore()
        let calculatorStore = InMemoryCalculatorContextStore()
        let library = CustomFilmLibrary()
        let vm = makeViewModel(
            library: library,
            calculatorContextStore: calculatorStore,
            sessionStore: sessionStore
        )
        let film = CustomFilmLibraryTests.makeCustomFilm(id: "haunting", stockName: "Haunting")
        vm.addCustomFilm(film)

        // Select the custom film on Camera 2 (becomes an inactive
        // slot once we switch back to Camera 1).
        vm.selectCameraSlot(.camera2)
        vm.selectEntry(vm.filmSelectorEntries.first { $0.id == "haunting" }!)
        vm.selectCameraSlot(.camera1)
        XCTAssertEqual(
            vm.cameraSlotPageState(for: .camera2).selectedFilm?.id,
            "haunting",
            "Sanity: Camera 2's snapshot retains the custom film while it's the inactive slot."
        )

        // Now delete the film. The active slot (Camera 1) had no
        // selection, so the delete must reach into the inactive
        // Camera 2 snapshot and clear the reference.
        vm.deleteCustomFilm(id: "haunting")

        XCTAssertNil(vm.cameraSlotPageState(for: .camera2).selectedFilm)
    }

    func test_deleteCustomFilm_inactiveSlotCleanup_survivesRelaunch() {
        let libraryStore = InMemoryCustomLibraryStore()
        let sessionStore = InMemoryCameraSlotSessionStore()
        let calculatorStore = InMemoryCalculatorContextStore()
        let library = CustomFilmLibrary(store: libraryStore)
        let vm = makeViewModel(
            library: library,
            calculatorContextStore: calculatorStore,
            sessionStore: sessionStore
        )
        let film = CustomFilmLibraryTests.makeCustomFilm(id: "doomed", stockName: "Doomed")
        vm.addCustomFilm(film)
        vm.selectCameraSlot(.camera2)
        vm.selectEntry(vm.filmSelectorEntries.first { $0.id == "doomed" }!)
        vm.selectCameraSlot(.camera1)
        vm.deleteCustomFilm(id: "doomed")

        // Fresh ViewModel against the same persistence — the
        // delete must have written the cleared snapshot, so the
        // restored Camera 2 page shows no film.
        let library2 = CustomFilmLibrary(store: libraryStore)
        let vm2 = makeViewModel(
            library: library2,
            calculatorContextStore: calculatorStore,
            sessionStore: sessionStore
        )
        XCTAssertFalse(vm2.customFilms.contains { $0.id == "doomed" })
        XCTAssertNil(vm2.cameraSlotPageState(for: .camera2).selectedFilm)
    }

    // MARK: - Persistence sanitation

    func test_sanitation_dropsMalformedCustomFilm() {
        let wellFormed = CustomFilmLibraryTests.makeCustomFilm(id: "ok", stockName: "Ok")
        let malformedKind = FilmIdentity(
            id: "preset-as-custom",
            kind: .preset,
            canonicalStockName: "Preset",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .current,
            profiles: [],
            userMetadata: nil
        )
        let zeroISO = customFilm(id: "zero-iso", iso: 0, exponent: 1.30)
        let blankProfileName = customFilm(
            id: "blank-profile-name",
            iso: 100,
            exponent: 1.30,
            profileName: "  "
        )
        let negativeExponent = customFilm(id: "neg-exp", iso: 100, exponent: -1.0)
        let nanExponent = customFilm(id: "nan-exp", iso: 100, exponent: .nan)
        let zeroCoefficient = customFilm(id: "zero-coef", iso: 100, exponent: 1.3, coefficient: 0)
        let infiniteOffset = customFilm(id: "inf-offset", iso: 100, exponent: 1.3, offset: .infinity)

        let library = CustomFilmLibrary(initial: [
            wellFormed,
            malformedKind,
            zeroISO,
            blankProfileName,
            negativeExponent,
            nanExponent,
            zeroCoefficient,
            infiniteOffset,
        ])

        let retainedIDs: [String] = library.customFilms.map { $0.id }
        XCTAssertEqual(retainedIDs, ["ok"])
    }

    func test_sanitation_appliesOnLibraryRestore() {
        let store = InMemoryCustomLibraryStore()
        // Plant a snapshot directly through the store API so we
        // bypass the library's runtime invariants — simulates a
        // future schema mismatch or a manual UserDefaults edit.
        store.saveSnapshot(
            PersistentCustomFilmLibrarySnapshot(films: [
                customFilm(id: "valid", iso: 100, exponent: 1.30),
                customFilm(id: "broken", iso: 100, exponent: -2.0),
            ])
        )
        let library = CustomFilmLibrary(store: store)
        XCTAssertEqual(library.customFilms.map(\.id), ["valid"])
    }

    // MARK: - Helpers

    private func makeViewModel(
        library: CustomFilmLibrary,
        calculatorContextStore: ExposureCalculatorContextStoring,
        sessionStore: CameraSlotSessionPersistenceStoring
    ) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            contextPersistenceStore: calculatorContextStore,
            cameraSlotSessionPersistenceStore: sessionStore,
            customFilmLibrary: library
        )
    }

    private func customFilm(
        id: String,
        iso: Int,
        exponent: Double,
        coefficient: Double? = nil,
        offset: Double? = nil,
        profileName: String = "Custom profile"
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
            userMetadata: UserEditableMetadata(customSourceType: .personalTest),
            sourceEvidence: []
        )
        return FilmIdentity(
            id: id,
            kind: .custom,
            canonicalStockName: "Stock for \(id)",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: iso,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: nil
        )
    }
}

// MARK: - In-memory stores

@MainActor
private final class InMemoryCustomLibraryStore: CustomFilmLibraryStoring {
    private var snapshot: PersistentCustomFilmLibrarySnapshot?
    func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot? { snapshot }
    func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot) { self.snapshot = snapshot }
    func clearSnapshot() { snapshot = nil }
}

@MainActor
private final class InMemoryCalculatorContextStore: ExposureCalculatorContextStoring {
    private var snapshot: PersistentCalculatorContextSnapshot?
    func loadSnapshot() -> PersistentCalculatorContextSnapshot? { snapshot }
    func saveSnapshot(_ snapshot: PersistentCalculatorContextSnapshot) { self.snapshot = snapshot }
    func clearSnapshot() { snapshot = nil }
}

@MainActor
private final class InMemoryCameraSlotSessionStore: CameraSlotSessionPersistenceStoring {
    private var snapshot: PersistentCameraSlotSessionSnapshot?
    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { snapshot }
    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) { self.snapshot = snapshot }
    func clearSnapshot() { snapshot = nil }
}
