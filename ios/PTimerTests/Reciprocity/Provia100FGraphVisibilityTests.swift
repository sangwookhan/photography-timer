import XCTest
import PTimerKit
@testable import PTimer

final class Provia100FGraphVisibilityTests: XCTestCase {
    // MARK: - Sub-second no-correction visibility

    @MainActor
    func testProvia100FSubSecondInputSitsInsideVisibleNoCorrectionBand() throws {
        // 1/30 s metered is inside Provia 100F's published
        // no-correction band (0.00025 … 128 s). The stable
        // viewport extends below 1 s so the no-correction state
        // is visible end-to-end — the marker sits at its real
        // position on the identity line instead of being hidden as
        // off-graph.
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertFalse(
            graph.isBelowVisibleRange,
            "Sub-1 s no-correction inputs must sit inside the visible plot, not below it."
        )
        XCTAssertEqual(graph.scaleTier, .t1, "Tier selection is unchanged — the lower-bound is profile-stable, not tier-driven.")
        XCTAssertFalse(graph.isBeyondVisibleRange)
        XCTAssertLessThan(
            graph.xRange.lowerBound,
            1.0,
            "Viewport must extend below 1 s so the no-correction region is visible."
        )
        XCTAssertEqual(graph.xRange.upperBound, 3_600,
                       "Upper bound stays anchored to the tier so the calculation curve domain reads at its existing visual proportions.")
    }

    @MainActor
    func testProvia100FOneSecondInputDoesNotTripBelowVisibleRange() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 1)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertFalse(
            graph.isBelowVisibleRange,
            "1 s sits exactly on the tier lower bound; it should not be marked below-visible."
        )
    }

    @MainActor
    func testProvia100FCalculationCurveStartsAtViewportLowerBoundAsIdentitySegment() throws {
        // The calculation curve now includes an identity segment
        // (Tc = Tm) through the no-correction range so the path is
        // continuous from the viewport's leading edge through the
        // formula segment. Samples must therefore extend down to
        // the profile-stable lower bound while every identity
        // sample sits on the y = x line.
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        let graph = try XCTUnwrap(displayState.graph)
        let minSample = try XCTUnwrap(graph.sourcePoints.map(\.meteredExposureSeconds).min())
        XCTAssertEqual(
            minSample,
            graph.xRange.lowerBound,
            accuracy: 1e-6,
            "Calculation curve must begin at the viewport's leading edge so the no-correction zone is not a visual gap."
        )

        guard let threshold = graph.noCorrectionRangeUpperBoundSeconds else {
            return XCTFail("Provia 100F must surface a no-correction upper bound.")
        }
        let identitySamples = graph.sourcePoints.filter { $0.meteredExposureSeconds <= threshold }
        XCTAssertFalse(identitySamples.isEmpty, "Identity segment must produce at least one sample.")
        for point in identitySamples {
            XCTAssertEqual(
                point.correctedExposureSeconds,
                point.meteredExposureSeconds,
                accuracy: 1e-6,
                "Identity-segment samples must produce corrected == metered through the no-correction zone."
            )
        }
    }

    // MARK: - Formula display near the graph

    @MainActor
    func testProvia100FGraphCarriesFormulaDisplayTextWithFourDecimalExponent() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 240)
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

    // MARK: - Beyond-source-range (pink) region

    /// PTIMER-160: pink beyond-source region starts at
    /// `sourceRangeThroughSeconds`, the last quantified source-backed
    /// anchor — 240 s for Provia 100F. The 480 s row is a separate
    /// "Not recommended" warning marker (see
    /// `notRecommendedBoundarySeconds`), not the source-range
    /// boundary.
    @MainActor
    func testProvia100FGraphCarriesBeyondSourceRangeStartAt240Seconds() throws {
        for metered in [60.0, 240.0, 600.0] {
            let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.beyondSourceRangeStartSeconds ?? 0,
                240,
                accuracy: 1e-6,
                "Metered \(metered) s: pink beyond-source region must start at the 240 s source-backed anchor."
            )
        }
    }

    // MARK: - Outside-visible-range indicator semantics

    @MainActor
    func testProvia100FBeyondVisibleSuppressesInRangeCurrentMarker() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 500_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(graph.isBeyondVisibleRange)
        XCTAssertNotNil(graph.currentPoint)
    }

    @MainActor
    func testProvia100FSubSecondInputKeepsCurrentMarkerVisibleInsideViewport() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertFalse(graph.isBelowVisibleRange)
        let currentPoint = try XCTUnwrap(graph.currentPoint)
        XCTAssertEqual(currentPoint.style, .noCorrection)
        XCTAssertLessThan(graph.xRange.lowerBound, currentPoint.point.meteredExposureSeconds)
    }

    /// At no-correction inputs the Details surface still renders the
    /// formula reference graph and plots the current point on the
    /// identity line with the `.noCorrection` marker, not as a
    /// formula prediction. Keeps the profile structurally consistent
    /// across shutter ranges.
    @MainActor
    func testProvia100FNoCorrectionInputStillRendersGraphWithIdentityCurrentPoint() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 60)

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
            let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: metered)
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
    func testProvia100FFormulaSegmentBeyondThresholdLeavesIdentityForPredictedCurve() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 60)
        let graph = try XCTUnwrap(displayState.graph)

        let pastThreshold = graph.sourcePoints.first(where: { $0.meteredExposureSeconds > 128 + 1e-6 })
        let predictedSample = try XCTUnwrap(
            pastThreshold,
            "Calculation curve must include at least one sample beyond Provia 100F's 128 s threshold."
        )
        XCTAssertGreaterThan(
            predictedSample.correctedExposureSeconds,
            predictedSample.meteredExposureSeconds,
            "Formula segment past the threshold must produce corrected > metered (formula curve lifts off the identity line)."
        )
    }

    /// The no-correction caption must not describe the point as
    /// sitting on the active calculation curve — that wording is
    /// reserved for the predicted formula segment. The caption
    /// must call out the no-correction range explicitly so the
    /// user reads the state as policy-driven, not curve-driven.
    @MainActor
    func testProvia100FNoCorrectionGraphCaptionReferencesNoCorrectionRangeNotCalculationCurve() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 60)
        let graph = try XCTUnwrap(displayState.graph)

        XCTAssertFalse(
            graph.caption.lowercased().contains("calculation curve"),
            "No-correction graph caption must not describe the point as being on the active calculation curve; got: \(graph.caption)"
        )
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
    /// prediction outside the source range, the Details graph plots
    /// the current point on the formula curve with the
    /// `.beyondSourceRange` style, not the "x-position only" red guide.
    @MainActor
    func testProvia100FUnsupportedNumericInputRendersBeyondSourceRangeCurrentPoint() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 600)

        let graph = try XCTUnwrap(
            displayState.graph,
            "Unsupported-with-numeric must still render the formula reference graph."
        )
        XCTAssertFalse(
            graph.usesCurrentInputGuideOnly,
            "A numeric formula prediction outside the source range must plot a real current point, not a guide line."
        )
        let currentPoint = try XCTUnwrap(graph.currentPoint)
        XCTAssertEqual(currentPoint.style, .beyondSourceRange)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 600, accuracy: 1e-6)
    }

    /// The corrected-exposure card surfaces the formula prediction
    /// outside the source range at unsupported inputs, and the
    /// timer-action state flags itself as outside manufacturer
    /// guidance so the play button can render with a warning-oriented
    /// treatment.
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
            "Numeric formula prediction must flow into the quantified display kind so the corrected card shows the value."
        )
        XCTAssertTrue(
            correctedDisplay.primaryText.hasPrefix("≈"),
            "Numeric formula prediction must be marked approximate; got: \(correctedDisplay.primaryText)"
        )
        XCTAssertFalse(
            correctedDisplay.primaryText.hasPrefix("≈≈"),
            "Approximate marker must not be doubled when the formatter already prefixes one; got: \(correctedDisplay.primaryText)"
        )
        let action = model.correctedExposureActionState(for: bindingState)
        XCTAssertTrue(action.canStartTimer, "Numeric formula prediction must enable the play button.")
        XCTAssertEqual(action.targetSeconds, policyResult.correctedExposureSeconds)
        XCTAssertTrue(
            action.isOutsideManufacturerGuidance,
            "The action state must preserve the outside-manufacturer-guidance basis so the start path can stamp it on the timer identity."
        )
    }
}
