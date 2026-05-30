import XCTest
@testable import PTimer

/// PTIMER-88 follow-up regression: drives the secondary-guidance formatter
/// directly off `LaunchPresetFilmCatalog.films` so the wire from real
/// preset data through `[ReciprocityAdjustment]` into
/// `ReciprocitySecondaryGuidancePresentation` rows stays intact for the
/// representative slide / negative / black-and-white films.
///
/// These tests intentionally do not duplicate notation-level coverage that
/// already lives in `SecondaryGuidancePresentationTests`; they
/// only verify that the published catalog still carries the expected
/// notation and that the formatter classifies it into the right category
/// without rewriting its text.
final class SecondaryGuidanceCatalogMappingTests: XCTestCase {

    // MARK: - Velvia 50 (Fujifilm slide film)

    func testVelvia50CatalogMapsMagentaColorCorrectionsAndStopSignal() throws {
        let film = try XCTUnwrap(film(named: "Velvia 50"))
        let rows = formattedSecondaryGuidance(for: film)

        let colorRows = rows.filter { $0.kind == .colorCorrection }
        let colorValues = colorRows.compactMap(\.valueText)

        XCTAssertTrue(
            colorValues.contains("5M"),
            "Velvia 50 should still surface the published 5M magenta correction. Got \(colorValues)."
        )
        XCTAssertTrue(
            colorValues.contains("7.5M"),
            "Velvia 50 should preserve the decimal 7.5M magenta correction verbatim. Got \(colorValues)."
        )
        for row in colorRows {
            XCTAssertEqual(row.severity, .neutral)
            XCTAssertEqual(row.title, "Color correction")
        }

        let stopWarnings = rows.filter { $0.kind == .warning && $0.severity == .stop }
        XCTAssertFalse(
            stopWarnings.isEmpty,
            "Velvia 50 must still surface its published not-recommended stop signal as a warning row."
        )
        for row in stopWarnings {
            XCTAssertNil(row.valueText, "Warning rows must not advertise a notation value.")
            XCTAssertFalse(row.detailText.isEmpty, "Warning rows must carry the source message text.")
        }
    }

    // MARK: - Provia 100F (Fujifilm slide film)

    func testProvia100FCatalogMapsGreenColorCorrectionAndStopSignal() throws {
        let film = try XCTUnwrap(film(named: "Provia 100F"))
        let rows = formattedSecondaryGuidance(for: film)

        let greenCorrection = rows.first {
            $0.kind == .colorCorrection && $0.valueText == "2.5G"
        }
        XCTAssertNotNil(
            greenCorrection,
            "Provia 100F must still surface the published 2.5G correction as color-correction guidance."
        )
        XCTAssertEqual(greenCorrection?.severity, .neutral)
        XCTAssertEqual(greenCorrection?.title, "Color correction")

        let stopWarnings = rows.filter { $0.kind == .warning && $0.severity == .stop }
        XCTAssertFalse(
            stopWarnings.isEmpty,
            "Provia 100F must still surface its published not-recommended stop signal as a warning row."
        )
    }

    // MARK: - Ektachrome E100 (Kodak slide film)

    func testEktachromeE100CatalogMapsCC10RColorCorrectionWithDetail() throws {
        let film = try XCTUnwrap(film(named: "Ektachrome E100"))
        let rows = formattedSecondaryGuidance(for: film)

        let cc10R = rows.first {
            $0.kind == .colorCorrection && $0.valueText == "CC10R"
        }
        XCTAssertNotNil(
            cc10R,
            "Ektachrome E100 must surface the published CC10R Kodak filtration guidance as color-correction. Rows = \(rows.map(\.valueText))."
        )
        XCTAssertEqual(cc10R?.severity, .neutral)
        XCTAssertEqual(cc10R?.title, "Color correction")
        XCTAssertFalse(
            cc10R?.detailText.isEmpty ?? true,
            "Ektachrome E100 CC10R guidance carries an explanatory note in the catalog; it must propagate into detailText."
        )
    }

    // MARK: - Tri-X 400 (Kodak black-and-white)

    func testTriX400CatalogMapsDevelopmentAdjustmentsAndNeverAsColorCorrection() throws {
        let film = try XCTUnwrap(film(named: "Tri-X 400"))
        let rows = formattedSecondaryGuidance(for: film)

        let devRows = rows.filter { $0.kind == .developmentAdjustment }
        let devValues = devRows.compactMap(\.valueText)

        for expected in ["-10% development", "-20% development", "-30% development"] {
            XCTAssertTrue(
                devValues.contains(expected),
                "Tri-X 400 must still surface published \(expected) instruction as a development-adjustment row. Got \(devValues)."
            )
        }
        for row in devRows {
            XCTAssertEqual(row.severity, .neutral)
            XCTAssertEqual(row.title, "Development adjustment")
            XCTAssertNotEqual(
                row.kind,
                .colorCorrection,
                "Development adjustments must never be classified as color correction."
            )
        }

        XCTAssertFalse(
            rows.contains { $0.kind == .colorCorrection },
            "Tri-X 400 has no published color-correction guidance; the formatter must not invent one."
        )
    }

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName }
    }

    private func formattedSecondaryGuidance(
        for film: FilmIdentity
    ) -> [ReciprocitySecondaryGuidancePresentation] {
        let adjustments = film.profiles.flatMap { profile -> [ReciprocityAdjustment] in
            let ruleAdjustments = profile.rules.flatMap(adjustments(in:))
            let evidenceAdjustments = profile.sourceEvidence.flatMap(\.adjustments)
            return ruleAdjustments + evidenceAdjustments
        }
        return ReciprocitySecondaryGuidanceFormatter.format(adjustments)
    }

    private func adjustments(in rule: ReciprocityRule) -> [ReciprocityAdjustment] {
        switch rule {
        case let .threshold(threshold):
            return threshold.adjustments
        case let .formula(formula):
            return formula.additionalAdjustments
        case let .limitedGuidance(rule):
            return rule.adjustments
        case let .tableInterpolation(rule):
            return rule.additionalAdjustments
        }
    }
}
