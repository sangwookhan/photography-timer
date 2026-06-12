import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-159: the compact "Reciprocity model" Details section reports
/// Source + Calculation for the active model. Film is the sheet header
/// and authority is the subtitle, so they are not repeated here.
final class ReciprocityModelMetadataPresenterTests: XCTestCase {

    private let presenter = ReciprocityModelMetadataPresenter()

    func testSectionIsCompactSourceAndCalculationOnly() throws {
        let film = try XCTUnwrap(film(named: "HP5 Plus"))
        let section = presenter.metadataSection(film: film, profile: film.profiles[0])

        XCTAssertEqual(section.title, "Reciprocity model")
        XCTAssertEqual(section.rows.map(\.title), ["Source", "Calculation"])
    }

    func testManufacturerFormulaProfileMapsToGuardedFormula() throws {
        let film = try XCTUnwrap(film(named: "HP5 Plus"))
        let section = presenter.metadataSection(film: film, profile: film.profiles[0])
        XCTAssertEqual(value(section, "Source"), "Manufacturer formula")
        XCTAssertEqual(value(section, "Calculation"), "Guarded formula")
    }

    func testMultiModelDefaultIsManufacturerTableLogLogInterpolation() throws {
        let film = try XCTUnwrap(film(named: "Fomapan 100 Classic"))
        let section = presenter.metadataSection(film: film, profile: film.profiles[0])
        XCTAssertEqual(value(section, "Source"), "Manufacturer table")
        XCTAssertEqual(
            value(section, "Calculation"),
            "Log-log table interpolation",
            "Fomapan's default official model is the log-log table, surfaced honestly (never a bare 'lookup')."
        )
    }

    func testMultiModelAppDerivedAlternateReadsAppDerivedGuardedFormula() throws {
        let film = try XCTUnwrap(film(named: "Fomapan 100 Classic"))
        let alternate = AlternateReciprocityModels.fomapan100AppDerivedFormula
        let section = presenter.metadataSection(film: film, profile: alternate)
        XCTAssertEqual(value(section, "Source"), "Manufacturer table")
        XCTAssertEqual(value(section, "Calculation"), "App-derived guarded formula")
    }

    func testManufacturerLimitedGuidanceProfile() throws {
        let film = try XCTUnwrap(film(named: "Ektar 100"))
        let section = presenter.metadataSection(film: film, profile: film.profiles[0])
        XCTAssertEqual(value(section, "Source"), "Manufacturer limited guidance")
        XCTAssertEqual(value(section, "Calculation"), "Limited guidance — no quantified prediction")
    }

    // MARK: - Tri-X 400 graph/table vs table distinction (PTIMER-168 follow-up)

    func testTriXModelsDistinguishGraphTableFromPublishedTable() throws {
        let film = try XCTUnwrap(film(named: "Tri-X 400"))

        // Default: the graph-extended anchor set.
        let graphTable = presenter.metadataSection(film: film, profile: film.profiles[0])
        XCTAssertEqual(value(graphTable, "Source"), "Manufacturer graph/table")
        XCTAssertEqual(value(graphTable, "Calculation"), "Log-log table interpolation")

        // Alternate: the published rows only.
        let officialTable = try XCTUnwrap(
            AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")
                .first { $0.id == "kodak-tri-x-official-table" }
        )
        let officialSection = presenter.metadataSection(film: film, profile: officialTable)
        XCTAssertEqual(value(officialSection, "Source"), "Manufacturer table")
        XCTAssertEqual(value(officialSection, "Calculation"), "Log-log table interpolation")

        // Alternate: the app-derived fit keeps the graph/table source.
        let appFormula = try XCTUnwrap(
            AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")
                .first { $0.id == "kodak-tri-x-app-formula" }
        )
        let appSection = presenter.metadataSection(film: film, profile: appFormula)
        XCTAssertEqual(value(appSection, "Source"), "Manufacturer graph/table")
        XCTAssertEqual(value(appSection, "Calculation"), "App-derived guarded formula")
    }

    // MARK: - PTIMER-169 special source shapes

    func testRangeGuidanceProfileReadsManufacturerRangeGuidance() throws {
        // Acros II's source is Fujifilm's published 120–1000 s range
        // rule; the formula encodes it verbatim. The Details section
        // must read "Manufacturer range guidance" (never "Manufacturer
        // table") and the calculation must not imply an app-derived fit.
        let film = try XCTUnwrap(film(named: "Acros II"))
        let section = presenter.metadataSection(film: film, profile: film.profiles[0])
        XCTAssertEqual(value(section, "Source"), "Manufacturer range guidance")
        XCTAssertEqual(value(section, "Calculation"), "Guarded formula")
    }

    func testTableSourceProfilesWithFittedFormulaReadAppDerived() throws {
        // Fujifilm slide films, Rollei range-valued-row films, and CMS
        // 20 II keep their fitted formula in Phase 1; Details must say
        // so honestly: table-shaped source, app-derived calculation.
        for stock in ["Velvia 50", "Velvia 100", "Provia 100F", "RETRO 80S", "SUPERPAN 200", "CMS 20 II"] {
            let film = try XCTUnwrap(film(named: stock))
            let section = presenter.metadataSection(film: film, profile: film.profiles[0])
            XCTAssertEqual(value(section, "Source"), "Manufacturer table", stock)
            XCTAssertEqual(value(section, "Calculation"), "App-derived guarded formula", stock)
        }
    }

    func testAllLimitedGuidanceProfilesReadLimitedGuidance() throws {
        // The five Kodak profiles that gained an explicit declaration
        // in PTIMER-169 read identically to Ektar 100 above.
        for stock in ["Portra 160", "Portra 400", "Gold 200", "Ultra Max 400", "Ektachrome E100"] {
            let film = try XCTUnwrap(film(named: stock))
            let section = presenter.metadataSection(film: film, profile: film.profiles[0])
            XCTAssertEqual(value(section, "Source"), "Manufacturer limited guidance", stock)
            XCTAssertEqual(
                value(section, "Calculation"),
                "Limited guidance — no quantified prediction",
                stock
            )
        }
    }

    func testUnofficialPracticalProfileMapsToPracticalGuidance() throws {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        let film = try XCTUnwrap(film(named: "Portra 400"))
        let section = presenter.metadataSection(film: film, profile: profile)
        XCTAssertEqual(value(section, "Source"), "Practical / community guidance")
        XCTAssertEqual(value(section, "Calculation"), "Guarded formula")
    }

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName }
    }

    private func value(_ section: FilmModeDetailsSectionState, _ title: String) -> String? {
        section.rows.first { $0.title == title }?.value
    }
}
