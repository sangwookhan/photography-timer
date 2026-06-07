import XCTest
import PTimerCore
@testable import PTimer

@MainActor
final class CustomFilmLibraryTests: XCTestCase {

    func test_initWithoutSeed_isEmpty() {
        let library = CustomFilmLibrary()
        XCTAssertTrue(library.isEmpty)
        XCTAssertEqual(library.customFilms.count, 0)
    }

    func test_add_appendsCustomFilm() {
        let library = CustomFilmLibrary()
        let film = Self.makeCustomFilm(id: "film-1")

        library.add(film)

        XCTAssertEqual(library.customFilms.map(\.id), ["film-1"])
    }

    func test_add_preservesInsertionOrder() {
        let library = CustomFilmLibrary()
        library.add(Self.makeCustomFilm(id: "film-1"))
        library.add(Self.makeCustomFilm(id: "film-2"))
        library.add(Self.makeCustomFilm(id: "film-3"))

        XCTAssertEqual(library.customFilms.map(\.id), ["film-1", "film-2", "film-3"])
    }

    func test_add_rejectsNonCustomKind() {
        let library = CustomFilmLibrary()
        let preset = FilmIdentity(
            id: "preset-1",
            kind: .preset,
            canonicalStockName: "Provia 100F",
            manufacturer: "Fujifilm",
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .current,
            profiles: [],
            userMetadata: nil
        )

        library.add(preset)

        XCTAssertTrue(library.isEmpty)
    }

    func test_add_withDuplicateID_replacesInPlace() {
        let library = CustomFilmLibrary()
        library.add(Self.makeCustomFilm(id: "film-1", stockName: "v1"))
        library.add(Self.makeCustomFilm(id: "film-2", stockName: "second"))
        library.add(Self.makeCustomFilm(id: "film-1", stockName: "v2"))

        XCTAssertEqual(library.customFilms.count, 2)
        XCTAssertEqual(library.customFilms[0].canonicalStockName, "v2")
        XCTAssertEqual(library.customFilms[1].canonicalStockName, "second")
    }

    func test_remove_dropsMatchingEntry() {
        let library = CustomFilmLibrary()
        library.add(Self.makeCustomFilm(id: "film-1"))
        library.add(Self.makeCustomFilm(id: "film-2"))

        library.remove(id: "film-1")

        XCTAssertEqual(library.customFilms.map(\.id), ["film-2"])
    }

    func test_remove_unknownID_isNoOp() {
        let library = CustomFilmLibrary()
        library.add(Self.makeCustomFilm(id: "film-1"))
        library.remove(id: "missing")
        XCTAssertEqual(library.customFilms.map(\.id), ["film-1"])
    }

    func test_initial_dropsMalformedEntries() {
        let valid = Self.makeCustomFilm(id: "ok", stockName: "Ok")
        let blankID = Self.makeCustomFilm(id: "   ", stockName: "Blank")
        let blankName = Self.makeCustomFilm(id: "no-name", stockName: " ")
        let preset = FilmIdentity(
            id: "preset", kind: .preset, canonicalStockName: "Preset",
            manufacturer: nil, brandLabel: nil, aliases: [], iso: 100,
            productionStatus: .current, profiles: [], userMetadata: nil
        )

        let library = CustomFilmLibrary(initial: [valid, blankID, blankName, preset])

        XCTAssertEqual(library.customFilms.map(\.id), ["ok"])
    }

    func test_filmWithID_returnsMatch() {
        let library = CustomFilmLibrary()
        let film = Self.makeCustomFilm(id: "film-7")
        library.add(film)
        XCTAssertEqual(library.film(withID: "film-7")?.id, "film-7")
        XCTAssertNil(library.film(withID: "missing"))
    }

    // MARK: - Helpers

    static func makeCustomFilm(
        id: String,
        stockName: String = "Custom film",
        iso: Int = 100,
        exponent: Double = 1.30,
        sourceType: CustomProfileSourceType = .userDefined
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(exponent: exponent
        , noCorrectionThroughSeconds: 1)
        let profile = ReciprocityProfile(
            id: "\(id)-profile",
            name: "Profile for \(stockName)",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            notes: [],
            userMetadata: UserEditableMetadata(customSourceType: sourceType),
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
