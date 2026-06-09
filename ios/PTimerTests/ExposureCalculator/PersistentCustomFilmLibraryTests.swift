import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Save / reload coverage for the custom film library.
/// Exercises the persistence boundary in both the in-memory +
/// injected-store path and the production
/// `UserDefaultsCustomFilmLibraryStore` path (against an
/// isolated `UserDefaults(suiteName:)`).
@MainActor
final class PersistentCustomFilmLibraryTests: XCTestCase {

    func test_savedProfile_survivesNewLibraryInstance() {
        let store = InMemoryCustomFilmLibraryStore()
        let library = CustomFilmLibrary(store: store)
        let film = CustomFilmTestSupport.makeCustomFilm(id: "film-1", stockName: "Saved")

        library.add(film)

        let reloaded = CustomFilmLibrary(store: store)
        XCTAssertEqual(reloaded.customFilms.map(\.id), ["film-1"])
        XCTAssertEqual(reloaded.customFilms.first?.canonicalStockName, "Saved")
    }

    func test_savedMultipleProfiles_surviveReloadInOrder() {
        let store = InMemoryCustomFilmLibraryStore()
        let library = CustomFilmLibrary(store: store)
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "alpha", stockName: "Alpha"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "beta", stockName: "Beta"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "gamma", stockName: "Gamma"))

        let reloaded = CustomFilmLibrary(store: store)
        XCTAssertEqual(reloaded.customFilms.map(\.id), ["alpha", "beta", "gamma"])
    }

    func test_savedProfile_roundTripsAllFieldsAndFormula() {
        let store = InMemoryCustomFilmLibraryStore()
        let library = CustomFilmLibrary(store: store)

        let formula = ReciprocityFormula(
            coefficientSeconds: 1.10,
            referenceMeteredTimeSeconds: 1,
            exponent: 1.42,
            offsetSeconds: 0.05,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "round-trip-profile",
            name: "Round-trip profile",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            notes: [],
            userMetadata: UserEditableMetadata(
                notes: ["bracketed test"],
                customSourceType: .personalTest
            ),
            sourceEvidence: []
        )
        let film = FilmIdentity(
            id: "round-trip-film",
            kind: .custom,
            canonicalStockName: "Round Trip Stock",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 400,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest)
        )

        library.add(film)
        let reloaded = CustomFilmLibrary(store: store)

        guard let reloadedFilm = reloaded.customFilms.first,
              let reloadedProfile = reloadedFilm.profiles.first,
              case .formula(let rule) = reloadedProfile.rules.first else {
            return XCTFail("Expected exactly one custom film with a formula rule")
        }

        XCTAssertEqual(reloadedFilm.id, "round-trip-film")
        XCTAssertEqual(reloadedFilm.canonicalStockName, "Round Trip Stock")
        XCTAssertEqual(reloadedFilm.iso, 400)
        XCTAssertEqual(reloadedFilm.userMetadata?.customSourceType, .personalTest)
        XCTAssertEqual(reloadedProfile.userMetadata?.customSourceType, .personalTest)
        XCTAssertEqual(reloadedProfile.userMetadata?.notes, ["bracketed test"])
        XCTAssertEqual(rule.formula.exponent, 1.42, accuracy: 0.0001)
        XCTAssertEqual(rule.formula.coefficientSeconds, 1.10, accuracy: 0.0001)
        XCTAssertEqual(rule.formula.offsetSeconds, 0.05, accuracy: 0.0001)
    }

    func test_removeProfile_persistsDeletion() {
        let store = InMemoryCustomFilmLibraryStore()
        let library = CustomFilmLibrary(store: store)
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "keep", stockName: "Keep"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "drop", stockName: "Drop"))

        library.remove(id: "drop")

        let reloaded = CustomFilmLibrary(store: store)
        XCTAssertEqual(reloaded.customFilms.map(\.id), ["keep"])
    }

    func test_malformedPayload_failsSafeToEmptyLibrary() {
        let suiteName = "ptimer.tests.custom-film-library.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create suite UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Plant a malformed payload directly so the next load hits
        // the decoder's failure branch. The store must swallow the
        // error and surface an empty library, not crash.
        let key = "ptimer.exposure-calculator.custom-films.snapshot"
        defaults.set(Data("not-json".utf8), forKey: key)

        let store = UserDefaultsCustomFilmLibraryStore(
            userDefaults: defaults,
            snapshotKey: key
        )
        let library = CustomFilmLibrary(store: store)

        XCTAssertTrue(library.isEmpty)

        // After a successful save, subsequent loads should now
        // succeed — the malformed bytes have been replaced.
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "recovered", stockName: "Recovered"))
        let reloaded = CustomFilmLibrary(store: store)
        XCTAssertEqual(reloaded.customFilms.map(\.id), ["recovered"])
    }

    func test_userDefaultsStore_persistsAcrossDistinctInstances() {
        let suiteName = "ptimer.tests.custom-film-library.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create suite UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storeKey = "ptimer.exposure-calculator.custom-films.snapshot"
        let firstStore = UserDefaultsCustomFilmLibraryStore(
            userDefaults: defaults,
            snapshotKey: storeKey
        )
        let firstLibrary = CustomFilmLibrary(store: firstStore)
        firstLibrary.add(CustomFilmTestSupport.makeCustomFilm(id: "persisted", stockName: "P"))

        // A new store instance with the same UserDefaults must
        // observe the persisted payload — same backing storage.
        let secondStore = UserDefaultsCustomFilmLibraryStore(
            userDefaults: defaults,
            snapshotKey: storeKey
        )
        let secondLibrary = CustomFilmLibrary(store: secondStore)
        XCTAssertEqual(secondLibrary.customFilms.map(\.id), ["persisted"])
    }

    func test_presetCatalogStoreKey_isDistinctFromCustomLibraryKey() {
        // Custom library writes under a dedicated UserDefaults key,
        // separate from `ptimer.exposure-calculator.context.snapshot`
        // / the camera-slot session key, so clearing the custom
        // library cannot stomp other persisted surfaces.
        let suiteName = "ptimer.tests.custom-film-library.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create suite UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Plant a sentinel under the calculator-context key.
        let calculatorContextKey = "ptimer.exposure-calculator.context.snapshot"
        defaults.set(Data("preset-sentinel".utf8), forKey: calculatorContextKey)

        let store = UserDefaultsCustomFilmLibraryStore(userDefaults: defaults)
        let library = CustomFilmLibrary(store: store)
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "custom", stockName: "Custom"))

        XCTAssertEqual(
            defaults.data(forKey: calculatorContextKey),
            Data("preset-sentinel".utf8),
            "The custom-film library writer must not overwrite unrelated persistence keys."
        )
    }
}

/// Test double that mimics `UserDefaultsCustomFilmLibraryStore`
/// in-memory, so persistence behavior tests stay deterministic
/// without touching the real UserDefaults domain.
@MainActor
private final class InMemoryCustomFilmLibraryStore: CustomFilmLibraryStoring {
    private var snapshot: PersistentCustomFilmLibrarySnapshot?

    func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}
