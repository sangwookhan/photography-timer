import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-159: the app-derived / fitted comparison section is separate
/// from Source reference. It compares the app's guarded formula against
/// the published source anchors (Fomapan 100 is the representative
/// case) and must never appear for profiles without comparison data.
final class ReciprocityModelComparisonPresenterTests: XCTestCase {

    private let presenter = ReciprocityModelComparisonPresenter()
    private let format: (Double) -> String = { String(format: "%.0fs", $0) }

    func testFomapanTableDefaultHasNoComparison() throws {
        // The catalog default is the official table (no formula), so it
        // reproduces the anchors exactly — there is nothing to compare.
        let film = try XCTUnwrap(film(named: "Fomapan 100 Classic"))
        XCTAssertNil(presenter.comparisonSection(for: film.profiles[0], formatDuration: format))
    }

    func testFomapan100AppDerivedFormulaComparisonReportsPercentAndStopDeltas() throws {
        // The comparison belongs to the app-derived FORMULA model, which
        // deviates from the official anchors.
        let appFormula = AlternateReciprocityModels.fomapan100AppDerivedFormula
        let section = try XCTUnwrap(
            presenter.comparisonSection(for: appFormula, formatDuration: format),
            "The app-derived formula model carries source anchors and must produce a comparison."
        )

        XCTAssertEqual(section.title, "App-derived comparison")

        let joined = section.rows.map(\.value).joined(separator: "\n")
        // Published anchors: 1s→2s, 10s→80s, 100s→1600s against
        // Tc = 2.2457 × Tm^1.4515.
        XCTAssertTrue(joined.contains("+12.3%"), "1 s / 100 s anchors sit ~+1/6 stop above the app fit: \(joined)")
        XCTAssertTrue(joined.contains("+0.167 stop"), joined)
        XCTAssertTrue(joined.contains("-20.6%"), "10 s anchor sits ~-1/3 stop below the app fit: \(joined)")
        XCTAssertTrue(joined.contains("-0.333 stop"), joined)
    }

    func testComparisonCarriesAppDerivedCaveatNotManufacturerGuidance() throws {
        let appFormula = AlternateReciprocityModels.fomapan100AppDerivedFormula
        let section = try XCTUnwrap(presenter.comparisonSection(for: appFormula, formatDuration: format))

        let joined = section.rows.map(\.value).joined(separator: "\n")
        XCTAssertTrue(
            joined.contains("Not manufacturer-published guidance."),
            "The comparison must explicitly disclaim manufacturer authorship of the app-derived deltas: \(joined)"
        )
    }

    func testFormulaProfileWithoutSourceAnchorsHasNoComparison() throws {
        // HP5 Plus is a manufacturer-formula profile with no published
        // source-evidence anchors, so there is nothing to compare.
        let film = try XCTUnwrap(film(named: "HP5 Plus"))
        XCTAssertNil(presenter.comparisonSection(for: film.profiles[0], formatDuration: format))
    }

    func testLimitedGuidanceProfileHasNoComparison() throws {
        let film = try XCTUnwrap(film(named: "Ektar 100"))
        XCTAssertNil(presenter.comparisonSection(for: film.profiles[0], formatDuration: format))
    }

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName }
    }
}
