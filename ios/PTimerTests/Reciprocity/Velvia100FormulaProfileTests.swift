import XCTest
@testable import PTimer

/// Behavior contract for Velvia 100's formula-based reciprocity
/// profile. Locks the invariants:
///
/// - Below the 60 s no-correction threshold the threshold rule wins.
/// - The formula range is closed at the published 240 s reference
///   row so 240 s itself reads as `.formulaDerived` (source-backed).
/// - Only inputs strictly greater than 240 s become beyond-source
///   numeric guidance (basis == `.unsupportedOutOfPolicyRange`).
/// - Both published rows (2 min / 4 min) and the 2.5M magenta
///   color guidance stay visible as source evidence; the graph has
///   no published not-recommended boundary.
final class Velvia100FormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold boundary (inclusive at 60 s)

    func testVelvia100AtThresholdBoundaryReturnsOfficialNoCorrection() throws {
        let profile = try velvia100Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 60)

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 60, accuracy: 1e-6)
    }

    // MARK: - Formula range, including the 240 s published row

    func testVelvia100InsideFormulaRangeIsFormulaDerived() throws {
        let profile = try velvia100Profile()
        for metered in [80.0, 120.0, 150.0, 200.0, 239.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) s must be formula-derived."
            )
        }
    }

    func testVelvia100At240SecondsIsFormulaDerivedSourceBackedNotUnsupported() throws {
        // 240 s is the published 4-min +1/2-stop reference row. The
        // formula range must include 240 s itself so the basis stays
        // `.formulaDerived` (source-backed) and only inputs strictly
        // greater than 240 s become beyond-source numeric guidance.
        let profile = try velvia100Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 240)

        XCTAssertEqual(
            result.metadata.basis,
            .formulaDerived,
            "240 s is a Fujifilm-published reference row and must remain inside the source-backed formula range."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        let expected = pow(60.0, 1 - 1.2667) * pow(240.0, 1.2667)
        XCTAssertEqual(corrected, expected, accuracy: 1)
    }

    func testVelvia100FormulaExponentMatchesAnchoredLogLogFit() throws {
        let profile = try velvia100Profile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule.formula.exponent, 1.2667, accuracy: 0.001)
        // coefficient encodes the 60 s threshold anchor: 60^(1 - P).
        let expectedCoefficient = pow(60.0, 1 - 1.2667)
        let coefficient = try XCTUnwrap(formulaRule.formula.coefficient)
        XCTAssertEqual(coefficient, expectedCoefficient, accuracy: 0.001)

        let equation = try XCTUnwrap(formulaRule.formula.equation)
        XCTAssertTrue(
            equation.contains("60"),
            "Equation must communicate the 60 s threshold anchor; got: \(equation)"
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

    // MARK: - Beyond source range (> 240 s) with formula extrapolation

    func testVelvia100Above240SecondsBecomesBeyondSourceNumericGuidance() throws {
        let profile = try velvia100Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 300)

        XCTAssertEqual(
            result.metadata.basis,
            .unsupportedOutOfPolicyRange,
            "Inputs above the 240 s published row must be classified as outside manufacturer guidance even though the formula keeps producing a value."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        let expected = pow(60.0, 1 - 1.2667) * pow(300.0, 1.2667)
        XCTAssertEqual(corrected, expected, accuracy: 1)
    }

    func testVelvia100Beyond240SecondsKeepsFormulaPredictionAndStaysUnsupported() throws {
        let profile = try velvia100Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 400)

        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        let expected = pow(60.0, 1 - 1.2667) * pow(400.0, 1.2667)
        XCTAssertEqual(corrected, expected, accuracy: 1)
    }

    // MARK: - Source-evidence preservation

    func testVelvia100SourceEvidencePreservesTwoExactRowsWith2dot5MagentaFilter() throws {
        let profile = try velvia100Profile()

        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        XCTAssertEqual(
            exactRows.map { $0.0 },
            [120, 240],
            "Velvia 100 must keep both Fujifilm-published rows (2 min and 4 min) as source evidence."
        )
        for (_, row) in exactRows {
            let filterName = row.adjustments.compactMap { adjustment -> String? in
                guard case let .colorFilter(filter) = adjustment else { return nil }
                return filter.filterName
            }.first
            XCTAssertEqual(filterName, "2.5M", "Velvia 100 source evidence must preserve the published 2.5M magenta correction.")
        }
    }

    // MARK: - UI surfacing

    @MainActor
    func testVelvia100DetailsSurfacesSourceReferenceWithoutGuidanceBoundary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 120)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Velvia 100 must surface a Source reference section for its converted profile."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(sourceBlock.contains("2.5M"))

        // Velvia 100 has no published not-recommended row.
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "Velvia 100 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testVelvia100GraphCarriesSourceMarkersWithoutNotRecommendedBoundary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 120)
        let graph = try XCTUnwrap(displayState.graph)

        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
        XCTAssertEqual(Set(markerMetereds), Set([120, 240]))
        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "Velvia 100 has no published not-recommended boundary, so the graph must not draw one."
        )
    }

    /// 240 s is Velvia 100's published reference row; the summary
    /// must read as source-backed at this exact value and never tip
    /// into "Beyond source range".
    @MainActor
    func testVelvia100At240SecondsSummaryStaysReferenceBacked() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Reference-backed formula prediction",
            "240 s is a Fujifilm-published reference; the summary must read as source-backed, not Beyond source range."
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: "Velvia 100",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func velvia100Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "Velvia 100")
    }
}
