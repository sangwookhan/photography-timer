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

    // Same contract — a profile with nothing to compare yields no
    // comparison section — across films/profiles as case data; each
    // case names the reason and the failure message carries the stock.
    func testProfilesWithNothingToCompareHaveNoComparisonSection() throws {
        struct Case { let stock: String; let why: String }
        let cases: [Case] = [
            Case(stock: "Fomapan 100 Classic", why: "official table default reproduces the anchors exactly"),
            Case(stock: "HP5 Plus", why: "manufacturer formula with no published source anchors"),
            Case(stock: "Ektar 100", why: "limited-guidance profile"),
        ]
        for c in cases {
            let film = try XCTUnwrap(film(named: c.stock))
            XCTAssertNil(
                presenter.comparisonSection(for: film.profiles[0], formatDuration: format),
                "\(c.stock) (\(c.why)) must have no comparison section"
            )
        }
    }

    func testMultiModelAppDerivedFormulaComparisonReportsPercentAndStopDeltas() throws {
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

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName }
    }
}
