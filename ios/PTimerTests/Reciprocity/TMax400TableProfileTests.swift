import XCTest
@testable import PTimer

/// Behavior contract for T-MAX 400's table-interpolation reciprocity
/// profile. Locks the invariants:
///
/// - The 1/10,000 sec to 1 sec no-correction band is preserved —
///   Kodak's "no adjustment required" range carries through unchanged
///   (basis `.officialThresholdNoCorrection`).
/// - Above 1 sec (noCorrectionThroughSeconds) the table-interpolation
///   rule fires (basis `.tableLogLogDerived`). At each anchor the
///   corrected time matches exactly: 10→15, 100→300.
/// - Above 100 sec (sourceRangeThroughSeconds) the evaluator returns
///   `.unsupportedOutOfPolicyRange`; a log-log extrapolation value is
///   still provided (non-nil, greater than the last anchor corrected time).
/// - Both published source rows stay visible as source evidence carrying
///   the stop delta AND the published corrected time.
/// - The profile carries a `.tableInterpolation` rule; NO `.formula`
///   rule remains.
final class TMax400TableProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Rule structure

    func testTMax400HasTableInterpolationRuleAndNoFormulaRule() throws {
        let profile = try tmax400Profile()

        let tableRule = profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
            if case let .tableInterpolation(r) = rule { return r } else { return nil }
        }.first
        XCTAssertNotNil(tableRule, "T-MAX 400 must carry a .tableInterpolation rule after migration.")

        let hasFormulaRule = profile.rules.contains { rule in
            if case .formula = rule { return true } else { return false }
        }
        XCTAssertFalse(hasFormulaRule, "T-MAX 400 must NOT carry a .formula rule after migration to table.")
    }

    func testTMax400TableRuleParametersMatchPublishedAnchors() throws {
        let profile = try tmax400Profile()
        let tableRule = try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r } else { return nil }
            }.first,
            "tableInterpolation rule must be present."
        )

        XCTAssertEqual(tableRule.noCorrectionThroughSeconds, 1, accuracy: 1e-6,
            "noCorrectionThroughSeconds must be 1.")
        XCTAssertEqual(tableRule.sourceRangeThroughSeconds, 100, accuracy: 1e-6,
            "sourceRangeThroughSeconds must be 100.")

        let anchorMetereds = tableRule.anchors.map { $0.meteredSeconds }
        XCTAssertEqual(anchorMetereds, [10, 100],
            "Table must have anchors at 10/100 sec.")

        let anchorCorrected = tableRule.anchors.map { $0.correctedSeconds }
        XCTAssertEqual(anchorCorrected[0], 15, accuracy: 1e-4,
            "Anchor at 10 sec must map to 15 sec corrected.")
        XCTAssertEqual(anchorCorrected[1], 300, accuracy: 1e-4,
            "Anchor at 100 sec must map to 300 sec corrected.")
    }

    func testTMax400ModelBasisIsManufacturerTableLogLogInterpolation() throws {
        let profile = try tmax400Profile()
        let basis = try XCTUnwrap(profile.modelBasis,
            "T-MAX 400 profile must carry a modelBasis after migration.")
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation)
    }

    // MARK: - Threshold band edges (1/10000 sec … 1 sec, inclusive)

    func testTMax400AtThresholdBandBoundariesReturnsOfficialNoCorrection() throws {
        let profile = try tmax400Profile()
        // Lower edge (1/10000 sec) and upper edge (1 sec inclusive —
        // the table picks up strictly above 1 sec).
        for metered in [0.0001, 1.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "T-MAX 400 at \(metered) sec must read as no-correction at the band edge."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, metered, accuracy: 1e-6)
        }
    }

    // MARK: - Table range (> 1 sec, up to 100 sec)

    func testTMax400InsideTableRangeIsTableLogLogDerived() throws {
        let profile = try tmax400Profile()
        for metered in [2.0, 5.0, 10.0, 30.0, 100.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .tableLogLogDerived,
                "Metered \(metered) sec sits inside the source-backed table range."
            )
        }
    }

    func testTMax400TableReproducesPublishedAnchorCorrectedTimesExactly() throws {
        let profile = try tmax400Profile()
        let samples: [(Double, Double)] = [(10, 15), (100, 300)]
        for (metered, published) in samples {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                published,
                accuracy: 1e-4,
                "Anchor at metered \(metered) sec must reproduce the published corrected time of \(published) sec exactly."
            )
        }
    }

    // MARK: - Beyond the published source range (> 100 sec)

    func testTMax400Above100SecondsBecomesBeyondSourceNumericGuidance() throws {
        let profile = try tmax400Profile()
        for metered in [150.0, 400.0, 2000.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "Metered \(metered) sec sits above Kodak's published 100 sec upper anchor."
            )
            let corrected = try XCTUnwrap(
                result.correctedExposureSeconds,
                "Metered \(metered) sec must keep a log-log extrapolation value past the source range."
            )
            XCTAssertGreaterThan(corrected, 300,
                "Extrapolated value past 100 sec must exceed the last anchor corrected time of 300 sec.")
        }
    }

    // MARK: - Source evidence preservation

    func testTMax400SourceEvidencePreservesBothPublishedRowsWithCorrectedTimes() throws {
        let profile = try tmax400Profile()
        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        XCTAssertEqual(
            exactRows.map { $0.0 },
            [10, 100],
            "T-MAX 400 must keep both Kodak-published rows (10/100 sec) as source evidence."
        )

        let expectedStops: [Double: Double] = [10: 0.5, 100: 1.5]
        let expectedCorrected: [Double: Double] = [10: 15, 100: 300]
        for (metered, row) in exactRows {
            let stopDelta = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
                return value.stopDelta
            }.first
            XCTAssertEqual(stopDelta ?? -1, expectedStops[metered] ?? -1, accuracy: 1e-6, "Stop delta mismatch at \(metered) s")

            let correctedSeconds = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                return mapping.correctedSeconds
            }.first
            XCTAssertEqual(correctedSeconds ?? -1, expectedCorrected[metered] ?? -1, accuracy: 1e-6, "Corrected time mismatch at \(metered) s")
        }
    }

    // MARK: - UI surfacing

    @MainActor
    func testTMax400DetailsSurfaceShowsSourceReferenceRows() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "T-MAX 400 must surface a Source reference section for its table-origin profile."
        )
        let block = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(block.contains("10.0s"))
        XCTAssertTrue(block.contains("100.0s"))
        XCTAssertTrue(block.contains("15"))
        XCTAssertTrue(block.contains("300"))
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "T-MAX 400 must not surface the legacy Reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "T-MAX 400 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testTMax400SummaryTextIsLogLogInterpolationInsideRange() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Log-log interpolation of the official table",
            "Summary inside the source range must describe table log-log interpolation."
        )
    }

    @MainActor
    func testTMax400SummaryTextIsBeyondSourceRangeAbove100Seconds() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 400)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Beyond source range",
            "Summary above 100 sec must read 'Beyond source range'."
        )
    }

    @MainActor
    func testTMax400GraphCarriesSourceReferenceMarkersAtPublishedCorrectedTimes() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula,
            "Table models render as .formula graph kind (matching Fomapan 100 Classic behavior).")

        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
        XCTAssertEqual(
            Set(markerMetereds),
            Set([10, 100]),
            "T-MAX 400 graph must mark both published source rows."
        )

        let markerByMetered = Dictionary(
            uniqueKeysWithValues: graph.sourceReferenceMarkers.map { ($0.point.meteredExposureSeconds.rounded(), $0.point.correctedExposureSeconds) }
        )
        XCTAssertEqual(markerByMetered[10] ?? 0, 15, accuracy: 0.01)
        XCTAssertEqual(markerByMetered[100] ?? 0, 300, accuracy: 0.01)

        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "T-MAX 400 has no published not-recommended boundary."
        )

        let beyondStart = try XCTUnwrap(
            graph.beyondSourceRangeStartSeconds,
            "The graph must shade the region above 100 sec so the user sees where source-backed guidance ends."
        )
        XCTAssertEqual(beyondStart, 100.000001, accuracy: 1e-3)
    }

    /// Past 100 sec the graph note must surface "source range"
    /// wording so the user reads the value as outside Kodak's
    /// supported range.
    @MainActor
    func testTMax400Above100SecondsGraphExplanationSurfacesSourceRangeWording() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 400)
        let graph = try XCTUnwrap(displayState.graph)
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertTrue(
            explanation.lowercased().contains("source table"),
            "Graph explanation must surface source-table wording past 100 sec; got: \(explanation)"
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: "T-MAX 400",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func tmax400Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "T-MAX 400")
    }
}
