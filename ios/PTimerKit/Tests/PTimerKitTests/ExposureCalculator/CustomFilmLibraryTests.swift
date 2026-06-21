// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

@MainActor
final class CustomFilmLibraryTests: XCTestCase {

    func test_initWithoutSeed_isEmpty() {
        let library = CustomFilmLibrary()
        XCTAssertTrue(library.isEmpty)
        XCTAssertEqual(library.customFilms.count, 0)
    }

    func test_add_appendsCustomFilm() {
        let library = CustomFilmLibrary()
        let film = CustomFilmTestSupport.makeCustomFilm(id: "film-1")

        library.add(film)

        XCTAssertEqual(library.customFilms.map(\.id), ["film-1"])
    }

    func test_add_preservesInsertionOrder() {
        let library = CustomFilmLibrary()
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-1"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-2"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-3"))

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
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-1", stockName: "v1"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-2", stockName: "second"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-1", stockName: "v2"))

        XCTAssertEqual(library.customFilms.count, 2)
        XCTAssertEqual(library.customFilms[0].canonicalStockName, "v2")
        XCTAssertEqual(library.customFilms[1].canonicalStockName, "second")
    }

    func test_remove_dropsMatchingEntry() {
        let library = CustomFilmLibrary()
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-1"))
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-2"))

        library.remove(id: "film-1")

        XCTAssertEqual(library.customFilms.map(\.id), ["film-2"])
    }

    func test_remove_unknownID_isNoOp() {
        let library = CustomFilmLibrary()
        library.add(CustomFilmTestSupport.makeCustomFilm(id: "film-1"))
        library.remove(id: "missing")
        XCTAssertEqual(library.customFilms.map(\.id), ["film-1"])
    }

    func test_initial_dropsMalformedEntries() {
        let valid = CustomFilmTestSupport.makeCustomFilm(id: "ok", stockName: "Ok")
        let blankID = CustomFilmTestSupport.makeCustomFilm(id: "   ", stockName: "Blank")
        let blankName = CustomFilmTestSupport.makeCustomFilm(id: "no-name", stockName: " ")
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
        let film = CustomFilmTestSupport.makeCustomFilm(id: "film-7")
        library.add(film)
        XCTAssertEqual(library.film(withID: "film-7")?.id, "film-7")
        XCTAssertNil(library.film(withID: "missing"))
    }

    // MARK: - Helpers

}
