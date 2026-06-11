import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Save / reload coverage for the concrete production
/// `UserDefaultsCustomFilmLibraryStore` (against an isolated
/// `UserDefaults(suiteName:)`). These stay app-hosted because the
/// concrete store lives in the app target; the injected in-memory /
/// library-rule round-trips moved off-simulator to
/// `CustomFilmLibraryReloadTests` in PTimerKitTests.
@MainActor
final class PersistentCustomFilmLibraryTests: XCTestCase {

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
