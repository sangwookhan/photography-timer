import XCTest
@testable import PTimerKit
import PTimerCore

/// Save / reload coverage for the custom film library through an
/// injected in-memory store (off-simulator). The concrete
/// `UserDefaultsCustomFilmLibraryStore` round-trip stays app-hosted in
/// `PersistentCustomFilmLibraryTests`.
@MainActor
final class CustomFilmLibraryReloadTests: XCTestCase {

    func test_savedProfiles_surviveReloadInOrderIntoNewInstance() {
        let store = InMemoryCustomFilmLibraryStore()
        let library = CustomFilmLibrary(store: store)
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "alpha", stockName: "Alpha"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "beta", stockName: "Beta"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "gamma", stockName: "Gamma"))

        // A fresh library instance reloads every saved profile in order,
        // and a saved profile's stock name survives the round-trip.
        let reloaded = CustomFilmLibrary(store: store)
        XCTAssertEqual(reloaded.customFilms.map(\.id), ["alpha", "beta", "gamma"])
        XCTAssertEqual(reloaded.customFilms.first?.canonicalStockName, "Alpha")
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
