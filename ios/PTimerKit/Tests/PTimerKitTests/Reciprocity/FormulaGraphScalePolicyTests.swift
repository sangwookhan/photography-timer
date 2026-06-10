import XCTest
import PTimerKit

final class FormulaGraphScalePolicyTests: XCTestCase {
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
    func testUsesT1ForNormalInputs() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.scaleTier, .t1, "240 s plus a corrected exposure of ~302 s must stay inside the 1 h tier.")
        // Viewport lower bound is profile-stable (one decade below
        // 1 s for Provia 100F's wide threshold) so the same frame
        // covers every normal-tier input. Upper bound stays tier-
        // driven.
        XCTAssertEqual(graph.xRange.lowerBound, 0.01, accuracy: 1e-9)
        XCTAssertEqual(graph.xRange.upperBound, 3_600, accuracy: 1e-9)
        XCTAssertEqual(graph.yRange.lowerBound, 0.01, accuracy: 1e-9)
        XCTAssertEqual(graph.yRange.upperBound, 3_600, accuracy: 1e-9)
        XCTAssertFalse(graph.isBeyondVisibleRange)
    }

    @MainActor
    func testUsesT2OrT3WhenFormulaPredictionExceedsOneHour() throws {
        // formula(3000) ≈ 128 × (3000/128)^1.3676 ≈ 8200 s, > 1 h →
        // pushes the graph past T1 into T2 (or higher if the y also
        // exceeds T2).
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 3_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertNotEqual(graph.scaleTier, .t1, "Predicted y above 1 h must escape T1.")
        XCTAssertTrue(
            graph.scaleTier == .t2 || graph.scaleTier == .t3,
            "Expected T2 or T3 for a 3000 s metered input; got \(String(describing: graph.scaleTier))."
        )
        XCTAssertFalse(graph.isBeyondVisibleRange)
    }

    @MainActor
    func testBeyondOneHundredHoursStaysAtT3WithOverflowIndicator() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 500_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.scaleTier, .t3, "Inputs past T3.upperBound must stay pinned to T3.")
        // T3 caps the upper bound; the profile-stable lower bound
        // is unchanged from the T1 frame so the no-correction band
        // stays visible even when long inputs bump the upper tier.
        XCTAssertEqual(graph.xRange.lowerBound, 0.01, accuracy: 1e-9)
        XCTAssertEqual(graph.xRange.upperBound, 360_000, accuracy: 1e-9, "xRange upper must be capped at T3 even for very large inputs.")
        XCTAssertEqual(graph.yRange.lowerBound, 0.01, accuracy: 1e-9)
        XCTAssertEqual(graph.yRange.upperBound, 360_000, accuracy: 1e-9, "yRange upper must be capped at T3 even for very large inputs.")
        XCTAssertTrue(graph.isBeyondVisibleRange, "isBeyondVisibleRange must trip for current values past T3.")
    }

    @MainActor
    func testFormulaCurveDoesNotExceedSelectedTier() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 500_000)
        let graph = try XCTUnwrap(displayState.graph)
        let maxSample = try XCTUnwrap(graph.sourcePoints.map(\.meteredExposureSeconds).max())
        XCTAssertLessThanOrEqual(
            maxSample,
            FilmModeDetailsGraphScaleTier.t3.upperBoundSeconds,
            "The formula curve must not be sampled past the tier upper bound."
        )
    }

    @MainActor
    func testSourceMarkersAndBoundaryStayWithinSelectedTier() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
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
    func testAxisTicksExtendTierTicksWithSubSecondLabels() throws {
        // Tier ticks anchor the axis from 1 s upward. With the
        // stable sub-second viewport the leading edge sits below
        // 1 s, so the axis prepends a sub-second tick (e.g.
        // "1/10s") to the tier's ticks. The user-visible labels
        // therefore extend the tier set; they no longer match it
        // exactly.
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)
        let tier = try XCTUnwrap(graph.scaleTier)

        let xLabels = graph.xAxisTicks.map(\.label)
        let tierLabels = tier.axisTicks.map(\.label)
        XCTAssertTrue(xLabels.contains("1h"),
                      "T1 axis must contain the 1h label.")
        for tierLabel in tierLabels {
            XCTAssertTrue(xLabels.contains(tierLabel),
                          "Tier-derived label '\(tierLabel)' must remain in the rendered axis tick set.")
        }
        XCTAssertGreaterThan(xLabels.count, tierLabels.count,
                             "Axis tick set must extend below 1 s when the viewport leading edge is sub-second.")
    }
}
