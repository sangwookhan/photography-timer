import XCTest
@testable import PTimer

/// Behavior contract for T-MAX 100's table-interpolation reciprocity
/// profile. Locks the invariants:
///
/// - The no-correction band ends at 0.5 sec — evaluator returns
///   `.officialThresholdNoCorrection` for metered <= 0.5 sec. Kodak's
///   published 1 sec +1/3 stop row marks 1 sec as already outside the
///   no-correction band, so the table's threshold is 0.5 sec (PTIMER-168).
/// - The table has ONLY TWO anchors (10→15 and 100→200). The published
///   1 sec row carries a +1/3 stop delta only; the catalog deliberately
///   does NOT synthesize a corrected-time anchor from it. At metered 1 sec
///   the evaluator therefore returns a `.tableLogLogDerived` correction
///   (interpolated from the 0.5 sec knee toward the 10 sec anchor), not
///   no-correction and not a published anchor value.
/// - At each table anchor the corrected time matches exactly: 10→15, 100→200.
/// - Above 100 sec (sourceRangeThroughSeconds) the evaluator returns
///   `.unsupportedOutOfPolicyRange`; a log-log extrapolation value is
///   still provided (non-nil, greater than the last anchor corrected time).
/// - All three published long-exposure rows (1 s / 10 s / 100 s) stay
///   visible as source evidence. The 1 s row carries a stop delta but
///   NO corrected time. The 10 s and 100 s rows carry both.
/// - The profile carries a `.tableInterpolation` rule; NO `.formula`
///   rule remains.
final class TMax100TableProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Rule structure

    func testTMax100HasTableInterpolationRuleAndNoFormulaRule() throws {
        let profile = try tmax100Profile()

        let tableRule = profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
            if case let .tableInterpolation(r) = rule { return r } else { return nil }
        }.first
        XCTAssertNotNil(tableRule, "T-MAX 100 must carry a .tableInterpolation rule after migration.")

        let hasFormulaRule = profile.rules.contains { rule in
            if case .formula = rule { return true } else { return false }
        }
        XCTAssertFalse(hasFormulaRule, "T-MAX 100 must NOT carry a .formula rule after migration to table.")
    }

    func testTMax100TableRuleParametersMatchPublishedAnchors() throws {
        let profile = try tmax100Profile()
        let tableRule = try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r } else { return nil }
            }.first,
            "tableInterpolation rule must be present."
        )

        XCTAssertEqual(tableRule.noCorrectionThroughSeconds, 0.5, accuracy: 1e-6,
            "noCorrectionThroughSeconds must be 0.5 — the 1 sec +1/3 stop row marks 1 sec as outside the no-correction band.")
        XCTAssertEqual(tableRule.sourceRangeThroughSeconds, 100, accuracy: 1e-6,
            "sourceRangeThroughSeconds must be 100.")

        let anchorMetereds = tableRule.anchors.map { $0.meteredSeconds }
        XCTAssertEqual(anchorMetereds, [10, 100],
            "Table must have exactly two anchors at 10/100 sec. The published 1 sec +1/3 stop row is NOT an anchor.")

        let anchorCorrected = tableRule.anchors.map { $0.correctedSeconds }
        XCTAssertEqual(anchorCorrected[0], 15, accuracy: 1e-4,
            "Anchor at 10 sec must map to 15 sec corrected.")
        XCTAssertEqual(anchorCorrected[1], 200, accuracy: 1e-4,
            "Anchor at 100 sec must map to 200 sec corrected.")
    }

    func testTMax100ModelBasisIsManufacturerTableLogLogInterpolation() throws {
        let profile = try tmax100Profile()
        let basis = try XCTUnwrap(profile.modelBasis,
            "T-MAX 100 profile must carry a modelBasis after migration.")
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation)
    }

    // MARK: - Threshold boundary (0.5 sec, inclusive)
    // IMPORTANT (PTIMER-168): noCorrectionThroughSeconds == 0.5. The 1 sec
    // source-evidence row carries only a +1/3 stop delta (no corrected time).
    // The catalog does NOT synthesize a corrected-time anchor from it, but the
    // row marks 1 sec as already outside the no-correction band — so the table
    // threshold ends at 0.5 sec and 1 sec evaluates as a table correction.

    func testTMax100AtAndBelowHalfSecondReturnsOfficialNoCorrection() throws {
        let profile = try tmax100Profile()
        for metered in [0.001, 0.1, 0.5] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "T-MAX 100 at \(metered) sec must read as no-correction — the no-correction band runs through 0.5 sec inclusive."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, metered, accuracy: 1e-6,
                "Corrected exposure at \(metered) sec must equal metered (identity).")
        }
    }

    func testTMax100At1SecondIsTableDerivedCorrectionNotAnAnchor() throws {
        // The published 1 sec row is +1/3 stop with NO corrected time. The
        // catalog preserves it as source evidence only (stop-delta row),
        // deliberately NOT as a table anchor — but it marks 1 sec as outside
        // the no-correction band. So at exactly 1 sec the evaluator must
        // return a `.tableLogLogDerived` correction (interpolated from the
        // 0.5 sec knee toward the 10 sec anchor), greater than the metered
        // value and NOT the no-correction identity.
        let profile = try tmax100Profile()

        // 1 sec is not a published table anchor.
        let tableRule = try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r } else { return nil }
            }.first
        )
        XCTAssertFalse(
            tableRule.anchors.contains { abs($0.meteredSeconds - 1) < 1e-9 },
            "1 sec must NOT be a table anchor; the +1/3 stop row stays source-evidence only."
        )

        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)
        XCTAssertEqual(
            result.metadata.basis,
            .tableLogLogDerived,
            "metered == 1 sec sits above the 0.5 sec no-correction threshold and must be a table correction."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertGreaterThan(
            corrected,
            1,
            "1 sec must receive a (small) reciprocity correction, not the no-correction identity."
        )
        XCTAssertLessThan(
            corrected,
            15,
            "1 sec interpolates below the 10 sec → 15 sec anchor."
        )
    }

    // MARK: - Table range (> 0.5 sec, up to 100 sec)

    func testTMax100InsideTableRangeIsTableLogLogDerivedThroughPublishedRows() throws {
        let profile = try tmax100Profile()
        for metered in [2.0, 5.0, 10.0, 50.0, 100.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .tableLogLogDerived,
                "Metered \(metered) sec sits inside the source-backed table range."
            )
        }
    }

    func testTMax100TableReproducesPublishedAnchorCorrectedTimesExactly() throws {
        let profile = try tmax100Profile()
        let samples: [(Double, Double)] = [(10, 15), (100, 200)]
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

    // MARK: - Short-exposure guidance is excluded from the long-exposure table

    func testTMax100Short1Over10000ExposureIsNotALongExposureTablePoint() throws {
        // 1/10000 sec sits well below noCorrectionThroughSeconds (0.5 sec).
        // The 1/10000 sec +1/3 stop guidance lives only as a profile-level
        // note; it must NOT produce a table correction.
        let profile = try tmax100Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1.0 / 10_000.0)
        XCTAssertEqual(
            result.metadata.basis,
            .officialThresholdNoCorrection,
            "1/10000 sec sits inside the no-correction band; the table rule must not fire."
        )
        XCTAssertEqual(
            result.correctedExposureSeconds ?? -1,
            1.0 / 10_000.0,
            accuracy: 1e-9,
            "1/10000 sec must return the identity corrected exposure."
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
        // The published 1/10,000 sec +1/3 stop short-exposure guidance
        // is preserved on `profile.notes` for source fidelity. It is not
        // rendered in the Details surface; a future ticket can wire it through.
        let profile = try tmax100Profile()
        let notes = profile.notes.joined(separator: "\n").lowercased()
        XCTAssertTrue(
            notes.contains("1/10,000") || notes.contains("short-exposure"),
            "profile.notes must keep the 1/10000 sec short-exposure +1/3 stop guidance archived; got notes: \(profile.notes)"
        )
    }

    func testTMax100ProfileNotesDocumentNoCorrectionRangeAndShortExposureExclusion() throws {
        // Two catalog-level notes are required:
        // 1. No adjustment from 1/1,000 to 1/10 sec.
        // 2. The 1/10,000 sec short-exposure +1/3 stop is excluded from
        //    the long-exposure table (the note now says "table", not "formula").
        let profile = try tmax100Profile()
        XCTAssertGreaterThanOrEqual(profile.notes.count, 2,
            "T-MAX 100 must carry at least two profile-level notes.")

        let joined = profile.notes.joined(separator: "\n").lowercased()
        XCTAssertTrue(
            joined.contains("table") || joined.contains("interpolation"),
            "At least one note must reference the table, confirming the long-exposure calculation model."
        )
        XCTAssertTrue(
            joined.contains("1/10,000") || joined.contains("short-exposure"),
            "A note must document the 1/10000 sec short-exposure guidance exclusion."
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
                "Metered \(metered) sec must keep a log-log extrapolation value past the source range."
            )
            XCTAssertGreaterThan(corrected, 200,
                "Extrapolated value past 100 sec must exceed the last anchor corrected time of 200 sec.")
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

        // The 1 sec row publishes only a stop delta (+1/3 stop); the
        // catalog MUST NOT synthesize a corrected-time anchor from it.
        let oneSecRow = exactRows.first(where: { $0.0 == 1 })?.1
        XCTAssertNotNil(oneSecRow, "1 sec source-evidence row must be present.")

        let oneSecStopDelta = oneSecRow?.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
            return value.stopDelta
        }.first
        XCTAssertNotNil(oneSecStopDelta,
            "1 sec source-evidence row must carry a stop delta (+1/3 stop).")
        XCTAssertEqual(oneSecStopDelta ?? 0, 1.0 / 3.0, accuracy: 0.01,
            "Stop delta at 1 sec must be approximately +1/3 stop.")

        let oneSecHasCorrectedTime = oneSecRow?.adjustments.contains { adjustment in
            if case .exposure(.correctedTime) = adjustment { return true }
            return false
        } ?? false
        XCTAssertFalse(
            oneSecHasCorrectedTime,
            "Kodak publishes only +1/3 stop at 1 sec; the catalog must not synthesize a corrected-time anchor. The evaluator must not derive a table correction from this row."
        )

        // The 10 sec and 100 sec rows publish both stop delta AND corrected time.
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

    // MARK: - UI surfacing

    @MainActor
    func testTMax100DetailsSurfaceShowsSourceReferenceRows() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "T-MAX 100 must surface a Source reference section for its table-origin profile."
        )
        let block = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(block.contains("1.0s"), "Source reference block must include the 1 sec row; got block:\n\(block)")
        XCTAssertTrue(block.contains("10.0s"))
        XCTAssertTrue(block.contains("100.0s"))
        XCTAssertTrue(block.contains("15"))
        XCTAssertTrue(block.contains("200"))
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "T-MAX 100 must not surface the legacy Reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "T-MAX 100 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testTMax100SummaryTextIsLogLogInterpolationInsideRange() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Log-log interpolation of the official table",
            "Summary inside the source range must describe table log-log interpolation."
        )
    }

    @MainActor
    func testTMax100SummaryTextIsBeyondSourceRangeAbove100Seconds() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 300)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Beyond source range",
            "Summary above 100 sec must read 'Beyond source range'."
        )
    }

    @MainActor
    func testTMax100GraphCarriesSourceReferenceMarkersForPublishedRows() throws {
        // Assert markers for the two table-anchor rows (10→15 and 100→200).
        // The 1 sec row has a stop delta only; do not over-assert its
        // plotted corrected value — only verify the 10 and 100 sec markers.
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula,
            "Table models render as .formula graph kind (matching Fomapan 100 Classic behavior).")

        let markerByMetered = Dictionary(
            uniqueKeysWithValues: graph.sourceReferenceMarkers.map { ($0.point.meteredExposureSeconds.rounded(), $0.point.correctedExposureSeconds) }
        )

        XCTAssertNotNil(markerByMetered[10],
            "T-MAX 100 graph must include a marker at 10 sec (published anchor).")
        XCTAssertEqual(markerByMetered[10] ?? 0, 15, accuracy: 0.01,
            "Marker at 10 sec must plot the published 15 sec corrected exposure.")

        XCTAssertNotNil(markerByMetered[100],
            "T-MAX 100 graph must include a marker at 100 sec (published anchor).")
        XCTAssertEqual(markerByMetered[100] ?? 0, 200, accuracy: 0.01,
            "Marker at 100 sec must plot the published 200 sec corrected exposure.")

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

    /// Past 100 sec the graph note must surface "source range"
    /// wording so the user reads the value as outside Kodak's
    /// supported range.
    @MainActor
    func testTMax100Above100SecondsGraphExplanationSurfacesSourceRangeWording() throws {
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
            film: "T-MAX 100",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func tmax100Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "T-MAX 100")
    }
}
