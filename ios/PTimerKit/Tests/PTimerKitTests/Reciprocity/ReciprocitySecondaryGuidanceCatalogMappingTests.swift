// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore

/// PTIMER-88 follow-up regression: drives the secondary-guidance formatter
/// directly off `LaunchPresetFilmCatalogV2.films` so the wire from real
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

    private struct MappingCase {
        let film: String
        var colorCorrectionValues: [String] = []
        var colorCorrectionRequiresDetail = false
        var requiresStopWarning = false
        var developmentValues: [String] = []
        var forbidsColorCorrection = false
    }

    private let cases: [MappingCase] = [
        MappingCase(film: "Velvia 50", colorCorrectionValues: ["5M", "7.5M"], requiresStopWarning: true),
        MappingCase(film: "Provia 100F", colorCorrectionValues: ["2.5G"], requiresStopWarning: true),
        MappingCase(film: "Ektachrome E100", colorCorrectionValues: ["CC10R"], colorCorrectionRequiresDetail: true),
        MappingCase(film: "Tri-X 400", developmentValues: ["-10% development", "-20% development", "-30% development"], forbidsColorCorrection: true),
    ]

    /// The published catalog adjustments still wire through the
    /// secondary-guidance formatter into the expected rows for each
    /// representative film. Film identity and its published notation are
    /// case data; the formatter classification is the shared contract.
    func testCatalogSecondaryGuidanceMapsToExpectedRows() throws {
        for c in cases {
            let film = try XCTUnwrap(film(named: c.film), "\(c.film) must remain in the launch catalog.")
            let rows = formattedSecondaryGuidance(for: film)
            let colorRows = rows.filter { $0.kind == .colorCorrection }
            let colorValues = colorRows.compactMap(\.valueText)

            for value in c.colorCorrectionValues {
                XCTAssertTrue(colorValues.contains(value), "\(c.film): must surface the published \(value) color correction. Got \(colorValues).")
            }
            for row in colorRows {
                XCTAssertEqual(row.severity, .neutral, "\(c.film): color correction severity")
                XCTAssertEqual(row.title, "Color correction", "\(c.film): color correction title")
            }
            if c.colorCorrectionRequiresDetail {
                let row = try XCTUnwrap(colorRows.first { c.colorCorrectionValues.contains($0.valueText ?? "") }, "\(c.film): expected a color-correction row with detail.")
                XCTAssertFalse(row.detailText.isEmpty, "\(c.film): color-correction guidance must propagate its note into detailText.")
            }
            if c.forbidsColorCorrection {
                XCTAssertTrue(colorRows.isEmpty, "\(c.film): has no published color-correction guidance; the formatter must not invent one.")
            }

            if c.requiresStopWarning {
                let stopWarnings = rows.filter { $0.kind == .warning && $0.severity == .stop }
                XCTAssertFalse(stopWarnings.isEmpty, "\(c.film): must surface its published not-recommended stop signal as a warning row.")
                for row in stopWarnings {
                    XCTAssertNil(row.valueText, "\(c.film): warning rows must not advertise a notation value.")
                    XCTAssertFalse(row.detailText.isEmpty, "\(c.film): warning rows must carry the source message text.")
                }
            }

            let devRows = rows.filter { $0.kind == .developmentAdjustment }
            let devValues = devRows.compactMap(\.valueText)
            for value in c.developmentValues {
                XCTAssertTrue(devValues.contains(value), "\(c.film): must surface the published \(value) instruction. Got \(devValues).")
            }
            for row in devRows {
                XCTAssertEqual(row.severity, .neutral, "\(c.film): development severity")
                XCTAssertEqual(row.title, "Development adjustment", "\(c.film): development title")
                XCTAssertNotEqual(row.kind, .colorCorrection, "\(c.film): development must never be classified as color correction.")
            }
        }
    }

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalogV2.films.first { $0.canonicalStockName == canonicalStockName }
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
