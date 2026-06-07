import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

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

    func testFomapanDefaultIsManufacturerTableLogLogInterpolation() throws {
        let film = try XCTUnwrap(film(named: "Fomapan 100 Classic"))
        let section = presenter.metadataSection(film: film, profile: film.profiles[0])
        XCTAssertEqual(value(section, "Source"), "Manufacturer table")
        XCTAssertEqual(
            value(section, "Calculation"),
            "Log-log table interpolation",
            "Fomapan's default official model is the log-log table, surfaced honestly (never a bare 'lookup')."
        )
    }

    func testFomapanAppDerivedAlternateReadsAppDerivedGuardedFormula() throws {
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
