import XCTest
@testable import PTimer

/// Behavior contract for T-MAX 400's formula-based reciprocity
/// profile. Locks the invariants:
///
/// - The 1/10,000 sec to 1 sec no-correction threshold band is
///   preserved verbatim — Kodak's "no adjustment required" range
///   carries through unchanged.
/// - The long-exposure formula is a threshold-anchored constrained
///   log-log fit through Kodak's published 10 s → 15 s and
///   100 s → 300 s corrected-time rows. The fit pins continuity
///   at the 1 sec threshold endpoint so the corrected exposure
///   never reads as less than the metered value at the boundary.
/// - Both published source rows stay visible as source evidence
///   carrying the stop delta AND the published corrected time.
/// - Above the 100 sec upper anchor the formula continues as
///   numeric continuation outside the published source range
///   (basis = `.unsupportedOutOfPolicyRange`).
final class TMax400FormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()
    private let expectedExponent: Double = 1.2261

    // MARK: - Threshold range (1/10000 sec to 1 sec)

    func testTMax400InsideThresholdBandReturnsOfficialNoCorrection() throws {
        let profile = try tmax400Profile()
        for metered in [0.0001, 0.001, 0.1, 0.5, 1.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "Metered \(metered) sec sits inside Kodak's 1/10000 sec–1 sec no-correction band."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, metered, accuracy: 1e-6)
        }
    }

    // MARK: - Formula range (> 1 sec, up to 100 sec)

    func testTMax400InsideFormulaRangeIsFormulaDerived() throws {
        let profile = try tmax400Profile()
        for metered in [2.0, 5.0, 10.0, 30.0, 100.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) sec sits inside the source-backed formula range."
            )
        }
    }

    func testTMax400FormulaTracksPublishedCorrectedTimesWithinSixthStop() throws {
        // Kodak rounds T-MAX 400's published corrected times for
        // practical use (the 10 sec row reads "+1/2 stop, 15 sec"
        // even though +1/2 stop literally derives to 14.14 sec, and
        // the 100 sec row reads "+1 1/2 stops, 300 sec" even though
        // +1.5 stops literally derives to 282.84 sec). The threshold
        // -anchored log-log fit balances those two rounded points,
        // landing within ~1/6 stop of each.
        let profile = try tmax400Profile()
        let samples: [(Double, Double)] = [(10, 15), (100, 300)]
        for (metered, published) in samples {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            let stopError = log2(corrected / published)
            XCTAssertEqual(
                stopError,
                0,
                accuracy: 0.2,
                "Metered \(metered) sec should land within 1/5 stop of the published corrected time (\(published) sec); got \(corrected) (err \(stopError) stop)."
            )
        }
    }

    func testTMax400FormulaIsThresholdAnchoredLogLogFit() throws {
        let profile = try tmax400Profile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule.formula.exponent, expectedExponent, accuracy: 1e-3)
        // Anchored at the 1 sec threshold endpoint so the coefficient
        // collapses to 1 and the equation is the bare power form.
        XCTAssertEqual(formulaRule.formula.coefficient ?? 1, 1, accuracy: 0.001)

        let equation = try XCTUnwrap(formulaRule.formula.equation)
        XCTAssertTrue(
            equation.contains("Tm^P"),
            "Equation must use the Tm^P placeholder; got: \(equation)"
        )

        let note = try XCTUnwrap(formulaRule.notes.first)
        XCTAssertTrue(
            note.lowercased().contains("threshold-anchored"),
            "Formula note must label the fit as threshold-anchored; got: \(note)"
        )
        XCTAssertTrue(
            note.lowercased().contains("log-log"),
            "Formula note must label the fit as log-log; got: \(note)"
        )
    }

    // MARK: - Continuity at the 1 sec threshold handoff

    func testTMax400AtFormulaRangeStartProducesContinuityWithThreshold() throws {
        // The formula range begins at 1.000001 sec so the formula
        // never returns a corrected exposure less than the metered
        // value at the boundary. At Tm = 1.000001 the formula
        // evaluates to ~1 sec (the threshold anchor), staying above
        // the no-correction value of 1 sec by less than 1/100 stop.
        let profile = try tmax400Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1.000001)
        guard case let .quantified(payload) = result else {
            return XCTFail("Tm just above 1 sec must remain quantified, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        XCTAssertGreaterThanOrEqual(
            payload.correctedExposureSeconds,
            1,
            "Formula handoff must not reduce exposure below the no-correction baseline at the boundary."
        )
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
                "Metered \(metered) sec must keep a numeric continuation past the source range."
            )
            let expected = pow(metered, expectedExponent)
            XCTAssertEqual(corrected, expected, accuracy: expected * 0.005)
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

    func testTMax400CalculationRulesDoNotContainPublishedTableEntries() throws {
        let profile = try tmax400Profile()
        for rule in profile.rules {
            if case .table = rule {
                XCTFail("T-MAX 400 must no longer carry a table rule — those entries are source evidence only.")
            }
        }
    }

    func testTMax400IsConvertedFormulaProfile() throws {
        let profile = try tmax400Profile()
        XCTAssertTrue(profile.isConvertedFormulaProfile)
    }

    // MARK: - UI surfacing

    @MainActor
    func testTMax400DetailsSurfaceShowsSourceReferenceRows() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "T-MAX 400 must surface a Source reference section for its converted profile."
        )
        let block = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(block.contains("10.0s"))
        XCTAssertTrue(block.contains("100.0s"))
        XCTAssertTrue(block.contains("15"))
        XCTAssertTrue(block.contains("300"))
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Converted T-MAX 400 must not surface the legacy Reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "T-MAX 400 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testTMax400GraphCarriesSourceReferenceMarkersAtPublishedCorrectedTimes() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula)

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

    @MainActor
    func testTMax400InsideRangeUsesReferenceBackedSummary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        XCTAssertEqual(displayState.summary.summaryText, "Reference-backed formula prediction")
    }

    @MainActor
    func testTMax400Above100SecondsUsesBeyondSourceRangeWording() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 400)
        XCTAssertEqual(displayState.summary.summaryText, "Beyond source range")
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
            film: "T-MAX 400",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func tmax400Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "T-MAX 400")
    }
}
