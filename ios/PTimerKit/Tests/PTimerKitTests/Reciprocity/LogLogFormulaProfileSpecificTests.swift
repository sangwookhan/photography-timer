import XCTest
import PTimerKit
import PTimerCore

/// Behavior contract for ADOX CMS 20 II's formula profile (PTIMER-139,
/// updated by PTIMER-160).
///
/// The manufacturer publishes:
///
/// ```
/// 1/1000 s – 1 s    No correction
/// 1/1000 s          +1/2 stop
/// 1 s               +1/2 stop
/// 10 s              +1 stop
/// 100 s             Not recommended
/// ```
///
/// The profile reflects this guidance with three deliberate policy
/// decisions:
///
/// 1. The full 1/1000 s … 1 s band is treated as no-correction on the
///    calculation path. The 1/1000 s +1/2 stop entry is preserved as
///    source evidence only — it does not fit the formula or move the
///    calculated corrected exposure off the identity line.
/// 2. 1 s (+1/2 stop) and 10 s (+1 stop) anchor a log-log formula
///    Tc = 1.4142 × Tm^1.150515. The 1 s open boundary
///    (`noCorrectionThroughSeconds = 0.999999`) leaves the formula
///    to fire at exactly 1 s; the source-backed range ends at the
///    10 s anchor (`sourceRangeThroughSeconds = 10`).
/// 3. PTIMER-160 made `sourceRangeThroughSeconds` a confidence
///    boundary, not a calculation stop. The formula keeps producing
///    numeric values above 10 s; presentation classifies those as
///    beyond source range. The 100 s "Not recommended" row is
///    preserved as a published warning marker through the Guidance
///    boundary section — it is NOT a corrected-time anchor and never
///    promotes its neighborhood back into source-backed status.
/// ADOX CMS 20 II is a converted guarded-formula film. Its
/// archetype-shared contracts — inclusive-threshold no-correction, fit
/// parameters, and source-evidence preservation — are verified across
/// films in `GuardedFormula{RegionBasis,Fit,SourceEvidence}ContractTests`.
/// This suite holds only CMS 20 II's genuinely film-specific behavior
/// (the 1/1000 s … 1 s sub-second no-correction band, the 1 s / 10 s
/// formula anchors, the 100 s not-recommended marker, and the graph /
/// viewport detail). The film is the `profileUnderTest()` constant, so no
/// film name appears in a test-function name.
final class LogLogFormulaProfileSpecificTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold band (1/1000 s … 1 s, inclusive at both edges)
    //
    // The 1/1000 s point lives in source evidence as +1/2 stop but the
    // calculation path still returns the no-correction identity for
    // it (see `testAtOneOverThousandSecStaysNoCorrection...` below).
    // The 1 s upper boundary is inclusive — 1.0 s itself still reads as
    // no-correction (the inclusive-threshold contract is shared and
    // verified in `GuardedFormulaRegionBasisContractTests`).

    /// Regression: 0.001 s lives in source evidence as +1/2 stop, but
    /// that row is preserved as published reference only. The active
    /// calculation path at 0.001 s must remain on the no-correction
    /// identity line, not collapse to the +1/2 stop derivation.
    func testAtOneOverThousandSecStaysNoCorrectionDespiteSourceEvidenceRow() throws {
        let profile = try profileUnderTest()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.001)
        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 0.001, accuracy: 1e-9)
    }

    // MARK: - Source-backed formula range (1 s … 10 s)
    //
    // The 10 s anchor is the last quantified source-backed metered
    // time per PTIMER-160. Inputs strictly above 10 s still compute
    // a formula-derived value but are classified outside source
    // range (see the "Beyond the source-backed range" tests).

    func testFormulaAnchorAtOneSecondMatchesPublishedHalfStop() throws {
        let profile = try profileUnderTest()
        // Evaluated at 1.0 the threshold rule wins (returns identity).
        // Evaluate just above 1 s to land in the formula domain and
        // verify the formula's value at the anchor matches the
        // published +1/2 stop derivation.
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1.0001)
        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 1.4142136, accuracy: 0.002)
    }

    func testFormulaAnchorAtTenSecondsMatchesPublishedFullStop() throws {
        let profile = try profileUnderTest()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 10)
        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 20, accuracy: 0.05)
    }

    func testBetweenAnchorsReturnsFormulaDerivedValue() throws {
        // 1.7 s and 6.8 s sit between the 1 s and 10 s source-evidence
        // anchors. The closed-form formula should produce a corrected
        // exposure between 1.414 s (at 1 s) and 20 s (at 10 s).
        let profile = try profileUnderTest()
        for (metered, expected) in [
            (1.7, 2.604),
            (6.8, 12.83),
        ] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "CMS 20 II at \(metered) s sits between the 1 s and 10 s anchors and must be formula-derived."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                expected,
                accuracy: 0.1,
                "Formula prediction at \(metered) s must match the published log-log fit."
            )
        }
    }

    // MARK: - Beyond the source-backed range (> 10 s, with 100 s as
    // a warning marker)
    //
    // PTIMER-160 policy: `sourceRangeThroughSeconds` is the last
    // quantified source-backed metered time — for CMS 20 II that is
    // the 10 s anchor. Inputs above 10 s still compute a formula-
    // derived continuation but are classified outside source range.
    // The 100 s row is preserved as a "Not recommended" warning
    // marker only; it is NOT a corrected-time anchor and never
    // promotes its neighborhood back into source-backed status.

    func testBeyondTenSecondsCarriesFormulaPredictionAsBeyondSource() throws {
        // 14 s, 27 s, 54 s, and 100 s all sit above the source-
        // backed 10 s anchor. The formula continues to produce
        // numeric values, but presentation must surface them as
        // beyond source range (formula-derived continuation, not
        // manufacturer guidance).
        let profile = try profileUnderTest()
        for (metered, expected) in [
            (14.0, 29.4),
            (27.0, 62.7),
            (54.0, 139.3),
            (100.0, 1.4142136 * pow(100.0, 1.150515)),
        ] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "CMS 20 II at \(metered) s sits above the 10 s source-backed boundary; presentation must classify it as outside source range."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                expected,
                accuracy: max(0.5, expected * 0.005),
                "CMS 20 II at \(metered) s must keep producing the formula-derived continuation value."
            )
        }
    }

    func testAbove100SecondsRemainsBeyondSourceWithFormulaPrediction() throws {
        let profile = try profileUnderTest()
        for metered in [120.0, 200.0, 500.0, 1_000.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "CMS 20 II at \(metered) s sits past the 100 s 'Not recommended' marker; the classification stays beyond source range."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            let expected = 1.4142136 * pow(metered, 1.150515)
            XCTAssertEqual(corrected, expected, accuracy: expected * 0.005)
        }
    }

    // MARK: - Formula shape

    // MARK: - Source evidence preservation

    // MARK: - Graph display state

    @MainActor
    func testGraphIsFormulaKindAndCarriesNoCorrectionBandUpToOneSecond() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 0.5)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula)
        XCTAssertEqual(
            graph.noCorrectionRangeUpperBoundSeconds ?? 0,
            1,
            accuracy: 1e-9,
            "Green no-correction band must run up to 1 s, matching the threshold rule."
        )
    }

    @MainActor
    func testGraphSourceReferenceMarkersIncludeOneSecondAndTenSecondsOnly() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)
        let graph = try XCTUnwrap(displayState.graph)
        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds }.sorted()
        XCTAssertEqual(markerMetereds.count, 2)
        XCTAssertEqual(markerMetereds[0], 1, accuracy: 1e-6, "1 s anchor must surface as a source-reference marker.")
        XCTAssertEqual(markerMetereds[1], 10, accuracy: 1e-6, "10 s anchor must surface as a source-reference marker.")
    }

    @MainActor
    func testGraphExcludesOneOverThousandSecMarkerEvenThoughEvidenceIsPreserved() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)
        let graph = try XCTUnwrap(displayState.graph)
        for marker in graph.sourceReferenceMarkers {
            XCTAssertGreaterThan(
                marker.point.meteredExposureSeconds,
                0.1,
                "1/1000 s evidence row must never appear as a graph fitting marker; it lives in the reference table only."
            )
        }
    }

    @MainActor
    func testGraphExposesOneHundredSecondNotRecommendedBoundaryAcrossInputs() throws {
        for metered in [0.5, 5.0, 50.0, 200.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.notRecommendedBoundarySeconds ?? 0,
                100,
                accuracy: 1e-6,
                "Metered \(metered) s: graph must always expose the 100 s not-recommended boundary."
            )
        }
    }

    /// PTIMER-160: the beyond-source-range region starts at the
    /// formula's `sourceRangeThroughSeconds`, which for CMS 20 II is
    /// the 10 s source-backed anchor. The 100 s row is preserved as
    /// a separate "Not recommended" marker (see
    /// `notRecommendedBoundarySeconds`), not as the boundary of the
    /// source-backed range.
    @MainActor
    func testGraphBeyondSourceRangeStartsAtTenSecondsAtSourceBoundary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(
            graph.beyondSourceRangeStartSeconds ?? 0,
            10,
            accuracy: 1e-6,
            "The beyond-source region must start at the 10 s source-backed boundary; 100 s is a separate not-recommended warning marker."
        )
    }

    @MainActor
    func testGraphSupportedRangeUpperBoundIsTenSeconds() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(
            graph.supportedRangeUpperBoundSeconds ?? 0,
            10,
            accuracy: 1e-6,
            "Source-backed range upper bound is the 10 s anchor."
        )
    }

    @MainActor
    func testViewportAndAxisAreStableAcrossInputs() throws {
        let inputs: [Double] = [0.053, 0.423, 1.7, 6.8, 14, 27, 54, 200]
        var seenViewports = Set<String>()
        var seenAxisTicks = Set<String>()
        var seenAnchors = Set<String>()
        for metered in inputs {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            seenViewports.insert("\(graph.xRange.lowerBound)|\(graph.xRange.upperBound)|\(graph.yRange.lowerBound)|\(graph.yRange.upperBound)")
            seenAxisTicks.insert(graph.xAxisTicks.map(\.label).joined(separator: ","))
            let anchorKey = graph.sourceReferenceMarkers
                .map { String(format: "%.6f", $0.point.meteredExposureSeconds) }
                .sorted()
                .joined(separator: "/")
            let boundaryKey = "\(graph.notRecommendedBoundarySeconds ?? -1)|\(graph.beyondSourceRangeStartSeconds ?? -1)"
            seenAnchors.insert("\(anchorKey)|\(boundaryKey)")
        }
        XCTAssertEqual(seenViewports.count, 1, "Viewport must be input-independent for CMS 20 II; got viewports \(seenViewports).")
        XCTAssertEqual(seenAxisTicks.count, 1, "Axis ticks must be input-independent for CMS 20 II.")
        XCTAssertEqual(seenAnchors.count, 1, "Reference anchors and the unsupported boundary must be input-independent for CMS 20 II.")
    }

    @MainActor
    func testCurrentMarkerInsideNoCorrectionBandSitsOnIdentity() throws {
        for metered in [0.053, 0.423, 1.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            let currentPoint = try XCTUnwrap(graph.currentPoint)
            XCTAssertEqual(currentPoint.style, .noCorrection)
            XCTAssertEqual(currentPoint.point.meteredExposureSeconds, metered, accuracy: 1e-9)
            XCTAssertEqual(
                currentPoint.point.correctedExposureSeconds,
                metered,
                accuracy: 1e-9,
                "Sub-1 s current marker must sit on the identity line."
            )
        }
    }

    /// Current marker inside the source-backed range (1 s … 10 s)
    /// plots with the `.formulaDerived` style — the formula matches
    /// ADOX's published anchors there.
    @MainActor
    func testCurrentMarkerInSourceBackedRangePlotsAtFormulaValue() throws {
        for (metered, expected) in [(1.7, 2.604), (6.8, 12.83)] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            let currentPoint = try XCTUnwrap(graph.currentPoint)
            XCTAssertEqual(currentPoint.style, .formulaDerived)
            XCTAssertEqual(currentPoint.point.meteredExposureSeconds, metered, accuracy: 1e-6)
            XCTAssertEqual(
                currentPoint.point.correctedExposureSeconds,
                expected,
                accuracy: 0.5,
                "Current marker at \(metered) s must plot at the source-backed formula-derived corrected exposure."
            )
        }
    }

    /// PTIMER-160: past the 10 s source-backed anchor CMS 20 II
    /// surfaces a formula-prediction marker plotted in the
    /// beyond-source style — the formula keeps producing values
    /// (14 s, 27 s, 54 s, …) but presentation must classify them as
    /// formula-derived continuation, not as source-backed prediction.
    @MainActor
    func testAboveTenSecondsPlotsBeyondSourceMarker() throws {
        for metered in [14.0, 27.0, 54.0, 120.0, 200.0, 500.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            let currentPoint = try XCTUnwrap(
                graph.currentPoint,
                "CMS 20 II at \(metered) s must plot a current-result marker in the beyond-source style (PTIMER-160)."
            )
            XCTAssertEqual(currentPoint.style, .beyondSourceRange)
            XCTAssertFalse(graph.usesCurrentInputGuideOnly)
        }
    }

    // MARK: - Reference data rendering

    @MainActor
    func testDetailsSplitsSourceReferenceAndGuidanceBoundarySections() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "CMS 20 II must surface a Source reference section."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(
            sourceBlock.contains("No correction range"),
            "Source reference block must surface the 1/1000 s … 1 s no-correction band."
        )
        XCTAssertTrue(
            sourceBlock.contains("*"),
            "Source reference block must mark the 1/1000 s evidence-only row with an asterisk."
        )
        XCTAssertTrue(
            sourceBlock.contains("Source evidence only"),
            "Source reference block must carry the footnote explaining the asterisk: got block \(sourceBlock)."
        )
        XCTAssertFalse(
            sourceBlock.contains("Not recommended"),
            "Source reference section must not carry the 100 s not-recommended boundary."
        )

        let boundarySection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Guidance boundary" }),
            "CMS 20 II must surface a Guidance boundary section for the 100 s row."
        )
        let boundaryBlock = try XCTUnwrap(boundarySection.rows.first?.value)
        XCTAssertTrue(
            boundaryBlock.contains("Not recommended"),
            "Guidance boundary block must carry the 100 s not-recommended row."
        )
    }

    @MainActor
    func testSourceReferenceRowsAreSortedByMeteredExposureAscending() throws {
        // PTIMER-160 retired CMS 20 II's companion threshold rule; the
        // no-correction band is now contributed by the formula itself
        // and sorts at sortValue 0 (the band's effective start), so it
        // leads the block. The published anchors and the 1/1000 s
        // evidence-only point follow in ascending order.
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)
        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" })
        )
        let block = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        let dataLines = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }

        XCTAssertGreaterThanOrEqual(dataLines.count, 4, "Expected at least four reference rows; got \(dataLines).")

        XCTAssertTrue(
            dataLines[0].contains("No correction"),
            "First row must be the sub-1 s no-correction band; got: \(dataLines[0])"
        )
        XCTAssertFalse(
            dataLines[0].contains("*"),
            "The no-correction band row must not carry the * marker; got: \(dataLines[0])"
        )
        XCTAssertTrue(
            dataLines[1].contains("*"),
            "Second row must be the 1/1000 s evidence-only entry (carries the * marker); got: \(dataLines[1])"
        )

        let firstColumn: (String) -> String = { line in
            line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        }
        XCTAssertTrue(firstColumn(dataLines[2]).hasPrefix("1"), "Third row must start with the 1 s anchor; got: \(dataLines[2])")
        XCTAssertTrue(firstColumn(dataLines[3]).hasPrefix("10"), "Fourth row must start with the 10 s anchor; got: \(dataLines[3])")
    }

    /// PTIMER-160: past the 100 s "Not recommended" warning marker
    /// (still beyond the 10 s source-backed boundary), CMS 20 II
    /// surfaces a formula prediction outside the source range. The
    /// detail / graph explanation switch to the "outside source
    /// range" wording with the numeric continuation copy other
    /// converted profiles use.
    @MainActor
    func testBeyondOneHundredSecondsUsesBeyondSourceRangeWordingWithValue() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 200)
        XCTAssertEqual(displayState.summary.summaryText, "Beyond source range")

        let graph = try XCTUnwrap(displayState.graph)
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertTrue(
            explanation.lowercased().contains("source range"),
            "Graph explanation at >=100 s must carry source-range wording; got: \(explanation)"
        )
    }

    // MARK: - Helpers

    private func profileUnderTest() throws -> ReciprocityProfile {
        let film = try filmUnderTest()
        return try XCTUnwrap(film.profiles.first)
    }

    private func filmUnderTest() throws -> FilmIdentity {
        try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "CMS 20 II" },
            "CMS 20 II must remain in the launch catalog."
        )
    }

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        let film = try filmUnderTest()
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> = .success(
            ExposureCalculationResult(
                baseShutterSeconds: meteredExposureSeconds,
                stop: 0,
                resultShutterSeconds: meteredExposureSeconds
            )
        )
        return try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: calculationResult,
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )
    }
}
