// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-169 Phase 1 baseline pins for the special / range /
/// limited-guidance source-shape profiles.
///
/// Phase 1 is a metadata and presentation honesty change: it must not
/// move a single corrected-exposure value, fabricate a quantified
/// prediction for a limited-guidance profile, or flatten range-valued
/// source rows into exact anchors. These tests pin the current
/// calculation output and source-evidence shape for the thirteen
/// PTIMER-169 target profiles so any accidental behavior change in
/// the metadata/presentation work surfaces as a failure here.
final class SourceShapePreservationBaselineTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    /// One pinned evaluation: a stock at a metered exposure must keep
    /// producing exactly this corrected exposure.
    private struct CorrectedValuePin {
        let stock: String
        let metered: Double
        let corrected: Double

        init(_ stock: String, _ metered: Double, _ corrected: Double) {
            self.stock = stock
            self.metered = metered
            self.corrected = corrected
        }
    }

    // MARK: - 1. Quantified corrected values stay exactly where they are

    /// Representative in-source-range inputs for every special-shape
    /// profile that currently produces a quantified formula result.
    private let quantifiedPins: [CorrectedValuePin] = [
        // Acros II encodes the published 120–1000 s +1/2 stop range
        // rule as Tc = √2 × Tm.
        CorrectedValuePin("Acros II", 120, 169.7056274847714),
        CorrectedValuePin("Acros II", 240, 339.4112549695428),
        CorrectedValuePin("Acros II", 1000, 1414.213562373095),
        // Fujifilm slide films: fitted formulas through published rows.
        CorrectedValuePin("Velvia 50", 4, 5.1486706970489395),
        CorrectedValuePin("Velvia 50", 32, 60.15029884271631),
        CorrectedValuePin("Velvia 100", 240, 347.3606680860101),
        CorrectedValuePin("Provia 100F", 240, 302.3893624325641),
        // Rollei range-valued-row films: free fit through the four
        // quantified rows.
        CorrectedValuePin("RETRO 80S", 4, 8.074968230824046),
        CorrectedValuePin("RETRO 80S", 30, 178.37025330742412),
        CorrectedValuePin("SUPERPAN 200", 15, 61.504975909344836),
        // ADOX sparse/special anchors.
        CorrectedValuePin("CMS 20 II", 10, 20.000000631965317),
    ]

    func testSpecialShapeProfilesReproduceCurrentQuantifiedValues() throws {
        for pin in quantifiedPins {
            let result = evaluator.evaluate(
                profile: try profile(pin.stock),
                meteredExposureSeconds: pin.metered
            )
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "\(pin.stock) at \(pin.metered) s must stay formula-derived in Phase 1."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                pin.corrected,
                accuracy: 1e-6,
                "\(pin.stock) at \(pin.metered) s corrected exposure must not move."
            )
        }
    }

    /// Beyond the published source range the formula keeps producing a
    /// numeric continuation classified as unsupported. Those values
    /// must not move either.
    private let beyondRangePins: [CorrectedValuePin] = [
        CorrectedValuePin("Velvia 50", 64, 136.48513298595844),
        CorrectedValuePin("Velvia 100", 480, 835.7864710601414),
        CorrectedValuePin("Provia 100F", 480, 780.288365467848),
        CorrectedValuePin("CMS 20 II", 100, 282.84272282391646),
    ]

    func testSpecialShapeProfilesReproduceCurrentBeyondRangeValues() throws {
        for pin in beyondRangePins {
            let result = evaluator.evaluate(
                profile: try profile(pin.stock),
                meteredExposureSeconds: pin.metered
            )
            guard case let .unsupported(payload) = result else {
                XCTFail("\(pin.stock) at \(pin.metered) s must stay beyond-source-range unsupported.")
                continue
            }
            let corrected = try XCTUnwrap(payload.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                pin.corrected,
                accuracy: 1e-6,
                "\(pin.stock) at \(pin.metered) s formula continuation must not move."
            )
        }
    }

    /// No-correction bands stay where the source put them.
    func testSpecialShapeProfilesKeepNoCorrectionBands() throws {
        let noCorrectionPins: [(stock: String, metered: Double)] = [
            ("Acros II", 60),
            ("Velvia 50", 1),
            ("Velvia 100", 60),
            ("Provia 100F", 128),
            ("RETRO 80S", 0.5),
            ("SUPERPAN 200", 0.5),
            ("CMS 20 II", 1),
        ]
        for pin in noCorrectionPins {
            let result = evaluator.evaluate(
                profile: try profile(pin.stock),
                meteredExposureSeconds: pin.metered
            )
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "\(pin.stock) at \(pin.metered) s must stay no-correction."
            )
            XCTAssertEqual(
                result.correctedExposureSeconds ?? -1,
                pin.metered,
                accuracy: 1e-9,
                "\(pin.stock) no-correction must return the metered exposure unchanged."
            )
        }
    }

    // MARK: - 2. Limited guidance stays value-less

    private let limitedGuidancePins: [(stock: String, metered: Double)] = [
        ("Ektar 100", 4),
        ("Gold 200", 4),
        ("Ultra Max 400", 4),
        ("Portra 160", 30),
        ("Portra 400", 30),
        ("Ektachrome E100", 30),
    ]

    func testLimitedGuidanceProfilesStayValueLessBeyondThreshold() throws {
        for pin in limitedGuidancePins {
            let result = evaluator.evaluate(
                profile: try profile(pin.stock),
                meteredExposureSeconds: pin.metered
            )
            guard case .limitedGuidance = result else {
                XCTFail("\(pin.stock) at \(pin.metered) s must stay limited guidance.")
                continue
            }
            XCTAssertNil(
                result.correctedExposureSeconds,
                "\(pin.stock) limited guidance must never fabricate a corrected exposure."
            )
            XCTAssertFalse(
                result.hasCalculatedExposureTime,
                "\(pin.stock) limited guidance must not advertise a calculated exposure time."
            )
        }
    }

    func testLimitedGuidanceProfilesKeepThresholdNoCorrection() throws {
        for pin in limitedGuidancePins {
            let result = evaluator.evaluate(
                profile: try profile(pin.stock),
                meteredExposureSeconds: 0.5
            )
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "\(pin.stock) at 0.5 s must stay threshold no-correction."
            )
        }
    }

    // MARK: - 3. Not-recommended stop signals stay present as source evidence

    /// One published manufacturer stop signal: a `notRecommended`
    /// warning row (no exposure adjustment) at a boundary.
    private struct StopSignalPin {
        let stock: String
        let boundarySeconds: Double
        let message: String

        init(_ stock: String, _ boundarySeconds: Double, _ message: String) {
            self.stock = stock
            self.boundarySeconds = boundarySeconds
            self.message = message
        }
    }

    /// Manufacturer stop signals for the slide films and CMS 20 II.
    private let stopSignalPins: [StopSignalPin] = [
        StopSignalPin("Velvia 50", 64, "64 sec is not recommended."),
        StopSignalPin("Provia 100F", 480, "8 min is not recommended."),
        StopSignalPin("CMS 20 II", 100, "100 sec is not recommended."),
    ]

    func testNotRecommendedBoundaryRowsRemainPresent() throws {
        for pin in stopSignalPins {
            let profile = try profile(pin.stock)
            let boundaryRow = profile.sourceEvidence.first { row in
                guard case let .exactSeconds(seconds) = row.meteredExposure else { return false }
                return seconds == pin.boundarySeconds
                    && ReciprocitySourceEvidenceClassifier.isGuidanceBoundary(row)
            }
            let row = try XCTUnwrap(
                boundaryRow,
                "\(pin.stock) must keep its \(pin.boundarySeconds) s not-recommended boundary row."
            )
            let message = row.adjustments.compactMap { adjustment -> String? in
                guard case let .warning(warning) = adjustment,
                      warning.severity == .notRecommended else { return nil }
                return warning.message
            }.first
            XCTAssertEqual(message, pin.message, "\(pin.stock) stop-signal message")
        }
    }

    // MARK: - 4. Range-valued rows stay ranges, not exact anchors

    /// Rollei publishes the 1 s and 2 s rows as corrected RANGES
    /// ("1 to 2 sec", "3 to 4 sec"). They are preserved as note-only
    /// source evidence and must never gain an exact corrected-time /
    /// stop-delta / multiplier adjustment.
    func testRolleiRangeValuedRowsAreNotFlattenedIntoExactAnchors() throws {
        for stock in ["RETRO 80S", "SUPERPAN 200"] {
            let profile = try profile(stock)
            for rangeRowSeconds in [1.0, 2.0] {
                let row = try XCTUnwrap(
                    profile.sourceEvidence.first { row in
                        guard case let .exactSeconds(seconds) = row.meteredExposure else { return false }
                        return seconds == rangeRowSeconds
                    },
                    "\(stock) must keep its \(rangeRowSeconds) s range-valued source row."
                )
                XCTAssertFalse(
                    row.adjustments.contains { adjustment in
                        if case .exposure = adjustment { return true }
                        return false
                    },
                    "\(stock) \(rangeRowSeconds) s row publishes a corrected RANGE and must not carry an exact exposure adjustment."
                )
                XCTAssertTrue(
                    row.adjustments.contains { adjustment in
                        if case .note = adjustment { return true }
                        return false
                    },
                    "\(stock) \(rangeRowSeconds) s row must preserve the published range as a note."
                )
            }
        }
    }

    // MARK: - 5. Phase 1 does not migrate the calculation model

    /// Phase 1 guard only. PTIMER-169 deliberately keeps the fitted
    /// formula as these profiles' default calculation; a later
    /// Fujifilm / Rollei / CMS table/range-policy migration ticket is
    /// expected to flip the calculation model and UPDATE this test
    /// alongside it. App-derived formula evaluation stays in
    /// PTIMER-170 either way.
    func testSpecialShapeProfilesKeepFormulaCalculationInPhase1() throws {
        let formulaStocks = [
            "Acros II", "Velvia 50", "Velvia 100", "Provia 100F",
            "RETRO 80S", "SUPERPAN 200", "CMS 20 II",
        ]
        for stock in formulaStocks {
            let profile = try profile(stock)
            XCTAssertTrue(
                profile.rules.contains { if case .formula = $0 { return true }; return false },
                "\(stock) keeps its formula rule in Phase 1 (migration is a later decision)."
            )
            XCTAssertFalse(
                profile.usesTableInterpolation,
                "\(stock) must not gain a table-interpolation rule in Phase 1."
            )
        }
    }

    // MARK: - Helpers

    private func profile(
        _ stock: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ReciprocityProfile {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == stock },
            "\(stock) must remain in the launch catalog.",
            file: file,
            line: line
        )
        return try XCTUnwrap(film.profiles.first, file: file, line: line)
    }
}
