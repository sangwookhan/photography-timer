import XCTest
@testable import PTimer

/// Behavior contract for T-MAX 100's formula-based reciprocity
/// profile. Locks the invariants:
///
/// - The 1/1000–1/10 sec no-correction threshold band is preserved.
/// - The 1/10,000 sec short-exposure +1/3 stop guidance is NOT used
///   as a long-exposure formula fitting point. It stays archived in
///   `profile.notes` so the source data sheet remains catalog-
///   preserved, and it is explicitly excluded from `sourceEvidence`
///   so it can never bend the long-exposure graph.
/// - The long-exposure formula is a threshold-anchored constrained
///   log-log fit through Kodak's published 10 s → 15 s and
///   100 s → 200 s corrected-time rows. The 1 s +1/3 stop row is
///   preserved as source evidence (stop delta only — the catalog
///   does not synthesize a corrected-time anchor) and not as a
///   fitting point.
/// - All three published long-exposure rows (1 s / 10 s / 100 s)
///   stay visible as source evidence so users can verify the
///   formula curve against the published anchors.
/// - Above the 100 s upper anchor the formula continues as numeric
///   continuation outside the published source range
///   (basis = `.unsupportedOutOfPolicyRange`).
final class TMax100FormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()
    private let expectedAnchor: Double = 0.1
    private let expectedExponent: Double = 1.0966

    // MARK: - Threshold range (1/1000 sec to 1/10 sec)

    func testTMax100InsideThresholdBandReturnsOfficialNoCorrection() throws {
        let profile = try tmax100Profile()
        for metered in [0.001, 0.01, 0.05, 0.1] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "Metered \(metered) sec sits inside Kodak's 1/1000 sec–1/10 sec no-correction band."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, metered, accuracy: 1e-6)
        }
    }

    // MARK: - Long-exposure formula range (> 1/10 sec, up to 100 sec)

    func testTMax100InsideFormulaRangeIsFormulaDerivedThroughPublishedRows() throws {
        let profile = try tmax100Profile()
        for metered in [0.5, 1.0, 4.0, 10.0, 50.0, 100.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) sec sits inside the source-backed long-exposure formula range."
            )
        }
    }

    func testTMax100FormulaTracksPublishedCorrectedTimesWithinTenthStop() throws {
        let profile = try tmax100Profile()
        let samples: [(Double, Double)] = [(10, 15), (100, 200)]
        for (metered, published) in samples {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            let stopError = log2(corrected / published)
            XCTAssertEqual(
                stopError,
                0,
                accuracy: 0.1,
                "Metered \(metered) sec should land within 1/10 stop of the published corrected time (\(published) sec); got \(corrected) (err \(stopError) stop)."
            )
        }
    }

    func testTMax100FormulaIsThresholdAnchoredLogLogFit() throws {
        let profile = try tmax100Profile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule.formula.exponent, expectedExponent, accuracy: 1e-3)
        // coefficient encodes the 1/10 sec threshold anchor: 0.1^(1 - P).
        let expectedCoefficient = pow(expectedAnchor, 1 - expectedExponent)
        let coefficient = try XCTUnwrap(formulaRule.formula.coefficient)
        XCTAssertEqual(coefficient, expectedCoefficient, accuracy: 1e-3)

        let equation = try XCTUnwrap(formulaRule.formula.equation)
        XCTAssertTrue(
            equation.contains("0.1"),
            "Equation must communicate the 1/10 sec threshold anchor; got: \(equation)"
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
        XCTAssertTrue(
            note.lowercased().contains("1/10,000") || note.lowercased().contains("short-exposure"),
            "Formula note must explicitly document why the 1/10000 sec short-exposure row is excluded from the long-exposure fit; got: \(note)"
        )
    }

    // MARK: - Short-exposure guidance is excluded from the long-exposure curve

    func testTMax100Short1Over10000ExposureIsNotALongExposureFittingPoint() throws {
        let profile = try tmax100Profile()
        // 1/10000 sec sits below the threshold band so the evaluator
        // returns nothing for it via the long-exposure formula. The
        // profile-level note still documents Kodak's +1/3 stop short
        // -exposure guidance; the formula curve must not accidentally
        // inherit that anchor.
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1.0 / 10_000.0)
        XCTAssertEqual(
            result.metadata.basis,
            .unsupportedOutOfPolicyRange,
            "1/10000 sec sits below the 1/1000 sec no-correction lower bound; the long-exposure rules must not silently quantify it via the formula curve."
        )

        let shortExposureMetered = 1.0 / 10_000.0
        for evidence in profile.sourceEvidence {
            if case let .exactSeconds(seconds) = evidence.meteredExposure {
                XCTAssertGreaterThan(
                    seconds,
                    shortExposureMetered * 10,
                    "1/10000 sec short-exposure row must not be added to long-exposure sourceEvidence; got entry at \(seconds) sec."
                )
            }
        }
    }

    func testTMax100ShortExposureGuidanceIsPreservedAtCatalogLevelOnly() throws {
        // Catalog-level preservation contract: the published
        // 1/10,000 sec +1/3 stop short-exposure guidance lives on
        // `profile.notes` so the source data sheet stays archived
        // in the catalog. The Details surface does not currently
        // render `profile.notes` (see FilmModeDetailsPresenter —
        // the Sources section only reads `profile.source`), so this
        // is a source-fidelity preservation, not a UI surface. A
        // future ticket can wire it through if photographers ask
        // for it; until then, this test ensures the catalog never
        // silently drops Kodak's high-speed guidance.
        let profile = try tmax100Profile()
        let notes = profile.notes.joined(separator: "\n").lowercased()
        XCTAssertTrue(
            notes.contains("1/10,000") || notes.contains("short-exposure"),
            "profile.notes must keep the 1/10000 sec short-exposure +1/3 stop guidance archived; got notes: \(profile.notes)"
        )
    }

    // MARK: - Beyond the published source range (> 100 sec)

    func testTMax100Above100SecondsBecomesBeyondSourceNumericGuidance() throws {
        let profile = try tmax100Profile()
        for metered in [150.0, 300.0, 1000.0] {
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
            let expected = pow(expectedAnchor, 1 - expectedExponent) * pow(metered, expectedExponent)
            XCTAssertEqual(corrected, expected, accuracy: expected * 0.005)
        }
    }

    // MARK: - Source evidence preservation

    func testTMax100SourceEvidencePreservesPublishedLongExposureRows() throws {
        let profile = try tmax100Profile()
        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        XCTAssertEqual(
            exactRows.map { $0.0 },
            [1, 10, 100],
            "T-MAX 100 must keep Kodak's three published long-exposure rows (1/10/100 sec) as source evidence."
        )

        // The 10 sec and 100 sec rows publish both a stop delta AND
        // a corrected time; the 1 sec row publishes only a stop delta
        // (the derived corrected time lives on the graph marker via
        // the presenter, not in the catalog).
        let oneSecRow = exactRows.first(where: { $0.0 == 1 })?.1
        XCTAssertNotNil(oneSecRow)
        let oneSecHasCorrectedTime = oneSecRow?.adjustments.contains { adjustment in
            if case .exposure(.correctedTime) = adjustment { return true }
            return false
        } ?? false
        XCTAssertFalse(
            oneSecHasCorrectedTime,
            "Kodak publishes only +1/3 stop at 1 sec; the catalog must not synthesize a corrected-time anchor that would join the formula fit."
        )

        let tenSecRow = exactRows.first(where: { $0.0 == 10 })?.1
        let tenSecCorrected = tenSecRow?.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
            return mapping.correctedSeconds
        }.first
        XCTAssertEqual(tenSecCorrected, 15)

        let hundredSecRow = exactRows.first(where: { $0.0 == 100 })?.1
        let hundredSecCorrected = hundredSecRow?.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
            return mapping.correctedSeconds
        }.first
        XCTAssertEqual(hundredSecCorrected, 200)
    }

    func testTMax100CalculationRulesDoNotContainPublishedTableEntries() throws {
        let profile = try tmax100Profile()
        for rule in profile.rules {
            if case .table = rule {
                XCTFail("T-MAX 100 must no longer carry a table rule — those entries are source evidence only.")
            }
        }
    }

    func testTMax100IsConvertedFormulaProfile() throws {
        let profile = try tmax100Profile()
        XCTAssertTrue(profile.isConvertedFormulaProfile)
    }

    // MARK: - UI surfacing

    @MainActor
    func testTMax100DetailsSurfaceShowsSourceReferenceRows() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "T-MAX 100 must surface a Source reference section for its converted profile."
        )
        let block = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(block.contains("1.0s"), "Source reference block must include the 1 sec row; got block:\n\(block)")
        XCTAssertTrue(block.contains("10.0s"))
        XCTAssertTrue(block.contains("100.0s"))
        XCTAssertTrue(block.contains("15"))
        XCTAssertTrue(block.contains("200"))
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Converted T-MAX 100 must not surface the legacy Reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "T-MAX 100 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testTMax100GraphCarriesSourceReferenceMarkersForAllThreePublishedRows() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula)

        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
        XCTAssertEqual(
            Set(markerMetereds),
            Set([1, 10, 100]),
            "T-MAX 100 graph must mark all three published long-exposure rows."
        )

        let markerByMetered = Dictionary(
            uniqueKeysWithValues: graph.sourceReferenceMarkers.map { ($0.point.meteredExposureSeconds.rounded(), $0.point.correctedExposureSeconds) }
        )
        // 1 sec row publishes a stop delta only; the marker uses the
        // stop-derived value 1 × 2^(1/3) ≈ 1.26.
        XCTAssertEqual(markerByMetered[1] ?? 0, 1.2599, accuracy: 0.01)
        XCTAssertEqual(markerByMetered[10] ?? 0, 15, accuracy: 0.01)
        XCTAssertEqual(markerByMetered[100] ?? 0, 200, accuracy: 0.01)

        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "T-MAX 100 has no published not-recommended boundary."
        )

        let beyondStart = try XCTUnwrap(
            graph.beyondSourceRangeStartSeconds,
            "The graph must shade the region above 100 sec so the user sees where source-backed guidance ends."
        )
        XCTAssertEqual(beyondStart, 100.000001, accuracy: 1e-3)
    }

    @MainActor
    func testTMax100InsideRangeUsesReferenceBackedSummary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        XCTAssertEqual(displayState.summary.summaryText, "Reference-backed formula prediction")
    }

    @MainActor
    func testTMax100Above100SecondsUsesBeyondSourceRangeWording() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 300)
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
            film: "T-MAX 100",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func tmax100Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "T-MAX 100")
    }
}
