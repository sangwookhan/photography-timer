import XCTest
@testable import PTimer

/// Behavior contract for Tri-X 400's table-interpolation reciprocity
/// profile. Locks the invariants:
///
/// - Below 1 sec (noCorrectionThroughSeconds = 0.999999) the threshold
///   rule wins — basis `.officialThresholdNoCorrection`, corrected == metered.
/// - At and above 1 sec the table-interpolation rule fires
///   (basis `.tableLogLogDerived`). At each anchor the corrected time
///   matches the published value exactly (1→2, 10→50, 100→1200).
/// - Above 100 sec (sourceRangeThroughSeconds) the evaluator returns
///   `.unsupportedOutOfPolicyRange`; a log-log extrapolation value is
///   still provided (non-nil, greater than the last anchor corrected time).
/// - All three published rows stay visible as source evidence carrying
///   the stop delta, the corrected time, AND the development adjustment
///   (-10% / -20% / -30%).
/// - The profile carries a `.tableInterpolation` rule; NO `.formula`
///   rule remains.
final class TriX400TableProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Rule structure

    func testTriX400HasTableInterpolationRuleAndNoFormulaRule() throws {
        let profile = try triX400Profile()

        let tableRule = profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
            if case let .tableInterpolation(r) = rule { return r } else { return nil }
        }.first
        XCTAssertNotNil(tableRule, "Tri-X 400 must carry a .tableInterpolation rule after migration.")

        let hasFormulaRule = profile.rules.contains { rule in
            if case .formula = rule { return true } else { return false }
        }
        XCTAssertFalse(hasFormulaRule, "Tri-X 400 must NOT carry a .formula rule after migration to table.")
    }

    func testTriX400TableRuleParametersMatchPublishedAnchors() throws {
        let profile = try triX400Profile()
        let tableRule = try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r } else { return nil }
            }.first,
            "tableInterpolation rule must be present."
        )

        XCTAssertEqual(tableRule.noCorrectionThroughSeconds, 0.999999, accuracy: 1e-6,
            "noCorrectionThroughSeconds must be 0.999999.")
        XCTAssertEqual(tableRule.sourceRangeThroughSeconds, 100, accuracy: 1e-6,
            "sourceRangeThroughSeconds must be 100.")

        let anchorMetereds = tableRule.anchors.map { $0.meteredSeconds }
        XCTAssertEqual(anchorMetereds, [1, 10, 100],
            "Table must have anchors at 1/10/100 sec.")

        let anchorCorrected = tableRule.anchors.map { $0.correctedSeconds }
        XCTAssertEqual(anchorCorrected[0], 2, accuracy: 1e-4,
            "Anchor at 1 sec must map to 2 sec corrected.")
        XCTAssertEqual(anchorCorrected[1], 50, accuracy: 1e-4,
            "Anchor at 10 sec must map to 50 sec corrected.")
        XCTAssertEqual(anchorCorrected[2], 1200, accuracy: 1e-4,
            "Anchor at 100 sec must map to 1200 sec corrected.")
    }

    func testTriX400ModelBasisIsManufacturerTableLogLogInterpolation() throws {
        let profile = try triX400Profile()
        let basis = try XCTUnwrap(profile.modelBasis,
            "Tri-X 400 profile must carry a modelBasis after migration.")
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation)
    }

    // MARK: - Threshold boundary (exclusive at 1 sec)

    func testTriX400Below1SecondReturnsOfficialNoCorrection() throws {
        let profile = try triX400Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.5)
        XCTAssertEqual(
            result.metadata.basis,
            .officialThresholdNoCorrection,
            "0.5 sec is below the noCorrectionThroughSeconds boundary and must not pick up a table correction."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 0.5, accuracy: 1e-6)
    }

    func testTriX400BoundaryAt1SecondAppliesTableNotNoCorrection() throws {
        // The 1 sec anchor is the start of Kodak's +1 stop range.
        // noCorrectionThroughSeconds = 0.999999, so 1 sec fires the
        // table rule, not the threshold.
        let profile = try triX400Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)

        XCTAssertEqual(
            result.metadata.basis,
            .tableLogLogDerived,
            "1 sec is the start of Kodak's +1 stop range and must NOT collapse onto the no-correction threshold."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 2, accuracy: 1e-4,
            "Table anchor at 1 sec must reproduce Kodak's published 2 sec corrected exposure exactly.")
    }

    // MARK: - Table range (1 sec … 100 sec, source-backed)

    func testTriX400InsideTableRangeIsTableLogLogDerivedAcrossPublishedRows() throws {
        let profile = try triX400Profile()
        for metered in [1.0, 5.0, 10.0, 25.0, 50.0, 100.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .tableLogLogDerived,
                "Metered \(metered) s sits inside the published 1–100 sec range and must be table-log-log-derived."
            )
        }
    }

    func testTriX400TableReproducesPublishedAnchorCorrectedTimesExactly() throws {
        let profile = try triX400Profile()
        let samples: [(Double, Double)] = [(1, 2), (10, 50), (100, 1200)]
        for (metered, published) in samples {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                published,
                accuracy: 1e-4,
                "Anchor at metered \(metered) s must reproduce the published corrected time of \(published) sec exactly."
            )
        }
    }

    // MARK: - Beyond the published source range (> 100 sec)

    func testTriX400Above100SecondsBecomesBeyondSourceNumericGuidance() throws {
        let profile = try triX400Profile()
        for metered in [150.0, 300.0, 1000.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "Metered \(metered) s sits above Kodak's 100 sec upper published row and must be marked outside manufacturer guidance."
            )
            let corrected = try XCTUnwrap(
                result.correctedExposureSeconds,
                "Metered \(metered) s must keep a log-log extrapolation value past the source range."
            )
            XCTAssertGreaterThan(corrected, 1200,
                "Extrapolated value past 100 sec must exceed the last anchor corrected time of 1200 sec.")
        }
    }

    // MARK: - Source evidence preservation (corrected time + stop delta + development)

    func testTriX400SourceEvidencePreservesPublishedRowsWithDevelopmentAdjustments() throws {
        let profile = try triX400Profile()

        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        XCTAssertEqual(
            exactRows.map { $0.0 },
            [1, 10, 100],
            "Tri-X 400 must keep Kodak's three published rows (1/10/100 sec) as source evidence."
        )

        let expectedDevelopment: [Double: String] = [
            1: "-10% development",
            10: "-20% development",
            100: "-30% development",
        ]
        let expectedStops: [Double: Double] = [1: 1, 10: 2, 100: 3]
        let expectedCorrected: [Double: Double] = [1: 2, 10: 50, 100: 1200]

        for (metered, row) in exactRows {
            // Stop delta — Kodak publishes a numeric +N stops anchor
            // alongside the corrected time on every row.
            let stopDelta = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
                return value.stopDelta
            }.first
            XCTAssertEqual(stopDelta ?? -1, expectedStops[metered] ?? -1, accuracy: 1e-6, "Stop delta mismatch at \(metered) s")

            // Corrected time — used as the table fitting basis.
            let correctedSeconds = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                return mapping.correctedSeconds
            }.first
            XCTAssertEqual(correctedSeconds ?? -1, expectedCorrected[metered] ?? -1, accuracy: 1e-6, "Corrected time mismatch at \(metered) s")

            // Development adjustment — Tri-X publishes -10/-20/-30%.
            let devInstruction = row.adjustments.compactMap { adjustment -> String? in
                guard case let .development(dev) = adjustment else { return nil }
                return dev.instruction
            }.first
            XCTAssertEqual(
                devInstruction,
                expectedDevelopment[metered],
                "Development instruction at \(metered) s must remain visible as published — Tri-X conversion must not silently drop it."
            )
        }
    }

    // MARK: - UI surfacing

    @MainActor
    func testTriX400DetailsSurfaceShowsSourceReferenceRowsWithDevelopmentText() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Tri-X 400 must surface a Source reference section for its table-origin profile."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        for stop in ["-10%", "-20%", "-30%"] {
            XCTAssertTrue(
                sourceBlock.contains(stop),
                "Source reference block must surface Kodak's development adjustment \(stop). Got block:\n\(sourceBlock)"
            )
        }
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Tri-X 400 must not surface the legacy Reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "Tri-X 400 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testTriX400DevelopmentLegendStillSurfacesAfterMigration() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(
            legend.lines.contains { $0 == "Development adjustment: Dev -10% means adjust development time by -10%." },
            "Tri-X 400 migration must keep the development-adjustment legend line. Got: \(legend.lines)"
        )
    }

    @MainActor
    func testTriX400SummaryTextIsLogLogInterpolationInsideRange() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Log-log interpolation of the official table",
            "Summary inside the source range must describe table log-log interpolation."
        )
    }

    @MainActor
    func testTriX400SummaryTextIsBeyondSourceRangeAbove100Seconds() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 300)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Beyond source range",
            "Summary above 100 sec must read 'Beyond source range'."
        )
    }

    @MainActor
    func testTriX400GraphCarriesSourceReferenceMarkersAtPublishedCorrectedTimes() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula,
            "Table models render as .formula graph kind (matching Fomapan 100 Classic behavior).")

        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
        XCTAssertEqual(
            Set(markerMetereds),
            Set([1, 10, 100]),
            "Tri-X 400 graph must mark Kodak's three published source rows."
        )

        let markerByMetered = Dictionary(
            uniqueKeysWithValues: graph.sourceReferenceMarkers.map { ($0.point.meteredExposureSeconds.rounded(), $0.point.correctedExposureSeconds) }
        )
        XCTAssertEqual(markerByMetered[1] ?? 0, 2, accuracy: 1e-3, "Marker at 1 sec must plot the published 2 sec corrected exposure.")
        XCTAssertEqual(markerByMetered[10] ?? 0, 50, accuracy: 1e-3, "Marker at 10 sec must plot the published 50 sec corrected exposure.")
        XCTAssertEqual(markerByMetered[100] ?? 0, 1200, accuracy: 1e-2, "Marker at 100 sec must plot the published 1200 sec corrected exposure.")

        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "Tri-X 400 has no published not-recommended boundary."
        )

        let beyondStart = try XCTUnwrap(
            graph.beyondSourceRangeStartSeconds,
            "The graph must shade the region above 100 sec so the user sees where source-backed guidance ends."
        )
        XCTAssertEqual(beyondStart, 100.000001, accuracy: 1e-3)
    }

    /// Past 100 sec the graph note must surface "source range"
    /// wording so the value never reads as manufacturer-supported.
    @MainActor
    func testTriX400Above100SecondsGraphExplanationSurfacesSourceRangeWording() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 300)
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
            film: "Tri-X 400",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func triX400Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "Tri-X 400")
    }
}
