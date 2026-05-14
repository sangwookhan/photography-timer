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
    func testProvia100FDetailsRendersFormulaAndReferenceSections() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)

        XCTAssertTrue(displayState.sections.contains(where: { $0.title == "Formula" }), "Provia 100F details must surface the Formula section.")

        let referenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Reference" }),
            "Provia 100F details must surface a Reference section built from source evidence."
        )
        let block = try XCTUnwrap(referenceSection.rows.first?.value)
        XCTAssertTrue(block.contains("2.5G"), "Reference block must surface the 2.5G manufacturer color guidance.")
        XCTAssertTrue(block.contains("Not recommended"), "Reference block must surface the 480 s not-recommended boundary.")

        let profileSection = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Profile" }))
        let methodValue = profileSection.rows.first(where: { $0.title == "Method" })?.value
        XCTAssertEqual(
            methodValue,
            "Formula-based guidance",
            "Provia 100F's profile method row must report formula-based guidance, not the residual reference table."
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
        XCTAssertTrue(
            correctedDisplay.secondaryText.lowercased().contains("outside manufacturer"),
            "Secondary text must call out that the value sits outside manufacturer guidance."
        )

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
