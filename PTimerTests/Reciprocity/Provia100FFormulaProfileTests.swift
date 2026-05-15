import XCTest
@testable import PTimer

/// Provia 100F is calculated by a constrained, threshold-anchored
/// formula rather than an exact-match table row. These tests lock
/// the invariants:
///
/// - Below the 128 s no-correction threshold, the threshold rule wins.
/// - In (128, 480) the formula wins (basis == `.formulaDerived`).
/// - 240 s — the manufacturer's published +1/3-stop reference point —
///   produces a formula-derived corrected exposure of ≈302 s. It must
///   not report `.exactTablePoint`.
/// - At and beyond 480 s — the manufacturer's "not recommended"
///   boundary — the basis is `.unsupportedOutOfPolicyRange` and the
///   result still carries the formula-extrapolated numeric corrected
///   exposure (visibly marked outside manufacturer guidance). 480 s
///   is never used as a formula fitting point.
/// - The 240 s (+1/3 stop, 2.5G) row and the 480 s not-recommended row
///   stay visible as source evidence so users can verify the formula
///   prediction against the manufacturer's published reference points.
final class Provia100FFormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold range (≤ 128 s)

    func testProvia100FBelowThresholdReturnsOfficialNoCorrection() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 64)

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 64, accuracy: 1e-6)
    }

    func testProvia100FAtThresholdBoundaryReturnsOfficialNoCorrection() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 128)

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 128, accuracy: 1e-6)
    }

    // MARK: - Formula range (128 s … 480 s exclusive)

    func testProvia100FAt240SecondsIsFormulaDerivedNotExactTablePoint() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 240)

        XCTAssertEqual(
            result.metadata.basis,
            .formulaDerived,
            "240 s must be formula-derived, not exactTablePoint, even though the manufacturer published a +1/3 stop reference here."
        )

        // Anchored to the published +1/3 stop reference (240 × 2^(1/3) ≈ 302.4 s).
        // The constrained-formula coefficient is rounded to six decimals, so a 2 s
        // tolerance comfortably covers the rounding error.
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 302.4, accuracy: 2.0)
    }

    func testProvia100FBetweenThresholdAndStopSignalIsFormulaDerived() throws {
        let profile = try proviaProfile()

        for metered in [150.0, 200.0, 360.0, 470.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) s in the formula range must be formula-derived."
            )
        }
    }

    func testProvia100FFormulaExponentMatchesPublishedReference() throws {
        let profile = try proviaProfile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule.formula.exponent, 1.3676, accuracy: 0.0001)

        let coefficient = try XCTUnwrap(formulaRule.formula.coefficient)
        // coefficient = 128^(1 - 1.3676) = 128^(-0.3676) ≈ 0.16803
        XCTAssertEqual(coefficient, pow(128.0, 1 - 1.3676), accuracy: 0.0005)

        let equation = try XCTUnwrap(formulaRule.formula.equation)
        XCTAssertTrue(
            equation.contains("128"),
            "Equation text must communicate the 128 s anchor; got: \(equation)"
        )
    }

    // MARK: - Unsupported boundary (≥ 480 s) with formula extrapolation

    func testProvia100FAt480SecondsIsUnsupportedWithFormulaExtrapolation() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 480)

        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)

        // The boundary itself sits outside manufacturer guidance, but
        // the formula can still produce a value the user can act on.
        // Tc = 128 × (480 / 128)^1.3676 = 128 × 3.75^1.3676 ≈ 781 s.
        let corrected = try XCTUnwrap(
            result.correctedExposureSeconds,
            "480 s must carry a formula-extrapolated corrected exposure, not nil."
        )
        let expected = 128.0 * pow(480.0 / 128.0, 1.3676)
        XCTAssertEqual(corrected, expected, accuracy: 1.5)
    }

    func testProvia100FBeyond480SecondsExtrapolatesFromFormulaAndStaysUnsupported() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 500)

        XCTAssertEqual(
            result.metadata.basis,
            .unsupportedOutOfPolicyRange,
            "Beyond the 480 s boundary the result remains classified as outside manufacturer guidance."
        )

        let corrected = try XCTUnwrap(
            result.correctedExposureSeconds,
            "Formula must keep producing a numeric extrapolation past the manufacturer boundary."
        )
        let expected = 128.0 * pow(500.0 / 128.0, 1.3676)
        XCTAssertEqual(corrected, expected, accuracy: 1.5)
    }

    func testProvia100FUnsupportedNumericResultExposesCalculatedTime() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 600)

        XCTAssertTrue(
            result.hasCalculatedExposureTime,
            "Unsupported-with-numeric must report hasCalculatedExposureTime so the play button enables."
        )

        let presentation = result.confidencePresentation
        XCTAssertEqual(presentation.category, .unsupported)
        XCTAssertTrue(
            presentation.returnsCalculatedExposureTime,
            "Confidence presentation must surface the numeric value to the play button."
        )
        XCTAssertEqual(
            presentation.badgeStyle,
            .unsupported,
            "Visual treatment stays in the unsupported badge style so the user reads the value as outside guidance."
        )
    }

    // MARK: - Source evidence preservation

    func testProvia100FSourceEvidencePreserves240SecondReferenceAnd2dot5GFilter() throws {
        let profile = try proviaProfile()

        let evidence240 = try XCTUnwrap(
            profile.sourceEvidence.first {
                if case let .exactSeconds(seconds) = $0.meteredExposure {
                    return abs(seconds - 240) < 1e-6
                }
                return false
            },
            "Provia 100F must keep the 240 s manufacturer reference as source evidence."
        )

        let stopDelta = evidence240.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
            return value.stopDelta
        }.first
        XCTAssertEqual(stopDelta ?? 0, 1.0 / 3.0, accuracy: 1e-4, "240 s source evidence must record the published +1/3 stop correction.")

        let colorFilter = evidence240.adjustments.compactMap { adjustment -> String? in
            guard case let .colorFilter(recommendation) = adjustment else { return nil }
            return recommendation.filterName
        }.first
        XCTAssertEqual(colorFilter, "2.5G", "240 s source evidence must keep the 2.5G color guidance.")
    }

    func testProvia100FSourceEvidencePreserves480SecondNotRecommendedBoundary() throws {
        let profile = try proviaProfile()

        let evidence480 = try XCTUnwrap(
            profile.sourceEvidence.first {
                if case let .exactSeconds(seconds) = $0.meteredExposure {
                    return abs(seconds - 480) < 1e-6
                }
                return false
            },
            "Provia 100F must keep the 480 s not-recommended boundary as source evidence."
        )

        let warningSeverity = evidence480.adjustments.compactMap { adjustment -> ReciprocityWarningSeverity? in
            guard case let .warning(warning) = adjustment else { return nil }
            return warning.severity
        }.first
        XCTAssertEqual(warningSeverity, .notRecommended)
    }

    func testProvia100FCalculationRulesDoNotContain240SecondTableEntry() throws {
        let profile = try proviaProfile()

        for rule in profile.rules {
            guard case let .table(tableRule) = rule else { continue }
            for entry in tableRule.entries {
                if case let .exactSeconds(seconds) = entry.meteredExposure {
                    XCTAssertNotEqual(
                        seconds,
                        240,
                        accuracy: 1e-6,
                        "240 s must not exist as a calculation table row — it is source evidence only, otherwise the basis would regress to exactTablePoint."
                    )
                }
            }
        }
    }

    // MARK: - UI surfacing

    @MainActor
    func testProvia100FDetailsSplitsSourceReferenceAndGuidanceBoundarySections() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Provia 100F must surface a Source reference section for the 128 s no-correction band and the 240 s reference row."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(
            sourceBlock.contains("2.5G"),
            "Source reference block must surface the 2.5G manufacturer color guidance."
        )
        XCTAssertTrue(
            sourceBlock.contains("No correction range"),
            "Source reference block must label the 128 s threshold band as a No correction range, per the design."
        )
        XCTAssertFalse(
            sourceBlock.contains("Not recommended"),
            "The Source reference section must not contain the 480 s not-recommended boundary row."
        )

        let guidanceBoundarySection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Guidance boundary" }),
            "Provia 100F must surface a Guidance boundary section for the 480 s not-recommended row."
        )
        let boundaryBlock = try XCTUnwrap(guidanceBoundarySection.rows.first?.value)
        XCTAssertTrue(
            boundaryBlock.contains("Not recommended"),
            "Guidance boundary block must surface the 480 s not-recommended boundary."
        )
        XCTAssertFalse(
            boundaryBlock.contains("2.5G"),
            "Guidance boundary section must not pull the 240 s source-reference row into it."
        )

        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Formula profiles with source evidence must not surface the legacy Reference section."
        )

        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Profile" }),
            "Profile metadata block is removed; the calculation method is implied by the visible curve."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Formula" }),
            "Formula metadata block is removed; the formula expression now lives next to the graph."
        )
        let formula = try XCTUnwrap(
            displayState.graph?.formulaDisplayText,
            "Formula expression must be exposed on the graph state."
        )
        XCTAssertTrue(formula.contains("1.3676"))
    }

    @MainActor
    func testProvia100FGraphCarries240SecondSourceReferenceMarker() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)

        let marker = try XCTUnwrap(
            graph.sourceReferenceMarkers.first {
                abs($0.point.meteredExposureSeconds - 240) < 1e-6
            },
            "Provia 100F graph state must include the 240 s manufacturer source reference marker."
        )

        // Source-evidence carries a +1/3 stop adjustment at 240 s:
        // 240 × 2^(1/3) ≈ 302.4 s.
        XCTAssertEqual(marker.point.correctedExposureSeconds, 302.4, accuracy: 1.0)
        XCTAssertEqual(
            marker.label,
            "240s",
            "Source reference markers carry an adjacent label so the user reads the published metered value directly off the graph."
        )
    }

    @MainActor
    func testProvia100FGraphCarriesNotRecommendedBoundaryAt480Seconds() throws {
        for metered in [60.0, 240.0, 600.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.notRecommendedBoundarySeconds ?? 0,
                480,
                accuracy: 1e-6,
                "Metered \(metered) s: graph must expose Provia 100F's 480 s not-recommended boundary."
            )
        }
    }

    @MainActor
    func testProvia100FGraphSourceReferenceMarkersExclude480SecondBoundary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)

        for marker in graph.sourceReferenceMarkers {
            XCTAssertNotEqual(
                marker.point.meteredExposureSeconds,
                480,
                accuracy: 1e-6,
                "480 s must remain a Guidance boundary, never a source-reference fitting point."
            )
        }
    }

    @MainActor
    func testProvia100FGraphCurrentResultMarkerPersistsAlongsideReferenceElements() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)

        let currentPoint = try XCTUnwrap(
            graph.currentPoint,
            "Current result marker must remain present when source-reference markers and boundary are also shown."
        )
        XCTAssertEqual(currentPoint.style, .formulaDerived)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 240, accuracy: 1e-6)
    }

    @MainActor
    func testProvia100FInSourceRangeGraphHasNoDuplicateDescriptionLines() throws {
        // The marker, region, and legend already name every visible
        // graph element in the supported source range. Description
        // lines stay empty here so the user does not read the same
        // information twice.
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(
            graph.descriptionLines.isEmpty,
            "Source-range cases must not repeat marker/region meanings via description lines; got: \(graph.descriptionLines)"
        )
    }

    @MainActor
    func testProvia100FBeyondSourceRangeProducesSingleSourceRangeNote() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 600)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.descriptionLines.count, 1)
        let line = try XCTUnwrap(graph.descriptionLines.first)
        XCTAssertTrue(line.lowercased().contains("source range"), "Got: \(line)")
    }

    @MainActor
    func testProvia100FBeyondVisibleRangeProducesSingleVisibleRangeNote() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 500_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.descriptionLines.count, 1)
        let line = try XCTUnwrap(graph.descriptionLines.first)
        XCTAssertTrue(line.lowercased().contains("beyond the visible"), "Got: \(line)")
    }

    // MARK: - Scale policy (tier-based domain)

    func testScalePolicySelectsT1ForValuesUpToOneHour() {
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 1), .t1)
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 600), .t1)
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 3_600), .t1)
    }

    func testScalePolicySelectsT2ForValuesAboveOneHourUpToTenHours() {
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 3_601), .t2)
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 10_000), .t2)
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 36_000), .t2)
    }

    func testScalePolicySelectsT3ForValuesAboveTenHoursUpToOneHundredHours() {
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 36_001), .t3)
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 100_000), .t3)
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 360_000), .t3)
    }

    func testScalePolicyKeepsT3ForValuesBeyondOneHundredHoursAndReportsOverflow() {
        XCTAssertEqual(FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: 1_000_000), .t3)
        XCTAssertTrue(FilmModeDetailsGraphScalePolicy.isBeyondVisibleRange(maxPlottedSeconds: 1_000_000))
        XCTAssertFalse(FilmModeDetailsGraphScalePolicy.isBeyondVisibleRange(maxPlottedSeconds: 360_000))
    }

    func testScalePolicyAxisLabelsArePhoneWidthFriendly() {
        XCTAssertLessThanOrEqual(FilmModeDetailsGraphScaleTier.t1.axisTicks.count, 8)
        XCTAssertLessThanOrEqual(FilmModeDetailsGraphScaleTier.t2.axisTicks.count, 8)
        XCTAssertLessThanOrEqual(FilmModeDetailsGraphScaleTier.t3.axisTicks.count, 6)

        for tier in [FilmModeDetailsGraphScaleTier.t1, .t2, .t3] {
            let values = tier.axisTicks.map(\.value)
            for value in values {
                XCTAssertGreaterThanOrEqual(value, tier.lowerBoundSeconds)
                XCTAssertLessThanOrEqual(value, tier.upperBoundSeconds)
            }
            XCTAssertEqual(values, values.sorted(), "Tier \(tier) axis labels must be sorted ascending.")
        }
    }

    // MARK: - Provia 100F tier selection and marker consistency

    @MainActor
    func testProvia100FUsesT1ForNormalInputs() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.scaleTier, .t1, "240 s plus a corrected exposure of ~302 s must stay inside the 1 h tier.")
        XCTAssertEqual(graph.xRange, 1...3_600)
        XCTAssertEqual(graph.yRange, 1...3_600)
        XCTAssertFalse(graph.isBeyondVisibleRange)
    }

    @MainActor
    func testProvia100FUsesT2OrT3WhenFormulaPredictionExceedsOneHour() throws {
        // formula(3000) ≈ 128 × (3000/128)^1.3676 ≈ 8200 s, > 1 h →
        // pushes the graph past T1 into T2 (or higher if the y also
        // exceeds T2).
        let displayState = try makeDisplayState(meteredExposureSeconds: 3_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertNotEqual(graph.scaleTier, .t1, "Predicted y above 1 h must escape T1.")
        XCTAssertTrue(
            graph.scaleTier == .t2 || graph.scaleTier == .t3,
            "Expected T2 or T3 for a 3000 s metered input; got \(String(describing: graph.scaleTier))."
        )
        XCTAssertFalse(graph.isBeyondVisibleRange)
    }

    @MainActor
    func testProvia100FBeyondOneHundredHoursStaysAtT3WithOverflowIndicator() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 500_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.scaleTier, .t3, "Inputs past T3.upperBound must stay pinned to T3.")
        XCTAssertEqual(graph.xRange, 1...360_000, "xRange must be capped at T3 even for very large inputs.")
        XCTAssertEqual(graph.yRange, 1...360_000, "yRange must be capped at T3 even for very large inputs.")
        XCTAssertTrue(graph.isBeyondVisibleRange, "isBeyondVisibleRange must trip for current values past T3.")
    }

    @MainActor
    func testProvia100FFormulaCurveDoesNotExceedSelectedTier() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 500_000)
        let graph = try XCTUnwrap(displayState.graph)
        let maxSample = try XCTUnwrap(graph.sourcePoints.map(\.meteredExposureSeconds).max())
        XCTAssertLessThanOrEqual(
            maxSample,
            FilmModeDetailsGraphScaleTier.t3.upperBoundSeconds,
            "The formula curve must not be sampled past the tier upper bound."
        )
    }

    @MainActor
    func testProvia100FSourceMarkersAndBoundaryStayWithinSelectedTier() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)
        let tier = try XCTUnwrap(graph.scaleTier)
        for marker in graph.sourceReferenceMarkers {
            XCTAssertTrue(tier.range.contains(marker.point.meteredExposureSeconds))
            XCTAssertTrue(tier.range.contains(marker.point.correctedExposureSeconds))
        }
        if let boundary = graph.notRecommendedBoundarySeconds {
            XCTAssertTrue(tier.range.contains(boundary))
        }
    }

    @MainActor
    func testProvia100FAxisTicksAreTierDerived() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)
        let tier = try XCTUnwrap(graph.scaleTier)
        XCTAssertEqual(graph.xAxisTicks.map(\.label), tier.axisTicks.map(\.label))
        XCTAssertEqual(graph.yAxisTicks.map(\.label), tier.axisTicks.map(\.label))
        XCTAssertTrue(
            graph.xAxisTicks.map(\.label).contains("1h"),
            "T1 axis must contain the 1h label."
        )
    }

    // MARK: - Source-range presentation

    @MainActor
    func testProvia100FSupportedRangeUsesReferenceBackedSummary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Reference-backed formula prediction",
            "Converted formula profiles must surface reference-backed wording in the supported formula range."
        )
    }

    @MainActor
    func testProvia100FBeyondSourceRangeUsesSourceRangeWordingNotExtrapolated() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 600)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Beyond source range",
            "Provia 100F outside supported guidance must not use Extrapolated wording."
        )
        let detail = try XCTUnwrap(displayState.summary.detailText)
        XCTAssertFalse(
            detail.lowercased().contains("extrapolated"),
            "Detail text must avoid Extrapolated as the primary label; got: \(detail)"
        )
        XCTAssertTrue(
            detail.lowercased().contains("source range"),
            "Detail text must surface source-range wording; got: \(detail)"
        )

        let graph = try XCTUnwrap(displayState.graph)
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertFalse(
            explanation.lowercased().contains("extrapolated"),
            "Graph explanation must avoid Extrapolated as the primary label; got: \(explanation)"
        )
        XCTAssertTrue(
            explanation.lowercased().contains("source range"),
            "Graph explanation must surface source-range wording; got: \(explanation)"
        )
    }

    @MainActor
    func testProvia100FCorrectedExposureNoLongerCarriesSecondaryDescription() throws {
        // Detail surfaces the long-form note via the graph note;
        // the Main corrected-exposure card no longer renders a
        // per-state caption. The model state therefore returns an
        // empty secondary text for every numeric reciprocity case
        // — both supported and outside-guidance.
        let film = try proviaFilm()
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()

        for metered in [240.0, 600.0] {
            let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: metered)
            let bindingState = FilmModeReciprocityBindingState(
                film: film,
                profile: profile,
                policyResult: policyResult,
                presentation: policyResult.confidencePresentation
            )
            let correctedDisplay = model.correctedExposureDisplayState(for: bindingState)
            XCTAssertEqual(
                correctedDisplay.secondaryText,
                "",
                "Metered \(metered) s: numeric reciprocity results must not surface a Main secondary description; the detail/graph note carries any long-form explanation."
            )
        }
    }

    // MARK: - Existing formula profile regression (no source evidence)

    @MainActor
    func testHP5PlusFormulaProfileKeepsLegacyWordingAndTierBasedScale() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "HP5 Plus" },
            "HP5 Plus must remain in the launch catalog."
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 8)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let displayState = try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: .success(
                        ExposureCalculationResult(baseShutterSeconds: 8, stop: 0, resultShutterSeconds: 8)
                    ),
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )

        XCTAssertEqual(
            displayState.summary.summaryText,
            "Formula-based correction on the active curve",
            "Source-less formula profiles must keep the existing summary wording."
        )

        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(graph.sourceReferenceMarkers.isEmpty)
        XCTAssertNil(graph.notRecommendedBoundarySeconds)
        // HP5 Plus at 8 s with no upper formula bound still snaps to
        // a tier; the curve's intrinsic upper of 120 s (canonical
        // fallback) and corrected ~14 s both fit comfortably in T1.
        XCTAssertEqual(graph.scaleTier, .t1)
    }

    // MARK: - Non-converted table profile regression

    // MARK: - Below-visible-range (< 1 s)

    @MainActor
    func testProvia100FSubSecondInputTripsBelowVisibleRangeAndSuppressesMarker() throws {
        // 1/30 s metered: well below the T1 lower bound (1 s).
        // The graph must stay anchored to its tier domain and not
        // park the marker at the 1 s axis edge pretending to be a
        // legitimate value.
        let displayState = try makeDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(
            graph.isBelowVisibleRange,
            "A 1/30 s input must trip the below-visible-range flag so the view can suppress the on-plot marker."
        )
        XCTAssertEqual(graph.scaleTier, .t1, "Below-visible-range inputs still pin to a tier — the lowest one (T1).")
        XCTAssertFalse(graph.isBeyondVisibleRange)
        XCTAssertEqual(graph.xRange, 1...3_600)
    }

    @MainActor
    func testProvia100FOneSecondInputDoesNotTripBelowVisibleRange() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 1)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertFalse(
            graph.isBelowVisibleRange,
            "1 s sits exactly on the tier lower bound; it should not be marked below-visible."
        )
    }

    @MainActor
    func testProvia100FFormulaCurveSamplesStayAtOrAboveOneSecond() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        let graph = try XCTUnwrap(displayState.graph)
        let minSample = try XCTUnwrap(graph.sourcePoints.map(\.meteredExposureSeconds).min())
        XCTAssertGreaterThanOrEqual(
            minSample,
            FilmModeDetailsGraphScaleTier.t1.lowerBoundSeconds,
            "Curve samples must never sit below the active tier's lower bound."
        )
    }

    // MARK: - Layout

    @MainActor
    func testProvia100FDetailsSectionOrderIsSourceReferenceGuidanceBoundarySources() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let titles = displayState.sections.map(\.title)
        XCTAssertEqual(
            titles,
            ["Source reference", "Guidance boundary", "Sources"],
            "Provia 100F details only show evidence sections plus Sources; Profile/Formula are gone."
        )
    }

    @MainActor
    func testProvia100FCurrentResultStatusTextIsShortAndStateAware() throws {
        let supported = try makeDisplayState(meteredExposureSeconds: 240)
        XCTAssertEqual(supported.currentResult.statusText, "Formula-derived")

        let beyondSource = try makeDisplayState(meteredExposureSeconds: 600)
        XCTAssertEqual(beyondSource.currentResult.statusText, "Beyond source range")
        XCTAssertEqual(beyondSource.currentResult.statusTone, .unsupported)

        let noCorrection = try makeDisplayState(meteredExposureSeconds: 60)
        XCTAssertEqual(noCorrection.currentResult.statusText, "No correction")

        // Visible-range membership is a graph affordance (orange
        // triangle + graph note); the status text stays anchored
        // to the calculation basis on converted formula profiles.
        let beyondVisible = try makeDisplayState(meteredExposureSeconds: 500_000)
        XCTAssertEqual(
            beyondVisible.currentResult.statusText,
            "Beyond source range",
            "Provia 100F (converted) keeps the source-range status even when current is past T3."
        )

        let belowVisible = try makeDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        XCTAssertEqual(
            belowVisible.currentResult.statusText,
            "No correction",
            "Sub-second Provia 100F sits in the no-correction threshold; status text follows the basis, not the visible-range flag."
        )
    }

    // MARK: - Unified Current Result layout

    @MainActor
    func testProvia100FNoCorrectionUsesComparisonLayoutLikeEveryOtherCase() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 60)
        XCTAssertEqual(
            displayState.currentResult.layout,
            .comparison,
            "No-correction must use the same comparison layout as every other case so the screen shape is consistent."
        )
        XCTAssertNotEqual(
            displayState.currentResult.correctedExposure.detailText,
            "Adjusted shutter equals corrected exposure.",
            "Legacy no-correction-specific note must not appear."
        )
        XCTAssertEqual(displayState.currentResult.statusText, "No correction")
    }

    @MainActor
    func testProvia100FAllCasesShareSameLayoutAndProduceStatusText() throws {
        let cases: [(meter: Double, expectedStatus: String)] = [
            (60, "No correction"),
            (240, "Formula-derived"),
            (600, "Beyond source range")
        ]
        for (meter, expected) in cases {
            let displayState = try makeDisplayState(meteredExposureSeconds: meter)
            XCTAssertEqual(
                displayState.currentResult.layout,
                .comparison,
                "Metered \(meter) s must use the comparison layout."
            )
            XCTAssertEqual(
                displayState.currentResult.statusText,
                expected,
                "Metered \(meter) s status text must equal \(expected)."
            )
        }
    }

    // MARK: - ≈ duplication regression

    @MainActor
    func testProvia100FBeyondVisibleNumericResultDoesNotDoubleApproximateMarker() throws {
        // A Provia 100F input that produces both an outside-guidance
        // numeric (the model adds a "≈" prefix) AND a year-coarsened
        // formatter output (the coarse formatter already prefixes
        // "≈") used to read as "≈≈Ny". The dedup keeps a single
        // approximate marker.
        let film = try proviaFilm()
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 1_000_000)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let correctedDisplay = model.correctedExposureDisplayState(for: bindingState)
        XCTAssertTrue(correctedDisplay.primaryText.hasPrefix("≈"))
        XCTAssertFalse(
            correctedDisplay.primaryText.hasPrefix("≈≈"),
            "Approximate marker doubled to \"≈≈\" — got: \(correctedDisplay.primaryText)"
        )
    }

    // MARK: - Status / graph state cross-checks for visible-range cases

    @MainActor
    func testProvia100FBeyondVisibleStatusStaysOnBasisWhileGraphFlagsTrip() throws {
        // Provia 100F at a multi-day metered input lands far past
        // the T3 upper bound. The graph must trip its
        // `isBeyondVisibleRange` flag so the orange edge triangle
        // and the "outside visible" graph note render, but the
        // status text on the current-result card must stay anchored
        // to the calculation basis ("Beyond source range") so the
        // user reads one wording across surfaces.
        let displayState = try makeDisplayState(meteredExposureSeconds: 1_000_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(graph.isBeyondVisibleRange)
        XCTAssertEqual(displayState.currentResult.statusText, "Beyond source range")
        XCTAssertEqual(displayState.summary.badgeText, "Beyond source range")
    }

    @MainActor
    func testProvia100FBelowVisibleStatusStaysOnBasis() throws {
        // 1/30 s metered is below the T1 lower bound but sits
        // inside Provia 100F's threshold no-correction band. The
        // basis-derived status wins over the visible-range flag.
        let displayState = try makeDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(graph.isBelowVisibleRange)
        XCTAssertEqual(displayState.currentResult.statusText, "No correction")
    }

    // MARK: - Main badge / Detail status alignment

    @MainActor
    func testProvia100FMainBadgeAndDetailStatusUseTheSameWording() throws {
        let cases: [(meter: Double, expected: String)] = [
            (60, "No correction"),
            (240, "Formula-derived"),
            (600, "Beyond source range")
        ]
        for (meter, expected) in cases {
            let displayState = try makeDisplayState(meteredExposureSeconds: meter)
            XCTAssertEqual(
                displayState.summary.badgeText,
                expected,
                "Main badge text for metered \(meter) s must read \(expected)."
            )
            XCTAssertEqual(
                displayState.currentResult.statusText,
                expected,
                "Detail status text for metered \(meter) s must read \(expected)."
            )
        }
    }

    // MARK: - Simplified Sources

    @MainActor
    func testProvia100FSourcesAreAnUnlabeledListWithoutReferenceCitationLabels() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let sources = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Sources" }))
        XCTAssertEqual(sources.rows.map(\.title), ["", ""])
        XCTAssertFalse(sources.rows.contains { $0.title == "Reference" })
        XCTAssertFalse(sources.rows.contains { $0.title == "Citation" })

        let texts = sources.rows.map(\.value)
        XCTAssertTrue(
            texts.contains(where: { $0.contains("FUJICHROME PROVIA 100F") }),
            "Sources list must include the manufacturer reference text."
        )
        XCTAssertTrue(
            texts.contains(where: { $0.contains("Provia 100F support page") }),
            "Sources list must include the citation text."
        )
    }

    // MARK: - Formula display near the graph

    @MainActor
    func testProvia100FGraphCarriesFormulaDisplayTextWithFourDecimalExponent() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)
        let formula = try XCTUnwrap(
            graph.formulaDisplayText,
            "Formula graphs must expose the formula expression next to the curve."
        )
        XCTAssertTrue(
            formula.contains("1.3676"),
            "Formula exponent must be rendered at 4-decimal precision; got: \(formula)"
        )
        XCTAssertTrue(
            formula.contains("128"),
            "Formula expression must communicate the 128 s anchor; got: \(formula)"
        )
    }

    @MainActor
    func testHP5PlusFormulaGraphCarriesFormulaDisplayTextWithoutSourceReferenceArtifacts() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "HP5 Plus" }
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 8)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let displayState = try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: .success(
                        ExposureCalculationResult(baseShutterSeconds: 8, stop: 0, resultShutterSeconds: 8)
                    ),
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )

        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertNotNil(
            graph.formulaDisplayText,
            "Source-less formula profiles still surface the formula expression near the graph."
        )
        XCTAssertNil(
            graph.beyondSourceRangeStartSeconds,
            "Profiles without source evidence must not render a pink beyond-source region."
        )
    }

    // MARK: - Beyond-source-range (pink) region

    @MainActor
    func testProvia100FGraphCarriesBeyondSourceRangeStartAt480Seconds() throws {
        for metered in [60.0, 240.0, 600.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.beyondSourceRangeStartSeconds ?? 0,
                480,
                accuracy: 1e-6,
                "Metered \(metered) s: pink beyond-source region must start at 480 s regardless of current input."
            )
        }
    }

    // MARK: - Outside-visible-range indicator semantics

    @MainActor
    func testProvia100FBeyondVisibleSuppressesInRangeCurrentMarker() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 500_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(graph.isBeyondVisibleRange)
        // The current point object is still produced (for status/
        // diagnostic surfaces) but the view-rendering invariant is
        // tested via the flag — the view skips in-range marker draws
        // whenever this flag is true. See FilmModeDetailsView.
        XCTAssertNotNil(graph.currentPoint)
    }

    @MainActor
    func testProvia100FBelowVisibleSuppressesInRangeCurrentMarker() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(graph.isBelowVisibleRange)
    }

    // MARK: - Centralized converted-profile classification

    func testConvertedFormulaProfileFlagIsTrueOnlyForFormulaPlusSourceEvidence() throws {
        let provia = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Provia 100F" }?.profiles.first
        )
        XCTAssertTrue(provia.isConvertedFormulaProfile)

        let hp5Plus = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "HP5 Plus" }?.profiles.first
        )
        XCTAssertFalse(
            hp5Plus.isConvertedFormulaProfile,
            "Source-less formula profiles must not be classified as converted."
        )

        let triX = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Tri-X 400" }?.profiles.first
        )
        XCTAssertFalse(
            triX.isConvertedFormulaProfile,
            "Table-based profiles without a formula rule must not be classified as converted."
        )
    }

    @MainActor
    func testTriX400TableProfileKeepsExistingWordingAndAxisTicks() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Tri-X 400" },
            "Tri-X 400 must remain in the launch catalog."
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 5)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let displayState = try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: .success(
                        ExposureCalculationResult(baseShutterSeconds: 5, stop: 0, resultShutterSeconds: 5)
                    ),
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )

        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .table, "Tri-X 400 must keep the table graph path.")
        XCTAssertNil(graph.scaleTier, "Table graphs must not be forced onto the formula tier policy.")
        XCTAssertFalse(graph.isBeyondVisibleRange)

        // Tri-X 400 outside-table summary wording must continue to
        // use the legacy reference-data phrasing — the source-range
        // rewording is scoped to converted formula profiles only.
        XCTAssertFalse(
            displayState.summary.summaryText.lowercased().contains("source range"),
            "Non-converted table profiles must not pick up source-range wording; got: \(displayState.summary.summaryText)"
        )
    }

    @MainActor
    func testHP5PlusFormulaGraphCarriesNoSourceReferenceArtifacts() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "HP5 Plus" },
            "HP5 Plus must remain in the launch catalog."
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 8)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let displayState = try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: .success(
                        ExposureCalculationResult(baseShutterSeconds: 8, stop: 0, resultShutterSeconds: 8)
                    ),
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )

        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(
            graph.sourceReferenceMarkers.isEmpty,
            "HP5 Plus carries no published source evidence, so the formula graph must not invent markers."
        )
        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "HP5 Plus carries no not-recommended boundary."
        )
        XCTAssertTrue(
            graph.descriptionLines.isEmpty,
            "Profiles without source-reference markers stay on the existing state-aware caption rather than introducing description lines."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Source reference" }),
            "HP5 Plus must not surface a Source reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "HP5 Plus must not surface a Guidance boundary section."
        )
    }

    /// At no-correction inputs the Details surface still renders the
    /// formula reference graph and plots the current point on the
    /// identity line with the `.noCorrection` marker, not as a
    /// formula prediction. Keeps the profile structurally consistent
    /// across shutter ranges.
    @MainActor
    func testProvia100FNoCorrectionInputStillRendersGraphWithIdentityCurrentPoint() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 60)

        let graph = try XCTUnwrap(
            displayState.graph,
            "Provia 100F details graph must remain visible for no-correction inputs."
        )
        XCTAssertEqual(graph.kind, .formula)

        let currentPoint = try XCTUnwrap(
            graph.currentPoint,
            "No-correction graph must still plot a current point so the user can locate their input."
        )
        XCTAssertEqual(
            currentPoint.style,
            .noCorrection,
            "No-correction current point must use the .noCorrection marker rather than .formulaDerived."
        )
        XCTAssertEqual(
            currentPoint.point.meteredExposureSeconds,
            currentPoint.point.correctedExposureSeconds,
            accuracy: 1e-6,
            "No-correction current point sits on adjusted == corrected (the identity line)."
        )
    }

    /// The no-correction range upper bound (Provia 100F's 128 s
    /// threshold) must be exposed on the graph state so the view can
    /// shade the no-correction band and draw the boundary guide.
    @MainActor
    func testProvia100FGraphCarriesNoCorrectionRangeUpperBound() throws {
        for metered in [60.0, 240.0, 600.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.noCorrectionRangeUpperBoundSeconds ?? 0,
                128,
                accuracy: 1e-6,
                "Metered \(metered) s: graph must expose Provia 100F's 128 s threshold so the view can shade the no-correction range."
            )
        }
    }

    /// The formula curve must not be drawn through the no-correction
    /// range. The lowest sampled metered exposure stays at or above
    /// the threshold upper bound so the region left of 128 s reads as
    /// policy-controlled rather than as a formula prediction.
    @MainActor
    func testProvia100FFormulaCurveDoesNotExtendIntoNoCorrectionRange() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 60)
        let graph = try XCTUnwrap(displayState.graph)

        let minimumSampledMetered = try XCTUnwrap(
            graph.sourcePoints.map(\.meteredExposureSeconds).min(),
            "Formula curve must produce at least one source sample."
        )
        XCTAssertGreaterThanOrEqual(
            minimumSampledMetered,
            128,
            "Formula curve sampling must start at or above Provia 100F's 128 s threshold; got \(minimumSampledMetered) s."
        )
    }

    /// The no-correction caption must not describe the point as
    /// sitting on the active formula curve. It must call out the
    /// no-correction range explicitly.
    @MainActor
    func testProvia100FNoCorrectionGraphCaptionDoesNotReferenceFormulaCurve() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 60)
        let graph = try XCTUnwrap(displayState.graph)

        XCTAssertFalse(
            graph.caption.lowercased().contains("formula curve"),
            "No-correction graph caption must not describe the point as being on the active formula curve; got: \(graph.caption)"
        )
        XCTAssertTrue(
            graph.caption.lowercased().contains("no-correction"),
            "No-correction graph caption must reference the no-correction range; got: \(graph.caption)"
        )
    }

    /// At unsupported inputs that still produce a numeric formula
    /// extrapolation, the Details graph plots the current point on
    /// the formula curve with the `.extrapolated` style, not the
    /// "x-position only" red guide.
    @MainActor
    func testProvia100FUnsupportedNumericInputRendersExtrapolatedCurrentPoint() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 600)

        let graph = try XCTUnwrap(
            displayState.graph,
            "Unsupported-with-numeric must still render the formula reference graph."
        )
        XCTAssertFalse(
            graph.usesCurrentInputGuideOnly,
            "A formula-extrapolated unsupported numeric must plot a real current point, not a guide line."
        )
        let currentPoint = try XCTUnwrap(graph.currentPoint)
        XCTAssertEqual(currentPoint.style, .extrapolated)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 600, accuracy: 1e-6)
    }

    /// The corrected-exposure card surfaces the formula-extrapolated
    /// value at unsupported inputs, and the timer-action state flags
    /// itself as outside manufacturer guidance so the play button can
    /// render with a warning-oriented treatment.
    @MainActor
    func testProvia100FUnsupportedNumericEnablesCorrectedExposurePlayButton() throws {
        let film = try proviaFilm()
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 600)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )

        let correctedDisplay = model.correctedExposureDisplayState(for: bindingState)
        XCTAssertEqual(correctedDisplay.kind, .quantified)
        XCTAssertTrue(
            correctedDisplay.usesNumericExposure,
            "Numeric extrapolation must flow into the quantified display kind so the corrected card shows the value."
        )
        XCTAssertTrue(
            correctedDisplay.primaryText.hasPrefix("≈"),
            "Numeric extrapolation must be marked approximate; got: \(correctedDisplay.primaryText)"
        )
        XCTAssertFalse(
            correctedDisplay.primaryText.hasPrefix("≈≈"),
            "Approximate marker must not be doubled when the formatter already prefixes one; got: \(correctedDisplay.primaryText)"
        )
        // The Main card no longer carries a per-state caption;
        // detailed wording lives in the Detail graph note. The model
        // therefore returns an empty secondary text.
        XCTAssertEqual(correctedDisplay.secondaryText, "")

        let action = model.correctedExposureActionState(for: bindingState)
        XCTAssertTrue(action.canStartTimer, "Numeric extrapolation must enable the play button.")
        XCTAssertEqual(action.targetSeconds, policyResult.correctedExposureSeconds)
        XCTAssertTrue(
            action.isOutsideManufacturerGuidance,
            "The action state must preserve the outside-manufacturer-guidance basis so the start path can stamp it on the timer identity."
        )
    }

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        let film = try proviaFilm()
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

    // MARK: - Helpers

    private func proviaProfile() throws -> ReciprocityProfile {
        let film = try proviaFilm()
        return try XCTUnwrap(film.profiles.first)
    }

    private func proviaFilm() throws -> FilmIdentity {
        try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Provia 100F" },
            "Provia 100F must remain in the launch catalog."
        )
    }
}
