import XCTest
@testable import PTimer

/// Behavior contract for FOMA BOHEMIA's three Fomapan reciprocity
/// profiles after their conversion from multiplier-table profiles
/// to formula-based prediction. Locks the invariants:
///
/// - The threshold rule (no correction up to 1/2 sec) is unchanged.
/// - The formula rule replaces the published multiplier table. Above
///   the 1/2 sec threshold and up to and including the 100 sec
///   published row, the basis is `.formulaDerived`. Above 100 sec
///   the formula continues as numeric continuation outside the
///   published source range (`.unsupportedOutOfPolicyRange` with a
///   non-nil corrected exposure).
/// - The three published multiplier rows (1/10/100 sec) are
///   preserved verbatim as `sourceEvidence` — both the multiplier
///   factor and the published corrected time stay visible so the
///   photographer can verify the formula against FOMA's anchors.
/// - The fits are free log-log fits through the three published
///   rows; FOMA's data sheets are not perfectly log-linear, so the
///   residuals are documented in the formula note rather than
///   forced to zero.
final class FomaFormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    private struct FomaPublishedRow {
        let metered: Double
        let multiplier: Double
        let corrected: Double
    }

    private struct FomaFit {
        let canonicalStockName: String
        let coefficient: Double
        let exponent: Double
        let publishedRows: [FomaPublishedRow]
        let stopTolerancePerRow: Double
    }

    private let foma100 = FomaFit(
        canonicalStockName: "Fomapan 100 Classic",
        coefficient: 2.2457,
        exponent: 1.4515,
        publishedRows: [
            FomaPublishedRow(metered: 1, multiplier: 2, corrected: 2),
            FomaPublishedRow(metered: 10, multiplier: 8, corrected: 80),
            FomaPublishedRow(metered: 100, multiplier: 16, corrected: 1600),
        ],
        stopTolerancePerRow: 0.35
    )

    private let foma200 = FomaFit(
        canonicalStockName: "Fomapan 200 Creative",
        coefficient: 3.2107,
        exponent: 1.3891,
        publishedRows: [
            FomaPublishedRow(metered: 1, multiplier: 3, corrected: 3),
            FomaPublishedRow(metered: 10, multiplier: 9, corrected: 90),
            FomaPublishedRow(metered: 100, multiplier: 18, corrected: 1800),
        ],
        stopTolerancePerRow: 0.25
    )

    private let foma400 = FomaFit(
        canonicalStockName: "Fomapan 400 Action",
        coefficient: 1.8022,
        exponent: 1.3635,
        publishedRows: [
            FomaPublishedRow(metered: 1, multiplier: 1.5, corrected: 1.5),
            FomaPublishedRow(metered: 10, multiplier: 6, corrected: 60),
            FomaPublishedRow(metered: 100, multiplier: 8, corrected: 800),
        ],
        stopTolerancePerRow: 0.6
    )

    private var allFits: [FomaFit] { [foma100, foma200, foma400] }

    // MARK: - Threshold boundary (inclusive at 1/2 sec)

    func testFomapanProfilesAtThresholdBoundaryReturnOfficialNoCorrection() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.5)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "\(fit.canonicalStockName)'s 1/2 sec threshold is inclusive — 0.5 s itself must read as no-correction."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, 0.5, accuracy: 1e-6)
        }
    }

    // MARK: - Formula range (> 1/2 sec, up to and including 100 sec)

    func testFomapanProfilesInsideFormulaRangeAreFormulaDerivedAtAllPublishedRows() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            for row in fit.publishedRows {
                let result = evaluator.evaluate(
                    profile: profile,
                    meteredExposureSeconds: row.metered
                )
                XCTAssertEqual(
                    result.metadata.basis,
                    .formulaDerived,
                    "\(fit.canonicalStockName) at \(row.metered) s must be formula-derived, never resurrected as an exact-table point — the published row lives as source evidence only."
                )
            }
        }
    }

    func testFomapanProfilesFormulaTracksPublishedCorrectedTimesWithinDocumentedTolerance() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            for row in fit.publishedRows {
                let result = evaluator.evaluate(
                    profile: profile,
                    meteredExposureSeconds: row.metered
                )
                let corrected = try XCTUnwrap(result.correctedExposureSeconds)
                let stopError = log2(corrected / row.corrected)
                XCTAssertEqual(
                    stopError,
                    0,
                    accuracy: fit.stopTolerancePerRow,
                    "\(fit.canonicalStockName) at \(row.metered) s formula prediction (\(corrected) s) must stay within \(fit.stopTolerancePerRow) stop of FOMA's published row (\(row.corrected) s); got error \(stopError) stop."
                )
            }
        }
    }

    func testFomapanProfilesFormulaUsesFreeLogLogCoefficient() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                guard case let .formula(rule) = rule else { return nil }
                return rule
            }.first)

            XCTAssertEqual(formulaRule.formula.exponent, fit.exponent, accuracy: 1e-3, "\(fit.canonicalStockName) exponent mismatch")
            let coefficient = formulaRule.formula.coefficientSeconds
            XCTAssertEqual(coefficient, fit.coefficient, accuracy: 1e-3, "\(fit.canonicalStockName) coefficient mismatch")

            let note = try XCTUnwrap(formulaRule.notes.first)
            XCTAssertTrue(
                note.lowercased().contains("log-log"),
                "\(fit.canonicalStockName) formula note must label the fit as log-log; got: \(note)"
            )
            XCTAssertTrue(
                note.lowercased().contains("numeric continuation"),
                "\(fit.canonicalStockName) formula note must describe values above 100 sec as numeric continuation; got: \(note)"
            )
        }
    }

    // MARK: - Beyond the published source range (> 100 sec)

    func testFomapanProfilesAbove100SecondsBecomesBeyondSourceNumericGuidance() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            for metered in [150.0, 300.0, 1000.0] {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .unsupportedOutOfPolicyRange,
                    "\(fit.canonicalStockName) at \(metered) s sits above FOMA's 100 sec upper published row and must be marked outside manufacturer guidance."
                )
                let corrected = try XCTUnwrap(
                    result.correctedExposureSeconds,
                    "\(fit.canonicalStockName) at \(metered) s must keep a numeric continuation past the source range."
                )
                let expected = fit.coefficient * pow(metered, fit.exponent)
                XCTAssertEqual(corrected, expected, accuracy: expected * 0.01)
            }
        }
    }

    // MARK: - Source-evidence preservation (multiplier + corrected time)

    func testFomapanProfilesSourceEvidencePreservesMultiplierAndCorrectedTime() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
                guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
                return (seconds, row)
            }
            XCTAssertEqual(
                exactRows.map { $0.0 },
                fit.publishedRows.map { $0.metered },
                "\(fit.canonicalStockName) must keep all three FOMA-published multiplier rows as source evidence."
            )

            let expectedMultipliers = Dictionary(uniqueKeysWithValues: fit.publishedRows.map { ($0.metered, $0.multiplier) })
            let expectedCorrected = Dictionary(uniqueKeysWithValues: fit.publishedRows.map { ($0.metered, $0.corrected) })

            for (metered, row) in exactRows {
                let multiplier = row.adjustments.compactMap { adjustment -> Double? in
                    guard case let .exposure(.multiplier(value)) = adjustment else { return nil }
                    return value.factor
                }.first
                XCTAssertEqual(
                    multiplier ?? -1,
                    expectedMultipliers[metered] ?? -1,
                    accuracy: 1e-6,
                    "\(fit.canonicalStockName) source evidence at \(metered) s must keep the published multiplier factor."
                )

                let correctedSeconds = row.adjustments.compactMap { adjustment -> Double? in
                    guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                    return mapping.correctedSeconds
                }.first
                XCTAssertEqual(
                    correctedSeconds ?? -1,
                    expectedCorrected[metered] ?? -1,
                    accuracy: 1e-6,
                    "\(fit.canonicalStockName) source evidence at \(metered) s must keep the published corrected time (metered × multiplier) verbatim."
                )
            }
        }
    }

    func testFomapanProfilesKeepOfficialManufacturerPublishedSource() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            XCTAssertEqual(profile.source.kind, .manufacturerPublished)
            XCTAssertEqual(profile.source.authority, .official)
            XCTAssertEqual(profile.source.publisher, "FOMA BOHEMIA")
        }
    }

    // MARK: - UI surfacing (presenter / graph)

    @MainActor
    func testFomapanProfilesDetailsSurfaceShowsSourceReferenceWithMultiplierColumn() throws {
        for fit in allFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: 10
            )

            let sourceReferenceSection = try XCTUnwrap(
                displayState.sections.first(where: { $0.title == "Source reference" }),
                "\(fit.canonicalStockName) must surface a Source reference section after conversion."
            )
            let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)

            for row in fit.publishedRows {
                let multiplierToken = "\(formatMultiplier(row.multiplier))x"
                XCTAssertTrue(
                    sourceBlock.contains(multiplierToken),
                    "\(fit.canonicalStockName) source block must surface the published multiplier '\(multiplierToken)'. Got:\n\(sourceBlock)"
                )
            }
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Reference" }),
                "Converted \(fit.canonicalStockName) must not surface the legacy Reference section."
            )
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
                "FOMA profiles publish no not-recommended row; Guidance boundary section must be absent."
            )
        }
    }

    @MainActor
    func testFomapanProfilesGraphCarriesSourceReferenceMarkersAtPublishedRows() throws {
        for fit in allFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: 10
            )
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(graph.kind, .formula, "\(fit.canonicalStockName) must render the formula graph kind after conversion.")

            let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
            XCTAssertEqual(
                Set(markerMetereds),
                Set(fit.publishedRows.map { $0.metered }),
                "\(fit.canonicalStockName) graph must mark FOMA's three published source rows."
            )

            XCTAssertNil(
                graph.notRecommendedBoundarySeconds,
                "\(fit.canonicalStockName) has no published not-recommended boundary."
            )

            let beyondStart = try XCTUnwrap(
                graph.beyondSourceRangeStartSeconds,
                "\(fit.canonicalStockName) graph must shade the region above 100 sec so the user sees where source-backed guidance ends."
            )
            XCTAssertEqual(beyondStart, 100.000001, accuracy: 1e-3)
        }
    }

    /// Past 100 sec the graph note for every Fomapan film must
    /// surface "source range" wording so the value never reads as
    /// manufacturer-supported.
    @MainActor
    func testFomapanProfilesAbove100SecondsGraphExplanationSurfacesSourceRangeWording() throws {
        for fit in allFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: 300
            )
            let graph = try XCTUnwrap(displayState.graph)
            let explanation = try XCTUnwrap(graph.unsupportedExplanation)
            XCTAssertTrue(
                explanation.lowercased().contains("source range"),
                "\(fit.canonicalStockName) graph explanation must surface source-range wording past 100 sec; got: \(explanation)"
            )
        }
    }

    // MARK: - Helpers

    private func profile(for fit: FomaFit) throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: fit.canonicalStockName)
    }

    @MainActor
    private func makeDisplayState(
        film canonicalStockName: String,
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: canonicalStockName,
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func formatMultiplier(_ factor: Double) -> String {
        // The presenter renders integer multipliers without a decimal
        // (e.g. "2x") and fractional ones with a single decimal
        // (e.g. "1.5x"). Match that exactly so the assertion catches
        // formatting drifts.
        if factor.rounded() == factor {
            return String(format: "%g", factor)
        }
        return String(factor)
    }
}
