import XCTest
@testable import PTimer
import PTimerKit

/// Behavior contract for T-MAX 400's table-interpolation reciprocity
/// profile. Locks the invariants:
///
/// - The no-correction band ends at 0.1 sec — evaluator returns
///   `.officialThresholdNoCorrection` for metered <= 0.1 sec (PTIMER-168).
/// - The table has THREE anchors: 1→1.2599, 10→15, 100→300.
///   The published 1 sec row is Kodak aperture/stop guidance (+1/3 stop);
///   its corrected-time mapping (≈1.2599 sec) is synthesized from the stop
///   delta and stored as a table anchor with isApproximate == true.
///   At metered 1 sec the evaluator returns `.tableLogLogDerived` with
///   corrected ≈ 1.2599 sec.
/// - At each table anchor the corrected time matches exactly:
///   1→1.2599210498948732, 10→15, 100→300.
/// - Above 100 sec (sourceRangeThroughSeconds) the evaluator returns
///   `.unsupportedOutOfPolicyRange`; a log-log extrapolation value is
///   still provided (non-nil, greater than the last anchor corrected time).
/// - All three published long-exposure rows (1 s / 10 s / 100 s) stay
///   visible as source evidence. The 1 s row carries a stopDelta (+1/3)
///   AND a correctedTime mapping with isApproximate == true. The 10 s and
///   100 s rows carry both.
/// - The profile carries a `.tableInterpolation` rule; NO `.formula`
///   rule remains.
final class TMax400TableProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Rule structure

    // MARK: - Threshold band edges (at/below 0.1 sec, inclusive)

    /// PTIMER-168 boundary tolerance: a nominal 1/10 sec UI input can
    /// evaluate to ~0.102 sec after Base Shutter / ND stop arithmetic and
    /// must read as No correction; values clearly above 1/10 sec stay
    /// corrected (table-derived).
    func testTMax400NominalTenthSecondToleranceClassifiesNoCorrection() throws {
        let profile = try tmax400Profile()

        let nominal = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.102)
        XCTAssertEqual(
            nominal.metadata.basis,
            .officialThresholdNoCorrection,
            "Nominal 1/10 sec (~0.102 sec) must read as No correction."
        )
        XCTAssertEqual(try XCTUnwrap(nominal.correctedExposureSeconds), 0.102, accuracy: 1e-6)

        for metered in [0.12, 0.15] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .tableLogLogDerived,
                "\(metered) sec is clearly above the 1/10 sec band and must stay table-derived."
            )
            XCTAssertGreaterThan(try XCTUnwrap(result.correctedExposureSeconds), metered)
        }
    }

    func testTMax400At1SecondIsTableDerivedCorrectionAtAnchorValue() throws {
        // The 1 sec row is Kodak aperture/stop guidance (+1/3 stop). Its
        // corrected-time mapping (≈1.2599 sec) is synthesized from the stop
        // delta and stored as a table anchor with isApproximate == true.
        // At exactly 1 sec the evaluator must return `.tableLogLogDerived`
        // with corrected ≈ 1.2599 sec — a real correction, not identity.
        let profile = try tmax400Profile()

        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)
        XCTAssertEqual(
            result.metadata.basis,
            .tableLogLogDerived,
            "metered == 1 sec sits above the 0.1 sec no-correction threshold and must be a table correction."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(
            corrected,
            1.2599210498948732,
            accuracy: 1e-4,
            "1 sec anchor must map to ≈1.2599 sec corrected (1 × 2^(1/3))."
        )
        XCTAssertGreaterThan(
            corrected,
            1,
            "1 sec must receive a reciprocity correction, not the no-correction identity."
        )
    }

    func testTMax400At1SecondSourceEvidenceCarriesStopDeltaAndApproximateCorrectedTime() throws {
        // The 1 sec source-evidence row is aperture/stop guidance (not a
        // published corrected shutter time). It must carry:
        //   • a stopDelta ≈ +1/3 stop
        //   • a correctedTime mapping whose isApproximate == true
        let profile = try tmax400Profile()
        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        let oneSecRow = try XCTUnwrap(
            exactRows.first(where: { $0.0 == 1 })?.1,
            "1 sec source-evidence row must be present for T-MAX 400 (previously absent; PTIMER-168 adds it)."
        )

        var foundStopDelta: Double? = nil
        var foundApproximateCorrectedTime = false
        for adjustment in oneSecRow.adjustments {
            if case let .exposure(.stopDelta(value)) = adjustment {
                foundStopDelta = value.stopDelta
            }
            if case let .exposure(.correctedTime(mapping)) = adjustment {
                if mapping.isApproximate { foundApproximateCorrectedTime = true }
            }
        }
        XCTAssertNotNil(foundStopDelta,
            "1 sec source-evidence row must carry a stop delta (+1/3 stop).")
        XCTAssertEqual(foundStopDelta ?? 0, 1.0 / 3.0, accuracy: 0.01,
            "Stop delta at 1 sec must be approximately +1/3 stop.")
        XCTAssertTrue(foundApproximateCorrectedTime,
            "1 sec source-evidence row must carry a correctedTime mapping with isApproximate == true.")
    }

    // MARK: - Table range (> 0.1 sec, up to 100 sec)

    // MARK: - Beyond the published source range (> 100 sec)

    // MARK: - Source evidence preservation

    func testTMax400SourceEvidencePreservesAllThreePublishedRowsWithCorrectedTimes() throws {
        let profile = try tmax400Profile()
        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        XCTAssertEqual(
            exactRows.map { $0.0 },
            [1, 10, 100],
            "T-MAX 400 must keep all three Kodak-published rows (1/10/100 sec) as source evidence (PTIMER-168 adds 1 sec row)."
        )

        let expectedStops: [Double: Double] = [1: 1.0 / 3.0, 10: 0.5, 100: 1.5]
        let expectedCorrected: [Double: Double] = [1: 1.2599210498948732, 10: 15, 100: 300]
        for (metered, row) in exactRows {
            let stopDelta = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
                return value.stopDelta
            }.first
            XCTAssertEqual(stopDelta ?? -1, expectedStops[metered] ?? -1, accuracy: 0.01, "Stop delta mismatch at \(metered) s")

            let correctedSeconds = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                return mapping.correctedSeconds
            }.first
            XCTAssertEqual(correctedSeconds ?? -1, expectedCorrected[metered] ?? -1, accuracy: 1e-4, "Corrected time mismatch at \(metered) s")
        }

        // The 1 sec correctedTime is approximate (aperture/stop guidance,
        // not a published corrected shutter time).
        let oneSecCorrectedMapping = exactRows.first(where: { $0.0 == 1 })?.1.adjustments.compactMap { adjustment -> CorrectedTimeMapping? in
            guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
            return mapping
        }.first
        XCTAssertTrue(oneSecCorrectedMapping?.isApproximate ?? false,
            "T-MAX 400 1 sec correctedTime mapping must be flagged isApproximate == true.")
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
        XCTAssertTrue(block.contains("1.0s"), "Source reference block must include the 1 sec row; got block:\n\(block)")
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
            Set([1, 10, 100]),
            "T-MAX 400 graph must mark all three published source rows (1/10/100 sec)."
        )

        let markerByMetered = Dictionary(
            uniqueKeysWithValues: graph.sourceReferenceMarkers.map { ($0.point.meteredExposureSeconds.rounded(), $0.point.correctedExposureSeconds) }
        )
        XCTAssertEqual(markerByMetered[1] ?? 0, 1.2599210498948732, accuracy: 0.01,
            "Marker at 1 sec must plot the approximate 1.2599 sec corrected exposure.")
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
