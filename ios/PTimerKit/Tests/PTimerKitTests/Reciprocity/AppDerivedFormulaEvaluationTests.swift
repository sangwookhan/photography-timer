// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-170 evaluation fixture for app-derived formula candidates.
///
/// Evaluates a free log-log modified-Schwarzschild fit
/// (`Tc = a × Tm^p`) against each PTIMER-168 migrated table profile's
/// published anchors and locks the fitted constants, the worst anchor
/// residual (in stops), and the resulting ship/no-ship decision. The
/// fit is recomputed from the live catalog anchors at test time, so a
/// later anchor correction invalidates the recorded decision instead
/// of silently drifting away from it.
///
/// Decision policy (PTIMER-170):
/// - worst |stop error| ≤ 0.1     → eligible for an app-derived alternate
/// - 0.1 < worst |stop error| ≤ 0.25 → borderline; document only
/// - worst |stop error| > 0.25    → poor/unsafe fit; document only
///
/// Tri-X 400 and Fomapan 100 Classic already ship app-derived
/// alternates (PTIMER-168 / PTIMER-164) and are not re-evaluated here.
final class AppDerivedFormulaEvaluationTests: XCTestCase {

    private enum Decision: String {
        case add
        case borderlineDocumentOnly
        case poorFitDocumentOnly
    }

    /// Fitted-formula constants PTIMER-168 retired from the catalog
    /// when these profiles migrated to table calculation, preserved as
    /// executable fixture data per the PTIMER-167 storage decision
    /// ("preserve fitted values in test fixtures for PTIMER-170").
    /// Five retired fits were plain free log-log fits and reproduce
    /// from the current anchors (`reproducesViaFreeFit`); the two
    /// T-MAX fits used different anchoring schemes (T-MAX 100 is
    /// referenced to 0.1 s, T-MAX 400 used a 1 s threshold) and are
    /// pinned by evaluating the retired formula directly instead.
    private struct RetiredFit {
        let coefficient: Double
        let referenceMeteredTimeSeconds: Double
        let exponent: Double
        let noCorrectionThroughSeconds: Double
        let reproducesViaFreeFit: Bool

        init(
            coefficient: Double = 1,
            referenceMeteredTimeSeconds: Double = 1,
            exponent: Double,
            noCorrectionThroughSeconds: Double,
            reproducesViaFreeFit: Bool
        ) {
            self.coefficient = coefficient
            self.referenceMeteredTimeSeconds = referenceMeteredTimeSeconds
            self.exponent = exponent
            self.noCorrectionThroughSeconds = noCorrectionThroughSeconds
            self.reproducesViaFreeFit = reproducesViaFreeFit
        }

        var formula: ReciprocityFormula {
            ReciprocityFormula(
                coefficientSeconds: coefficient,
                referenceMeteredTimeSeconds: referenceMeteredTimeSeconds,
                exponent: exponent,
                noCorrectionThroughSeconds: noCorrectionThroughSeconds
            )
        }
    }

    private struct Candidate {
        let stock: String
        /// Pinned free log-log fit through the catalog anchors.
        let coefficient: Double
        let exponent: Double
        /// Pinned worst |stop error| across the published anchors.
        let worstStopError: Double
        let decision: Decision
        let retiredFit: RetiredFit

        init(
            _ stock: String,
            coefficient: Double,
            exponent: Double,
            worstStopError: Double,
            decision: Decision,
            retiredFit: RetiredFit
        ) {
            self.stock = stock
            self.coefficient = coefficient
            self.exponent = exponent
            self.worstStopError = worstStopError
            self.decision = decision
            self.retiredFit = retiredFit
        }
    }

    /// The PTIMER-170 evaluation record. Constants and residuals are
    /// derived from the catalog anchors (verified by the tests below);
    /// decisions follow the policy thresholds.
    private let candidates: [Candidate] = [
        Candidate(
            "CHS 100 II",
            coefficient: 1.210218, exponent: 1.342265,
            worstStopError: 0.0402,
            decision: .add,
            retiredFit: RetiredFit(
                coefficient: 1.2102, exponent: 1.3423,
                noCorrectionThroughSeconds: 1,
                reproducesViaFreeFit: true
            )
        ),
        Candidate(
            "T-MAX 100",
            coefficient: 1.236360, exponent: 1.100343,
            worstStopError: 0.0545,
            decision: .add,
            // Retired: Tc = 0.1 × (Tm / 0.1)^1.0966 — referenced to
            // the 0.1 s no-correction knee, not a free fit.
            retiredFit: RetiredFit(
                coefficient: 0.1, referenceMeteredTimeSeconds: 0.1,
                exponent: 1.0966,
                noCorrectionThroughSeconds: 0.1,
                reproducesViaFreeFit: false
            )
        ),
        Candidate(
            "Fomapan 200 Creative",
            coefficient: 3.209740, exponent: 1.389076,
            worstStopError: 0.1950,
            decision: .borderlineDocumentOnly,
            retiredFit: RetiredFit(
                coefficient: 3.2107, exponent: 1.3891,
                noCorrectionThroughSeconds: 0.5,
                reproducesViaFreeFit: true
            )
        ),
        Candidate(
            "T-MAX 400",
            coefficient: 1.155570, exponent: 1.188389,
            worstStopError: 0.2495,
            decision: .borderlineDocumentOnly,
            // Retired: Tc = Tm^1.2261 with a 1 s threshold, so the
            // published 1 s row sat inside its no-correction band.
            retiredFit: RetiredFit(
                exponent: 1.2261,
                noCorrectionThroughSeconds: 1,
                reproducesViaFreeFit: false
            )
        ),
        Candidate(
            "RPX 100",
            coefficient: 0.924311, exponent: 1.465046,
            worstStopError: 0.2882,
            decision: .poorFitDocumentOnly,
            retiredFit: RetiredFit(
                coefficient: 0.9248, exponent: 1.4652,
                noCorrectionThroughSeconds: 1,
                reproducesViaFreeFit: true
            )
        ),
        Candidate(
            "RPX 400",
            coefficient: 1.770810, exponent: 1.240573,
            worstStopError: 0.3830,
            decision: .poorFitDocumentOnly,
            retiredFit: RetiredFit(
                coefficient: 1.7708, exponent: 1.2404,
                noCorrectionThroughSeconds: 0.5,
                reproducesViaFreeFit: true
            )
        ),
        Candidate(
            "Fomapan 400 Action",
            coefficient: 1.801405, exponent: 1.363499,
            worstStopError: 0.5283,
            decision: .poorFitDocumentOnly,
            retiredFit: RetiredFit(
                coefficient: 1.8022, exponent: 1.3635,
                noCorrectionThroughSeconds: 0.5,
                reproducesViaFreeFit: true
            )
        ),
    ]

    // MARK: - 1. Candidate list matches the migrated table-profile group

    func testCandidateListCoversAllUnshippedMigratedTableProfiles() throws {
        // PTIMER-170 evaluated the PTIMER-168 migrated table-default
        // profiles, minus the two films that already ship app-derived
        // alternates. Later table additions stay out of this fitted-
        // formula fixture until a dedicated follow-up evaluates them.
        let ptimer168MigratedStocks = [
            "Fomapan 200 Creative", "Fomapan 400 Action",
            "Tri-X 400", "T-MAX 100", "T-MAX 400",
            "RPX 100", "RPX 400", "CHS 100 II",
        ]
        let alreadyShipped = ["Tri-X 400", "Fomapan 100 Classic"]
        let migratedStocks = LaunchPresetFilmCatalog.films
            .filter {
                ptimer168MigratedStocks.contains($0.canonicalStockName)
                    && $0.profiles.first?.usesTableInterpolation == true
            }
            .map(\.canonicalStockName)
        XCTAssertEqual(
            Set(migratedStocks).subtracting(alreadyShipped),
            Set(candidates.map(\.stock)),
            "The evaluation record must cover exactly the migrated table profiles without a shipped app-derived alternate."
        )
    }

    // MARK: - 2. Fits and residuals reproduce from the live anchors

    func testFreeFitConstantsAndResidualsMatchEvaluationRecord() throws {
        for candidate in candidates {
            let anchors = try anchors(for: candidate.stock)
            let fit = Self.freeLogLogFit(anchors: anchors)
            XCTAssertEqual(
                fit.coefficient, candidate.coefficient, accuracy: 1e-4,
                "\(candidate.stock) fitted coefficient drifted from the evaluation record."
            )
            XCTAssertEqual(
                fit.exponent, candidate.exponent, accuracy: 1e-4,
                "\(candidate.stock) fitted exponent drifted from the evaluation record."
            )

            let worst = Self.worstAbsoluteStopError(
                coefficient: fit.coefficient,
                exponent: fit.exponent,
                anchors: anchors
            )
            XCTAssertEqual(
                worst, candidate.worstStopError, accuracy: 1e-3,
                "\(candidate.stock) worst anchor residual drifted from the evaluation record."
            )
        }
    }

    // MARK: - 3. Decisions follow the policy thresholds

    func testDecisionsFollowStopErrorPolicy() throws {
        for candidate in candidates {
            let expected: Decision
            if candidate.worstStopError <= 0.1 {
                expected = .add
            } else if candidate.worstStopError <= 0.25 {
                expected = .borderlineDocumentOnly
            } else {
                expected = .poorFitDocumentOnly
            }
            XCTAssertEqual(
                candidate.decision, expected,
                "\(candidate.stock) decision must follow the PTIMER-170 stop-error policy."
            )
        }
    }

    // MARK: - 4. Retired PTIMER-168 constants are preserved

    /// Five of the seven retired fits are plain free log-log fits, so
    /// the current anchors reproduce them (PTIMER-167's "preserve in
    /// test fixtures" storage decision is satisfied by derivation).
    func testRetiredFreeFitConstantsReproduceFromCurrentAnchors() throws {
        for candidate in candidates where candidate.retiredFit.reproducesViaFreeFit {
            let retired = candidate.retiredFit
            let fit = Self.freeLogLogFit(anchors: try anchors(for: candidate.stock))
            XCTAssertEqual(
                fit.coefficient, retired.coefficient, accuracy: 2e-3,
                "\(candidate.stock) retired coefficient must reproduce from the current anchors."
            )
            XCTAssertEqual(
                fit.exponent, retired.exponent, accuracy: 2e-3,
                "\(candidate.stock) retired exponent must reproduce from the current anchors."
            )
        }
    }

    /// The two T-MAX retired fits do not reproduce via the free fit
    /// (different anchoring schemes), so they are preserved as
    /// EXECUTABLE records instead: the retired formula is rebuilt from
    /// the fixture constants and its output is pinned at the published
    /// anchor inputs. T-MAX 400's 1 s threshold put the published 1 s
    /// row inside its no-correction band — preserved as-is.
    func testRetiredTmaxFormulasRemainExecutableRecords() throws {
        let pins: [(stock: String, outputs: [(metered: Double, corrected: Double)])] = [
            ("T-MAX 100", [(1, 1.249108), (10, 15.602709), (100, 194.894687)]),
            ("T-MAX 400", [(10, 16.830616), (100, 283.269620)]),
        ]
        for pin in pins {
            let candidate = try XCTUnwrap(candidates.first { $0.stock == pin.stock })
            let formula = candidate.retiredFit.formula
            XCTAssertTrue(
                formula.hasValidParameters,
                "\(pin.stock) retired formula record must stay a valid guarded formula."
            )
            for output in pin.outputs {
                guard case let .withinSourceRange(corrected) =
                    formula.evaluate(meteredExposureSeconds: output.metered) else {
                    XCTFail("\(pin.stock) retired formula at \(output.metered) s must produce a quantified value.")
                    continue
                }
                XCTAssertEqual(
                    corrected, output.corrected, accuracy: 1e-4,
                    "\(pin.stock) retired formula output at \(output.metered) s drifted from the preserved record."
                )
            }
        }

        // T-MAX 400's retired 1 s threshold: the published 1 s row sat
        // inside the no-correction band.
        let tmax400 = try XCTUnwrap(candidates.first { $0.stock == "T-MAX 400" })
        XCTAssertEqual(
            tmax400.retiredFit.formula.evaluate(meteredExposureSeconds: 1),
            .noCorrection,
            "T-MAX 400's retired formula treated 1 s as no correction."
        )
    }

    // MARK: - Fit helpers

    /// Least-squares fit of `ln Tc = ln a + p × ln Tm` through the
    /// published anchors — the same free log-log fit PTIMER-161/168
    /// used for the retired formulas and the shipped Fomapan 100
    /// app-derived alternate.
    private static func freeLogLogFit(
        anchors: [TableAnchor]
    ) -> (coefficient: Double, exponent: Double) {
        let xs = anchors.map { log($0.meteredSeconds) }
        let ys = anchors.map { log($0.correctedSeconds) }
        let n = Double(anchors.count)
        let sx = xs.reduce(0, +)
        let sy = ys.reduce(0, +)
        let sxx = xs.map { $0 * $0 }.reduce(0, +)
        let sxy = zip(xs, ys).map(*).reduce(0, +)
        let exponent = (n * sxy - sx * sy) / (n * sxx - sx * sx)
        let coefficient = exp((sy - exponent * sx) / n)
        return (coefficient, exponent)
    }

    private static func worstAbsoluteStopError(
        coefficient: Double,
        exponent: Double,
        anchors: [TableAnchor]
    ) -> Double {
        anchors.map { anchor in
            let fitted = coefficient * pow(anchor.meteredSeconds, exponent)
            return abs(log2(fitted / anchor.correctedSeconds))
        }.max() ?? 0
    }

    private func anchors(
        for stock: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [TableAnchor] {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == stock },
            "\(stock) must remain in the launch catalog.",
            file: file,
            line: line
        )
        let profile = try XCTUnwrap(film.profiles.first, file: file, line: line)
        let rule = try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(rule) = rule { return rule }
                return nil
            }.first,
            "\(stock) must carry its migrated table-interpolation rule.",
            file: file,
            line: line
        )
        return rule.anchors
    }
}
