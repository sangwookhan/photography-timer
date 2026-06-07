import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// PTIMER-168: Behavior contract for Fomapan 200 Creative and
/// Fomapan 400 Action after their migration from a formula-based
/// reciprocity rule to the official FOMA table model
/// (`.tableLogLogInterpolation`). Locks the invariants:
///
/// - The threshold rule (no correction up to 1/2 sec) is unchanged.
/// - Inside the table range (> 1/2 sec up to and including 100 sec)
///   the basis is `.tableLogLogDerived`; the evaluator reproduces the
///   three published anchor times exactly.
/// - Above 100 sec the basis is `.unsupportedOutOfPolicyRange`; a
///   non-nil log-log extrapolated value is still returned.
/// - The three published multiplier rows (1/10/100 sec) are preserved
///   verbatim as `sourceEvidence` — both the multiplier factor and
///   the published corrected time remain visible for verification.
/// - No `.formula` rule exists on either profile.
final class FomaTableProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    private struct FomaPublishedRow {
        let metered: Double
        let multiplier: Double
        let corrected: Double
    }

    private struct FomaTableSpec {
        let canonicalStockName: String
        let noCorrectionThroughSeconds: Double
        let sourceRangeThroughSeconds: Double
        let anchors: [FomaPublishedRow]
    }

    private let foma200 = FomaTableSpec(
        canonicalStockName: "Fomapan 200 Creative",
        noCorrectionThroughSeconds: 0.5,
        sourceRangeThroughSeconds: 100,
        anchors: [
            FomaPublishedRow(metered: 1, multiplier: 3, corrected: 3),
            FomaPublishedRow(metered: 10, multiplier: 9, corrected: 90),
            FomaPublishedRow(metered: 100, multiplier: 18, corrected: 1800),
        ]
    )

    private let foma400 = FomaTableSpec(
        canonicalStockName: "Fomapan 400 Action",
        noCorrectionThroughSeconds: 0.5,
        sourceRangeThroughSeconds: 100,
        anchors: [
            FomaPublishedRow(metered: 1, multiplier: 1.5, corrected: 1.5),
            FomaPublishedRow(metered: 10, multiplier: 6, corrected: 60),
            FomaPublishedRow(metered: 100, multiplier: 8, corrected: 800),
        ]
    )

    private var allSpecs: [FomaTableSpec] { [foma200, foma400] }

    // MARK: - Profile structure

    func testFomapanProfilesCarryTableInterpolationRuleWithCorrectAnchors() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)

            let tableRule = try XCTUnwrap(
                profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                    if case let .tableInterpolation(r) = rule { return r } else { return nil }
                }.first,
                "\(spec.canonicalStockName) must carry a .tableInterpolation rule after migration."
            )

            XCTAssertEqual(
                tableRule.noCorrectionThroughSeconds,
                spec.noCorrectionThroughSeconds,
                accuracy: 1e-6,
                "\(spec.canonicalStockName) noCorrectionThroughSeconds mismatch."
            )
            XCTAssertEqual(
                tableRule.sourceRangeThroughSeconds,
                spec.sourceRangeThroughSeconds,
                accuracy: 1e-6,
                "\(spec.canonicalStockName) sourceRangeThroughSeconds mismatch."
            )
            XCTAssertEqual(
                tableRule.anchors.count,
                spec.anchors.count,
                "\(spec.canonicalStockName) anchor count mismatch."
            )
            for (anchor, expected) in zip(tableRule.anchors, spec.anchors) {
                XCTAssertEqual(anchor.meteredSeconds, expected.metered, accuracy: 1e-6)
                XCTAssertEqual(anchor.correctedSeconds, expected.corrected, accuracy: 1e-6)
            }
        }
    }

    func testFomapanProfilesCarryNoFormulaRule() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            let formulaRules = profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                guard case let .formula(r) = rule else { return nil }
                return r
            }
            XCTAssertTrue(
                formulaRules.isEmpty,
                "\(spec.canonicalStockName) must not carry any .formula rule after migration to the official table model."
            )
        }
    }

    func testFomapanProfilesModelBasisIsManufacturerTableLogLog() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            let basis = try XCTUnwrap(
                profile.modelBasis,
                "\(spec.canonicalStockName) must declare a modelBasis after migration."
            )
            XCTAssertEqual(
                basis.sourceModel,
                .manufacturerTable,
                "\(spec.canonicalStockName) sourceModel must be .manufacturerTable."
            )
            XCTAssertEqual(
                basis.calculationModel,
                .tableLogLogInterpolation,
                "\(spec.canonicalStockName) calculationModel must be .tableLogLogInterpolation."
            )
        }
    }

    func testFomapanProfilesHaveOfficialTableId() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            XCTAssertTrue(
                profile.id.hasSuffix("-official-table"),
                "\(spec.canonicalStockName) profile id must end with '-official-table'; got: \(profile.id)"
            )
            XCTAssertEqual(
                profile.name,
                "Official FOMA table",
                "\(spec.canonicalStockName) profile name mismatch."
            )
        }
    }

    // MARK: - Threshold boundary (inclusive at 1/2 sec)

    func testFomapanProfilesAtThresholdBoundaryReturnOfficialNoCorrection() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.5)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "\(spec.canonicalStockName)'s 1/2 sec threshold is inclusive — 0.5 s itself must read as no-correction."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, 0.5, accuracy: 1e-6)
        }
    }

    // MARK: - Table range (> 1/2 sec, up to and including 100 sec)

    func testFomapanProfilesInsideTableRangeAreTableLogLogDerivedAtAllPublishedAnchors() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            for anchor in spec.anchors {
                let result = evaluator.evaluate(
                    profile: profile,
                    meteredExposureSeconds: anchor.metered
                )
                XCTAssertEqual(
                    result.metadata.basis,
                    .tableLogLogDerived,
                    "\(spec.canonicalStockName) at \(anchor.metered) s must be .tableLogLogDerived inside the published table range."
                )
            }
        }
    }

    func testFomapanProfilesTableReproducesPublishedAnchorCorrectedTimesExactly() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            for anchor in spec.anchors {
                let result = evaluator.evaluate(
                    profile: profile,
                    meteredExposureSeconds: anchor.metered
                )
                let corrected = try XCTUnwrap(result.correctedExposureSeconds)
                XCTAssertEqual(
                    corrected,
                    anchor.corrected,
                    accuracy: 1e-4,
                    "\(spec.canonicalStockName) at \(anchor.metered) s: table must reproduce the published anchor time exactly."
                )
            }
        }
    }

    // MARK: - Beyond the published source range (> 100 sec)

    func testFomapanProfilesAbove100SecondsBecomesBeyondSourceRange() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            for metered in [150.0, 300.0, 1000.0] {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .unsupportedOutOfPolicyRange,
                    "\(spec.canonicalStockName) at \(metered) s sits above FOMA's 100 sec upper anchor and must be marked outside manufacturer guidance."
                )
                let corrected = try XCTUnwrap(
                    result.correctedExposureSeconds,
                    "\(spec.canonicalStockName) at \(metered) s must still return a log-log extrapolated value past the source range."
                )
                let lastAnchorCorrected = try XCTUnwrap(spec.anchors.last?.corrected)
                XCTAssertGreaterThan(
                    corrected,
                    lastAnchorCorrected,
                    "\(spec.canonicalStockName): extrapolated value at \(metered) s must exceed the last anchor's corrected time."
                )
            }
        }
    }

    // MARK: - Source-evidence preservation (multiplier + corrected time)

    func testFomapanProfilesSourceEvidencePreservesMultiplierAndCorrectedTime() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
                guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
                return (seconds, row)
            }
            XCTAssertEqual(
                exactRows.map { $0.0 },
                spec.anchors.map { $0.metered },
                "\(spec.canonicalStockName) must keep all three FOMA-published multiplier rows as source evidence."
            )

            let expectedMultipliers = Dictionary(uniqueKeysWithValues: spec.anchors.map { ($0.metered, $0.multiplier) })
            let expectedCorrected = Dictionary(uniqueKeysWithValues: spec.anchors.map { ($0.metered, $0.corrected) })

            for (metered, row) in exactRows {
                let multiplier = row.adjustments.compactMap { adjustment -> Double? in
                    guard case let .exposure(.multiplier(value)) = adjustment else { return nil }
                    return value.factor
                }.first
                XCTAssertEqual(
                    multiplier ?? -1,
                    expectedMultipliers[metered] ?? -1,
                    accuracy: 1e-6,
                    "\(spec.canonicalStockName) source evidence at \(metered) s must keep the published multiplier factor."
                )

                let correctedSeconds = row.adjustments.compactMap { adjustment -> Double? in
                    guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                    return mapping.correctedSeconds
                }.first
                XCTAssertEqual(
                    correctedSeconds ?? -1,
                    expectedCorrected[metered] ?? -1,
                    accuracy: 1e-6,
                    "\(spec.canonicalStockName) source evidence at \(metered) s must keep the published corrected time (metered × multiplier) verbatim."
                )
            }
        }
    }

    func testFomapanProfilesKeepOfficialManufacturerPublishedSource() throws {
        for spec in allSpecs {
            let profile = try profile(for: spec)
            XCTAssertEqual(profile.source.kind, .manufacturerPublished)
            XCTAssertEqual(profile.source.authority, .official)
            XCTAssertEqual(profile.source.publisher, "FOMA BOHEMIA")
        }
    }

    // MARK: - UI surfacing (presenter / graph)

    @MainActor
    func testFomapanProfilesDetailsSurfaceShowsSourceReferenceWithMultiplierColumn() throws {
        for spec in allSpecs {
            let displayState = try makeDisplayState(
                film: spec.canonicalStockName,
                meteredExposureSeconds: 10
            )

            let sourceReferenceSection = try XCTUnwrap(
                displayState.sections.first(where: { $0.title == "Source reference" }),
                "\(spec.canonicalStockName) must surface a Source reference section."
            )
            let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)

            for anchor in spec.anchors {
                let multiplierToken = "\(formatMultiplier(anchor.multiplier))x"
                XCTAssertTrue(
                    sourceBlock.contains(multiplierToken),
                    "\(spec.canonicalStockName) source block must surface the published multiplier '\(multiplierToken)'. Got:\n\(sourceBlock)"
                )
            }
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Reference" }),
                "\(spec.canonicalStockName) must not surface the legacy Reference section."
            )
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
                "FOMA profiles publish no not-recommended row; Guidance boundary section must be absent."
            )
        }
    }

    @MainActor
    func testFomapanProfilesSummaryTextInsideRangeIsLogLogInterpolation() throws {
        for spec in allSpecs {
            let displayState = try makeDisplayState(
                film: spec.canonicalStockName,
                meteredExposureSeconds: 10
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Log-log interpolation of the official table",
                "\(spec.canonicalStockName) summary inside the table range must read 'Log-log interpolation of the official table'."
            )
        }
    }

    @MainActor
    func testFomapanProfilesSummaryTextAboveSourceRangeIsBeyondSourceRange() throws {
        for spec in allSpecs {
            let displayState = try makeDisplayState(
                film: spec.canonicalStockName,
                meteredExposureSeconds: 300
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Beyond source range",
                "\(spec.canonicalStockName) summary above 100 sec must read 'Beyond source range'."
            )
        }
    }

    @MainActor
    func testFomapanProfilesGraphCarriesSourceReferenceMarkersAtPublishedAnchors() throws {
        for spec in allSpecs {
            let displayState = try makeDisplayState(
                film: spec.canonicalStockName,
                meteredExposureSeconds: 10
            )
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.kind,
                .formula,
                "\(spec.canonicalStockName) table profiles render as the .formula graph kind (same as Fomapan 100 Classic)."
            )

            let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
            XCTAssertEqual(
                Set(markerMetereds),
                Set(spec.anchors.map { $0.metered }),
                "\(spec.canonicalStockName) graph must mark FOMA's three published anchor rows."
            )

            XCTAssertNil(
                graph.notRecommendedBoundarySeconds,
                "\(spec.canonicalStockName) has no published not-recommended boundary."
            )

            let beyondStart = try XCTUnwrap(
                graph.beyondSourceRangeStartSeconds,
                "\(spec.canonicalStockName) graph must shade the region above 100 sec so the user sees where table-backed guidance ends."
            )
            XCTAssertEqual(beyondStart, 100.000001, accuracy: 1e-3)
        }
    }

    /// Past 100 sec the graph note for every Fomapan film must
    /// surface "source range" wording so the value never reads as
    /// manufacturer-supported.
    @MainActor
    func testFomapanProfilesAbove100SecondsGraphExplanationSurfacesSourceRangeWording() throws {
        for spec in allSpecs {
            let displayState = try makeDisplayState(
                film: spec.canonicalStockName,
                meteredExposureSeconds: 300
            )
            let graph = try XCTUnwrap(displayState.graph)
            let explanation = try XCTUnwrap(graph.unsupportedExplanation)
            XCTAssertTrue(
                explanation.lowercased().contains("source table"),
                "\(spec.canonicalStockName) graph explanation must surface source-table wording past 100 sec; got: \(explanation)"
            )
        }
    }

    // MARK: - Helpers

    private func profile(for spec: FomaTableSpec) throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: spec.canonicalStockName)
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
        // (e.g. "3x") and fractional ones with a single decimal
        // (e.g. "1.5x"). Match that exactly so the assertion catches
        // formatting drifts.
        if factor.rounded() == factor {
            return String(format: "%g", factor)
        }
        return String(factor)
    }
}
