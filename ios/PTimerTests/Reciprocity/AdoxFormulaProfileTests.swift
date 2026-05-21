import XCTest
@testable import PTimer

/// Behavior contract for ADOX CMS 20 II's formula profile (PTIMER-139).
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
///    Tc = 1.4142 × Tm^1.150515. The formula's domain runs from 1 s
///    (inclusive — the threshold rule wins at exactly 1 s) up to
///    100 s (exclusive).
/// 3. 100 s is published as "Not recommended"; the formula rule sets
///    `extrapolateBeyondMaximum = false` so inputs at or above 100 s
///    return an unsupported result with no corrected exposure. The
///    100 s row is preserved as a Guidance boundary entry.
final class AdoxFormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold band (1/1000 s … 1 s, inclusive at both edges)
    //
    // The 1/1000 s point lives in source evidence as +1/2 stop but the
    // calculation path still returns the no-correction identity for
    // it (see `testCms20IIAtOneOverThousandSecStaysNoCorrection...`
    // below). The 1 s upper boundary is inclusive — 1.0 s itself
    // still reads as no-correction.

    func testCms20IIAtOneSecondBoundaryReturnsOfficialNoCorrection() throws {
        let profile = try cms20Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1.0)
        XCTAssertEqual(
            result.metadata.basis,
            .officialThresholdNoCorrection,
            "CMS 20 II's 1 s upper boundary is inclusive — 1.0 s itself must read as no-correction."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 1.0, accuracy: 1e-6)
    }

    /// Regression: 0.001 s lives in source evidence as +1/2 stop, but
    /// that row is preserved as published reference only. The active
    /// calculation path at 0.001 s must remain on the no-correction
    /// identity line, not collapse to the +1/2 stop derivation.
    func testCms20IIAtOneOverThousandSecStaysNoCorrectionDespiteSourceEvidenceRow() throws {
        let profile = try cms20Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.001)
        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 0.001, accuracy: 1e-9)
    }

    // MARK: - Formula range (1 s … 100 s, exclusive at the upper bound)

    func testCms20IIFormulaAnchorAtOneSecondMatchesPublishedHalfStop() throws {
        let profile = try cms20Profile()
        // Evaluated at 1.0 the threshold rule wins (returns identity).
        // Evaluate just above 1 s to land in the formula domain and
        // verify the formula's value at the anchor matches the
        // published +1/2 stop derivation.
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1.0001)
        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 1.4142136, accuracy: 0.002)
    }

    func testCms20IIFormulaAnchorAtTenSecondsMatchesPublishedFullStop() throws {
        let profile = try cms20Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 10)
        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 20, accuracy: 0.05)
    }

    func testCms20IIBetweenAnchorsReturnsFormulaInterpolatedValue() throws {
        // 1.7 s and 6.8 s sit between the 1 s and 10 s anchors. The
        // log-log formula should produce a corrected exposure between
        // 1.414 s (at 1 s) and 20 s (at 10 s).
        let profile = try cms20Profile()
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

    func testCms20IIBeyondTenSecondsButBelowOneHundredStillReturnsFormulaValue() throws {
        // 14 s, 27 s, and 54 s sit past the last published anchor
        // (10 s) but inside the calculation-allowed continuation
        // (1 s … 100 s). The formula must continue to produce a
        // numeric corrected exposure on the same curve.
        let profile = try cms20Profile()
        for (metered, expected) in [
            (14.0, 29.4),
            (27.0, 62.7),
            (54.0, 139.3),
        ] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "CMS 20 II at \(metered) s is past the last published anchor but inside the policy's formula range."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                expected,
                accuracy: 0.5,
                "CMS 20 II at \(metered) s must keep producing the formula-derived corrected exposure."
            )
        }
    }

    // MARK: - Unsupported boundary (≥ 100 s)

    func testCms20IIAtOneHundredSecondsIsUnsupportedAndCarriesNoCorrectedExposure() throws {
        let profile = try cms20Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 100)
        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertNil(
            result.correctedExposureSeconds,
            "100 s is published as 'Not recommended'; CMS 20 II must not surface a corrected exposure at the stop signal."
        )
    }

    func testCms20IIBeyondOneHundredSecondsRemainsUnsupportedWithNoCorrectedExposure() throws {
        let profile = try cms20Profile()
        for metered in [120.0, 200.0, 500.0, 1_000.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "CMS 20 II at \(metered) s sits past the 100 s stop signal and must be unsupported."
            )
            XCTAssertNil(
                result.correctedExposureSeconds,
                "CMS 20 II must never extrapolate past 100 s; \(metered) s must return no corrected exposure."
            )
        }
    }

    // MARK: - Formula shape

    func testCms20IIFormulaRuleUsesLogLogCoefficientAndExponent() throws {
        let profile = try cms20Profile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule.formula.exponent, 1.150515, accuracy: 1e-3)
        let coefficient = try XCTUnwrap(formulaRule.formula.coefficient)
        XCTAssertEqual(coefficient, 1.4142136, accuracy: 1e-3)

        let equation = try XCTUnwrap(formulaRule.formula.equation)
        XCTAssertTrue(
            equation.contains("Tm^P"),
            "Equation must use the Tm^P placeholder; got: \(equation)"
        )

        let range = try XCTUnwrap(formulaRule.meteredRange)
        XCTAssertEqual(range.minimumSeconds, 1, accuracy: 1e-6)
        XCTAssertEqual(range.maximumSeconds ?? 0, 100, accuracy: 1e-6)
        XCTAssertFalse(
            formulaRule.extrapolateBeyondMaximum,
            "CMS 20 II must opt out of formula extrapolation past the 100 s stop signal."
        )
    }

    func testCms20IIThresholdRuleCoversFullSubOneSecondBand() throws {
        let profile = try cms20Profile()
        let threshold = try XCTUnwrap(profile.rules.compactMap { rule -> ThresholdReciprocityRule? in
            guard case let .threshold(rule) = rule else { return nil }
            return rule
        }.first)
        XCTAssertEqual(threshold.noCorrectionRange.minimumSeconds, 0.001, accuracy: 1e-9)
        XCTAssertEqual(threshold.noCorrectionRange.maximumSeconds ?? 0, 1, accuracy: 1e-9)
    }

    // MARK: - Source evidence preservation

    func testCms20IISourceEvidencePreservesAllFourPublishedRows() throws {
        let profile = try cms20Profile()
        let metereds = profile.sourceEvidence.compactMap { row -> Double? in
            if case let .exactSeconds(seconds) = row.meteredExposure { return seconds }
            return nil
        }
        XCTAssertEqual(
            metereds,
            [0.001, 1, 10, 100],
            "CMS 20 II must preserve all four published rows (1/1000 s, 1 s, 10 s, 100 s)."
        )
    }

    func testCms20IIOneOverThousandSecEvidenceRowIsMarkedSourceEvidenceOnly() throws {
        let profile = try cms20Profile()
        let row = try XCTUnwrap(profile.sourceEvidence.first { row in
            if case let .exactSeconds(seconds) = row.meteredExposure {
                return abs(seconds - 0.001) < 1e-9
            }
            return false
        })
        XCTAssertTrue(
            row.isSourceEvidenceOnly,
            "1/1000 s row must be flagged source-evidence-only so the renderer can mark it and skip it as a formula fitting point."
        )

        let stopDelta = row.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
            return value.stopDelta
        }.first
        XCTAssertEqual(stopDelta ?? 0, 0.5, accuracy: 1e-6)
    }

    func testCms20IIOneHundredSecondRowIsPreservedAsNotRecommendedBoundary() throws {
        let profile = try cms20Profile()
        let row = try XCTUnwrap(profile.sourceEvidence.first { row in
            if case let .exactSeconds(seconds) = row.meteredExposure {
                return abs(seconds - 100) < 1e-6
            }
            return false
        })
        let severity = row.adjustments.compactMap { adjustment -> ReciprocityWarningSeverity? in
            guard case let .warning(warning) = adjustment else { return nil }
            return warning.severity
        }.first
        XCTAssertEqual(severity, .notRecommended)
    }

    // MARK: - Graph display state

    @MainActor
    func testCms20IIGraphIsFormulaKindAndCarriesNoCorrectionBandUpToOneSecond() throws {
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
    func testCms20IIGraphSourceReferenceMarkersIncludeOneSecondAndTenSecondsOnly() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)
        let graph = try XCTUnwrap(displayState.graph)
        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds }.sorted()
        XCTAssertEqual(markerMetereds.count, 2)
        XCTAssertEqual(markerMetereds[0], 1, accuracy: 1e-6, "1 s anchor must surface as a source-reference marker.")
        XCTAssertEqual(markerMetereds[1], 10, accuracy: 1e-6, "10 s anchor must surface as a source-reference marker.")
    }

    @MainActor
    func testCms20IIGraphExcludesOneOverThousandSecMarkerEvenThoughEvidenceIsPreserved() throws {
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
    func testCms20IIGraphExposesOneHundredSecondNotRecommendedBoundaryAcrossInputs() throws {
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

    @MainActor
    func testCms20IIGraphBeyondSourceRangeStartsAtOneHundredSecondsNotAtTenSeconds() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(
            graph.beyondSourceRangeStartSeconds ?? 0,
            100,
            accuracy: 1e-6,
            "The unsupported region must start at the 100 s stop signal, never at the 10 s anchor."
        )
    }

    @MainActor
    func testCms20IIGraphSupportedRangeUpperBoundIsOneHundredSeconds() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 5)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(
            graph.supportedRangeUpperBoundSeconds ?? 0,
            100,
            accuracy: 1e-6,
            "Formula's upper bound (the policy stop signal) is 100 s."
        )
    }

    @MainActor
    func testCms20IIViewportAndAxisAreStableAcrossInputs() throws {
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
    func testCms20IICurrentMarkerInsideNoCorrectionBandSitsOnIdentity() throws {
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

    @MainActor
    func testCms20IICurrentMarkerInFormulaRangePlotsAtFormulaValue() throws {
        for (metered, expected) in [(1.7, 2.604), (6.8, 12.83), (14.0, 29.4)] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            let currentPoint = try XCTUnwrap(graph.currentPoint)
            XCTAssertEqual(currentPoint.style, .formulaDerived)
            XCTAssertEqual(currentPoint.point.meteredExposureSeconds, metered, accuracy: 1e-6)
            XCTAssertEqual(
                currentPoint.point.correctedExposureSeconds,
                expected,
                accuracy: 0.5,
                "Current marker at \(metered) s must plot at the formula-derived corrected exposure."
            )
        }
    }

    @MainActor
    func testCms20IIBeyondOneHundredSecondsHasNoCurrentPointAndUsesCurrentInputGuideOnly() throws {
        for metered in [100.0, 200.0, 500.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertNil(
                graph.currentPoint,
                "CMS 20 II at \(metered) s must not plot a current-result marker — no corrected exposure exists."
            )
            XCTAssertTrue(
                graph.usesCurrentInputGuideOnly,
                "CMS 20 II at \(metered) s must fall back to the current-input guide so the user still sees where the input lands on the x-axis."
            )
        }
    }

    // MARK: - Reference data rendering

    @MainActor
    func testCms20IIDetailsSplitsSourceReferenceAndGuidanceBoundarySections() throws {
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
    func testCms20IISourceReferenceRowsAreSortedByMeteredExposureAscending() throws {
        // The Source reference block must read bottom-up as a
        // shutter sweep: the published 1/1000 s point (evidence-only)
        // appears first, then the 1/1000 s … 1 s no-correction band
        // that wraps it, then 1 s, then 10 s. The 100 s row lives in
        // the Guidance boundary section and must not appear here.
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
            dataLines[0].contains("*"),
            "First row must be the 1/1000 s evidence-only entry (carries the * marker); got: \(dataLines[0])"
        )
        XCTAssertTrue(
            dataLines[1].contains("No correction"),
            "Second row must be the 1/1000 s … 1 s no-correction band; got: \(dataLines[1])"
        )
        XCTAssertFalse(
            dataLines[1].contains("*"),
            "The no-correction band row must not carry the * marker; got: \(dataLines[1])"
        )

        let firstColumn: (String) -> String = { line in
            line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        }
        XCTAssertTrue(firstColumn(dataLines[2]).hasPrefix("1"), "Third row must start with the 1 s anchor; got: \(dataLines[2])")
        XCTAssertTrue(firstColumn(dataLines[3]).hasPrefix("10"), "Fourth row must start with the 10 s anchor; got: \(dataLines[3])")
    }

    /// CMS 20 II is the *stop signal* profile: past the 100 s
    /// boundary the corrected exposure is nil (no formula
    /// extrapolation), and the detail / graph explanation carry the
    /// "no quantified corrected point" wording rather than the
    /// numeric continuation copy other converted profiles use.
    @MainActor
    func testCms20IIBeyondOneHundredSecondsUsesBeyondSourceRangeWordingWithNoValue() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 200)
        XCTAssertEqual(displayState.summary.summaryText, "Beyond source range")
        let detail = try XCTUnwrap(displayState.summary.detailText)
        XCTAssertTrue(
            detail.lowercased().contains("no quantified corrected point is available"),
            "Detail text at >=100 s must call out the missing corrected value; got: \(detail)"
        )

        let graph = try XCTUnwrap(displayState.graph)
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertTrue(
            explanation.lowercased().contains("no quantified corrected point is available"),
            "Graph explanation at >=100 s must also call out the missing corrected value; got: \(explanation)"
        )
    }

    // MARK: - Helpers

    private func cms20Profile() throws -> ReciprocityProfile {
        let film = try cms20Film()
        return try XCTUnwrap(film.profiles.first)
    }

    private func cms20Film() throws -> FilmIdentity {
        try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "CMS 20 II" },
            "CMS 20 II must remain in the launch catalog."
        )
    }

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        let film = try cms20Film()
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
