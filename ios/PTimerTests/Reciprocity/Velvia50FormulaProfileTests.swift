import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Behavior contract for Velvia 50's formula-based reciprocity
/// profile. Locks the invariants:
///
/// - Below the 1 s no-correction threshold the threshold rule wins.
/// - In (1 s, 32 s] the formula wins (basis == `.formulaDerived`),
///   even at the published 4/8/16/32 s reference rows — the formula
///   closely tracks them but the rows live as source evidence only.
/// - The source-backed range ends at the 32 s anchor (PTIMER-160);
///   inputs above 32 s classify as `.unsupportedOutOfPolicyRange`
///   with a numeric formula-derived continuation value.
/// - The 64 s row is preserved as a "Not recommended" warning
///   marker only and is never used as a formula fitting point.
/// - All five published rows stay visible as `sourceEvidence`.
final class Velvia50FormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold boundary (inclusive at 1 s)

    func testVelvia50AtThresholdBoundaryReturnsOfficialNoCorrection() throws {
        let profile = try velvia50Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 1, accuracy: 1e-6)
    }

    // MARK: - Source-backed formula range (1 s … 32 s inclusive)

    func testVelvia50InsideSourceBackedRangeIsFormulaDerivedNotExactTablePoint() throws {
        let profile = try velvia50Profile()
        for metered in [2.0, 4.0, 8.0, 16.0, 24.0, 32.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) s must be formula-derived even at published source rows (4/8/16/32 s)."
            )
        }
    }

    func testVelvia50FormulaIsAnchoredLogLogFit() throws {
        let profile = try velvia50Profile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.exponent, 1.1821, accuracy: 0.001)
        // Anchored at 1 s threshold endpoint, so the coefficient
        // collapses to 1 and the equation is the bare power form.
        XCTAssertEqual(formulaRule.formula.coefficientSeconds, 1, accuracy: 0.001)

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

    // MARK: - Beyond the source-backed range (> 32 s, with 64 s as
    // a warning marker)

    /// PTIMER-160: the source-backed range ends at the 32 s anchor.
    /// 50 s, 64 s, and 90 s all sit above that boundary; the formula
    /// keeps producing a numeric continuation but the basis must
    /// classify them as outside the source range. 64 s also exists as
    /// a published "Not recommended" warning marker, which surfaces
    /// independently through the source-evidence row — it does not
    /// promote 64 s back into source-backed status.
    func testVelvia50Above32SecondsCarriesFormulaPredictionAsBeyondSource() throws {
        let profile = try velvia50Profile()
        for metered in [50.0, 64.0, 90.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "Velvia 50 at \(metered) s sits above the 32 s source-backed boundary."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, pow(metered, 1.1821), accuracy: 1)
        }
    }

    // MARK: - Source-evidence preservation

    func testVelvia50SourceEvidencePreservesFiveExactRowsIncludingNotRecommendedBoundary() throws {
        let profile = try velvia50Profile()

        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        XCTAssertEqual(
            exactRows.map { $0.0 },
            [4, 8, 16, 32, 64],
            "Velvia 50 must keep all five Fujifilm-published rows as source evidence (4/8/16/32 s reference points and the 64 s not-recommended boundary)."
        )

        // Spot-check filters and stop deltas on the four reference rows.
        let filtersByMetered: [Double: String] = [4: "5M", 8: "7.5M", 16: "10M", 32: "12.5M"]
        for (metered, row) in exactRows where metered != 64 {
            let filterName = row.adjustments.compactMap { adjustment -> String? in
                guard case let .colorFilter(filter) = adjustment else { return nil }
                return filter.filterName
            }.first
            XCTAssertEqual(filterName, filtersByMetered[metered], "Color filter at \(metered) s must match the published reference.")

            let hasStopDelta = row.adjustments.contains { adjustment in
                if case .exposure(.stopDelta) = adjustment { return true }
                return false
            }
            XCTAssertTrue(hasStopDelta, "Source-evidence row at \(metered) s must keep a stop delta adjustment.")
        }

        let notRecommendedRow = exactRows.first(where: { $0.0 == 64 })?.1
        let warningSeverity = notRecommendedRow?.adjustments.compactMap { adjustment -> ReciprocityWarningSeverity? in
            guard case let .warning(warning) = adjustment else { return nil }
            return warning.severity
        }.first
        XCTAssertEqual(warningSeverity, .notRecommended, "64 s row must carry the not-recommended warning.")
    }

    // MARK: - UI surfacing

    @MainActor
    func testVelvia50DetailsSplitsSourceReferenceAndGuidanceBoundarySections() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 8)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Velvia 50 must surface a Source reference section."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(sourceBlock.contains("5M"))
        XCTAssertTrue(sourceBlock.contains("7.5M"))
        XCTAssertTrue(sourceBlock.contains("10M"))
        XCTAssertTrue(sourceBlock.contains("12.5M"))
        XCTAssertFalse(
            sourceBlock.contains("Not recommended"),
            "Source reference section must not contain the 64 s not-recommended boundary row."
        )

        let guidanceBoundarySection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Guidance boundary" }),
            "Velvia 50 must surface a Guidance boundary section for the 64 s row."
        )
        let boundaryBlock = try XCTUnwrap(guidanceBoundarySection.rows.first?.value)
        XCTAssertTrue(boundaryBlock.contains("Not recommended"))
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Converted Velvia 50 must not surface the legacy Reference section."
        )
    }

    @MainActor
    func testVelvia50GraphCarriesSourceReferenceMarkersAndNotRecommendedBoundary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 8)
        let graph = try XCTUnwrap(displayState.graph)

        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
        XCTAssertEqual(
            Set(markerMetereds),
            Set([4, 8, 16, 32]),
            "Velvia 50 graph must mark the four published reference rows and exclude 64 s."
        )

        XCTAssertEqual(graph.notRecommendedBoundarySeconds ?? 0, 64, accuracy: 1e-6)
        for marker in graph.sourceReferenceMarkers {
            XCTAssertNotEqual(
                marker.point.meteredExposureSeconds,
                64,
                accuracy: 1e-6,
                "64 s must remain a Guidance boundary, never a source-reference fitting point."
            )
        }
    }

    /// Detail copy past the not-recommended boundary surfaces "source
    /// range" without the "Extrapolated" label — Velvia 50's numeric
    /// formula prediction is explicitly outside Fujifilm's supported
    /// range. Negative guard for the table-era label.
    @MainActor
    func testVelvia50BeyondSourceRangeDetailAvoidsExtrapolatedWording() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 100)
        let detail = try XCTUnwrap(displayState.summary.detailText)
        XCTAssertFalse(detail.lowercased().contains("extrapolated"))
        XCTAssertTrue(detail.lowercased().contains("source range"))
    }

    // MARK: - Helpers

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: "Velvia 50",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func velvia50Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "Velvia 50")
    }
}
