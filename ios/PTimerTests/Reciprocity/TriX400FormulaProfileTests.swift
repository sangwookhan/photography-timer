import XCTest
@testable import PTimer

/// Behavior contract for Tri-X 400's formula-based reciprocity
/// profile. Locks the invariants:
///
/// - Below 1 sec the threshold rule wins (no correction).
/// - At and above 1 sec the formula wins
///   (basis == `.formulaDerived`). Kodak's published row at
///   1 sec is +1 stop (corrected 2 sec); the formula intentionally
///   jumps from 1 sec metered to ≈ 2 sec corrected at the boundary
///   so the published step from 0 stops to +1 stop is preserved.
/// - The formula is a free log-log least squares fit through the
///   three published corrected-time rows (1/10/100 sec); inputs
///   above 100 sec continue on the same curve as numeric
///   continuation outside the published source range.
/// - All three published rows stay visible as source evidence,
///   carrying the stop delta, the corrected time, AND the
///   development adjustment (-10% / -20% / -30%).
final class TriX400FormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()
    private let expectedCoefficient: Double = 2.013654
    private let expectedExponent: Double = 1.3891

    // MARK: - Threshold boundary (exclusive at 1 s)

    func testTriX400BoundaryAt1SecondAppliesFormulaNotNoCorrection() throws {
        // Kodak publishes "no correction at or below 1 sec" via the
        // table notes, but the 1 sec row itself is +1 stop
        // (corrected 2 sec). The boundary is the start of the
        // corrected range; the catalog encodes that by ending the
        // threshold at 0.999999 sec so the formula fires at exactly
        // 1 sec.
        let profile = try triX400Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)

        XCTAssertEqual(
            result.metadata.basis,
            .formulaDerived,
            "1 sec is the start of Kodak's +1 stop range and must NOT collapse onto the no-correction threshold."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        // Free log-log fit predicts ≈ 2.01 sec at Tm=1.
        XCTAssertEqual(corrected, expectedCoefficient * pow(1, expectedExponent), accuracy: 0.01)
        XCTAssertEqual(corrected, 2, accuracy: 0.05, "Formula prediction at 1 sec must track Kodak's published 2 sec corrected exposure.")
    }

    // MARK: - Formula range (1 s … 100 s, source-backed)

    func testTriX400InsideFormulaRangeIsFormulaDerivedAcrossPublishedRows() throws {
        let profile = try triX400Profile()
        for metered in [1.0, 5.0, 10.0, 25.0, 50.0, 100.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) s sits inside the published 1–100 sec range and must be formula-derived."
            )
        }
    }

    func testTriX400FormulaTracksPublishedCorrectedTimesWithinFiftiethStop() throws {
        let profile = try triX400Profile()
        let samples: [(Double, Double)] = [(1, 2), (10, 50), (100, 1200)]
        for (metered, published) in samples {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            let stopError = log2(corrected / published)
            XCTAssertEqual(
                stopError,
                0,
                accuracy: 0.025,
                "Metered \(metered) s should land within 1/40 stop of the published corrected time (\(published) sec); got \(corrected) (err \(stopError) stop)."
            )
        }
    }

    func testTriX400FormulaUsesFreeLogLogFitCoefficient() throws {
        let profile = try triX400Profile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule.formula.exponent, expectedExponent, accuracy: 1e-3)
        let coefficient = try XCTUnwrap(formulaRule.formula.coefficient)
        XCTAssertEqual(coefficient, expectedCoefficient, accuracy: 1e-3)

        let equation = try XCTUnwrap(formulaRule.formula.equation)
        XCTAssertTrue(
            equation.contains("Tm^P"),
            "Equation must use the Tm^P placeholder; got: \(equation)"
        )

        let note = try XCTUnwrap(formulaRule.notes.first)
        XCTAssertTrue(
            note.lowercased().contains("log-log"),
            "Formula note must label the fit as log-log; got: \(note)"
        )
        XCTAssertTrue(
            note.lowercased().contains("numeric continuation"),
            "Formula note must describe values above 100 sec as numeric continuation outside the published source range; got: \(note)"
        )
    }

    // MARK: - Beyond the published source range (> 100 s)

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
                "Metered \(metered) s must keep a numeric continuation past the source range."
            )
            let expected = expectedCoefficient * pow(metered, expectedExponent)
            XCTAssertEqual(corrected, expected, accuracy: expected * 0.005)
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

            // Corrected time — used as the formula fitting basis.
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
            "Tri-X 400 must surface a Source reference section for its converted profile."
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
            "Converted Tri-X 400 must not surface the legacy Reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "Tri-X 400 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testTriX400DevelopmentLegendStillSurfacesAfterConversion() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(
            legend.lines.contains { $0 == "Development adjustment: Dev -10% means adjust development time by -10%." },
            "Tri-X 400 conversion must keep the development-adjustment legend line. Got: \(legend.lines)"
        )
    }

    @MainActor
    func testTriX400GraphCarriesSourceReferenceMarkersAtPublishedCorrectedTimes() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula)

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
            explanation.lowercased().contains("source range"),
            "Graph explanation must surface source-range wording past 100 sec; got: \(explanation)"
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
