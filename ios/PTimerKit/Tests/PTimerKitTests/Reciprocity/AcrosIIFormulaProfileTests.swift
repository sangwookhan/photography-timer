import XCTest
import PTimerKit
import PTimerCore

/// Behavior contract for Acros II's formula-based reciprocity
/// profile. Fujifilm's published guidance is a constant +1/2 stop
/// applied across 120–1000 sec (no per-second exact reference rows).
/// The catalog encodes this as:
///
/// - Threshold rule: no correction for inputs strictly below 120 s.
///   The threshold's upper bound sits at 119.999999 s so the formula
///   rule wins at exactly 120 s, matching Fujifilm's "from 120 s"
///   intent.
/// - Formula rule: Tc = √2 × Tm (coefficient √2, exponent 1) across
///   the published 120–1000 s range. The same constant continues
///   above 1000 s as numeric continuation outside the published
///   source range (basis == `.unsupportedOutOfPolicyRange`).
/// - Source evidence: a single 120–1000 s range row carrying
///   +1/2 stop. The range is preserved verbatim; no fabricated
///   per-second exact reference points are emitted.
final class AcrosIIFormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold boundary (exclusive at 120 s)

    func testAcrosIIBoundaryAt120SecondsAppliesHalfStopFormulaNotNoCorrection() throws {
        // Fujifilm's published guidance: no correction below 120 sec,
        // +1/2 stop applied across 120–1000 sec. The boundary itself
        // is the start of the corrected range, not the last
        // no-correction value.
        let profile = try acrosIIProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 120)

        XCTAssertEqual(
            result.metadata.basis,
            .formulaDerived,
            "120 s is the start of Fujifilm's +1/2 stop range and must NOT collapse onto the no-correction threshold."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 120 * sqrt(2.0), accuracy: 1e-4)
    }

    // MARK: - Formula range (120 s … 1000 s, constant +1/2 stop)

    func testAcrosIIInsideFormulaRangeAppliesConstantHalfStop() throws {
        let profile = try acrosIIProfile()
        for metered in [120.0, 150.0, 240.0, 500.0, 750.0, 1000.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) s sits inside the published 120–1000 s range and must be formula-derived (source-backed)."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                metered * sqrt(2.0),
                accuracy: 1e-4,
                "Metered \(metered) s must apply Tc = √2 × Tm (constant +1/2 stop)."
            )
        }
    }

    func testAcrosIIFormulaUsesConstantMultiplierForm() throws {
        let profile = try acrosIIProfile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.exponent, 1, accuracy: 1e-9)
        let coefficient = formulaRule.formula.coefficientSeconds
        XCTAssertEqual(coefficient, sqrt(2.0), accuracy: 1e-9)

        let note = try XCTUnwrap(formulaRule.notes.first)
        XCTAssertTrue(
            note.lowercased().contains("numeric continuation"),
            "Formula note must describe values above 1000 s as numeric continuation outside the published source range; got: \(note)"
        )
        XCTAssertFalse(
            note.lowercased().contains("extrapolation"),
            "Formula note must not use \"extrapolation\" wording for Acros II's constant continuation; got: \(note)"
        )
    }

    // MARK: - Beyond the published source range (> 1000 s)

    func testAcrosIIAbove1000SecondsBecomesBeyondSourceNumericGuidance() throws {
        let profile = try acrosIIProfile()
        for metered in [1100.0, 2000.0, 5000.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "Metered \(metered) s sits above the published 1000 s upper limit and must be marked outside manufacturer guidance."
            )
            let corrected = try XCTUnwrap(
                result.correctedExposureSeconds,
                "Metered \(metered) s must keep a numeric +1/2 stop continuation past the source range."
            )
            XCTAssertEqual(
                corrected,
                metered * sqrt(2.0),
                accuracy: 1e-3,
                "Above 1000 s the same +1/2 stop continues as numeric guidance."
            )
        }
    }

    // MARK: - Source evidence preservation

    func testAcrosIISourceEvidenceIsPreservedAsRangeNotFabricatedExactPoints() throws {
        let profile = try acrosIIProfile()

        XCTAssertEqual(
            profile.sourceEvidence.count,
            1,
            "Acros II's published guidance is a single 120–1000 s range row; conversion must not fabricate per-second exact reference points."
        )

        let row = try XCTUnwrap(profile.sourceEvidence.first)
        guard case let .range(range) = row.meteredExposure else {
            XCTFail("Source evidence row must remain a range, not exactSeconds. Got: \(row.meteredExposure).")
            return
        }
        XCTAssertEqual(range.minimumSeconds, 120, accuracy: 1e-6)
        XCTAssertEqual(range.maximumSeconds ?? 0, 1000, accuracy: 1e-6)

        let stopDelta = row.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
            return value.stopDelta
        }.first
        XCTAssertEqual(stopDelta ?? 0, 0.5, accuracy: 1e-6)
    }

    // MARK: - UI surfacing

    @MainActor
    func testAcrosIIDetailsSurfaceShowsRangeSourceReference() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 500)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Acros II must surface a Source reference section for its range guidance."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(
            sourceBlock.contains("120") && sourceBlock.contains("1000"),
            "Source reference row must surface both range boundaries; got block:\n\(sourceBlock)"
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Acros II is now formula-backed and must not surface the legacy Reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "Acros II has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testAcrosIISourceReferenceThresholdRowReadsAsStrictlyBelow120Seconds() throws {
        // The threshold rule's upper bound sits at 119.999999 s so
        // the formula fires at exactly 120 s. The Source reference
        // row must render that as "< 120s" (strict) rather than the
        // literal "<= 119.999999s" — otherwise the threshold band
        // and the formula range would both visually include 120 s.
        let displayState = try makeDisplayState(meteredExposureSeconds: 500)
        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" })
        )
        let block = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        let thresholdLine = try XCTUnwrap(
            block.split(separator: "\n").map(String.init).first(where: { $0.contains("No correction range") }),
            "Source reference must include a No correction range threshold row; got block:\n\(block)"
        )
        XCTAssertTrue(
            thresholdLine.contains("< 120"),
            "Threshold row must read as strict \"< 120\"; got: \(thresholdLine)"
        )
        XCTAssertFalse(
            thresholdLine.contains("<= 119"),
            "Threshold row must not surface the implementation-detail \"<= 119.999999s\"; got: \(thresholdLine)"
        )
        XCTAssertFalse(
            thresholdLine.contains("<= 120"),
            "Threshold row must not read \"<= 120\" — 120 s is the start of the +1/2 stop range; got: \(thresholdLine)"
        )
    }

    @MainActor
    func testAcrosIIFormulaGraphRendersWithoutPerSecondSourceMarkers() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 500)
        let graph = try XCTUnwrap(
            displayState.graph,
            "Acros II must surface a formula graph so users see the +1/2 stop relationship visually."
        )
        XCTAssertEqual(graph.kind, .formula)
        XCTAssertTrue(
            graph.sourceReferenceMarkers.isEmpty,
            "Acros II's range guidance must not be rendered as fabricated exact-point markers."
        )
        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "Acros II has no published not-recommended boundary."
        )

        let beyondStart = try XCTUnwrap(
            graph.beyondSourceRangeStartSeconds,
            "The graph must shade the region above the published 1000 s upper limit so users see where source-backed guidance ends."
        )
        XCTAssertEqual(beyondStart, 1000.000001, accuracy: 1e-3)
    }

    /// PTIMER-160's formatter regenerates the display from the
    /// formula's numeric fields, so the constant √2 multiplier
    /// renders as its decimal `1.4142 × Tm` form. The `^1` exponent
    /// is omitted as a neutral value so the multiplier-only shape
    /// reads cleanly.
    @MainActor
    func testAcrosIIFormulaGraphTextRendersConstantMultiplierWithoutSpuriousExponent() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 500)
        let graph = try XCTUnwrap(displayState.graph)
        let formula = try XCTUnwrap(graph.formulaDisplayText)
        XCTAssertEqual(formula, "Tc = 1.4142 × Tm")
    }

    /// Past 1000 s Acros II's numeric continuation must surface
    /// "source range" wording on both the detail copy and the graph
    /// explanation, so the value never reads as manufacturer-supported.
    @MainActor
    func testAcrosIIAbove1000SecondsDetailAndExplanationSurfaceSourceRangeWording() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 2000)
        let detail = try XCTUnwrap(displayState.summary.detailText)
        XCTAssertTrue(
            detail.lowercased().contains("source range"),
            "Detail text must surface source-range wording so the value never reads as manufacturer-supported; got: \(detail)"
        )

        let graph = try XCTUnwrap(displayState.graph)
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertTrue(
            explanation.lowercased().contains("source range"),
            "Graph explanation must surface source-range wording past 1000 s; got: \(explanation)"
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: "Acros II",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func acrosIIProfile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "Acros II")
    }
}
