import XCTest
@testable import PTimer
import PTimerKit

final class TargetShutterPresenterTests: XCTestCase {
    // MARK: - Display state composition

    func testInactiveTargetProducesUnavailableDisplayState() {
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: nil,
            comparisonSource: .adjustedShutter(60)
        )

        XCTAssertEqual(state, .unavailable(.inactive))
    }

    func testZeroTargetProducesUnavailableDisplayState() {
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: 0,
            comparisonSource: .adjustedShutter(60)
        )

        XCTAssertEqual(state, .unavailable(.inactive))
    }

    func testNonFiniteTargetProducesUnavailableDisplayState() {
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: .infinity,
            comparisonSource: .adjustedShutter(60)
        )

        XCTAssertEqual(state, .unavailable(.inactive))
    }

    func testActiveTargetWithUnavailableComparisonPreservesTarget() throws {
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: 1200,
            comparisonSource: .unavailable
        )

        guard case .available(let availableState) = state else {
            return XCTFail("Expected available state with unavailable comparison")
        }

        XCTAssertEqual(availableState.targetSeconds, 1200)
        XCTAssertNil(availableState.comparison)
        XCTAssertNil(availableState.stopDifference)
    }

    func testDigitalWorkflowComparesAgainstAdjustedShutter() throws {
        // 120s vs 60s: target is +1 stop longer.
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: 120,
            comparisonSource: .adjustedShutter(60)
        )

        guard case .available(let availableState) = state,
              let comparison = availableState.comparison,
              let stopDifference = availableState.stopDifference else {
            return XCTFail("Expected available state with quantified comparison")
        }

        XCTAssertEqual(comparison.label, "Adjusted Shutter")
        XCTAssertEqual(comparison.seconds, 60)
        XCTAssertEqual(stopDifference.kind, .longerThanComparison)
        XCTAssertEqual(stopDifference.stops, 1, accuracy: 0.001)
        XCTAssertEqual(stopDifference.formattedText, "+1 stops")
    }

    func testFilmComparisonHasReadableLabel() throws {
        // 6m vs 5m: target is shorter than 1 stop. Comparison label
        // exposes the workflow context — `Corrected Exposure` here.
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: 360,
            comparisonSource: .correctedExposure(300)
        )

        guard case .available(let availableState) = state,
              let comparison = availableState.comparison else {
            return XCTFail("Expected available state with quantified comparison")
        }

        XCTAssertEqual(comparison.label, "Corrected Exposure")
    }

    func testFilmWorkflowComparesAgainstCorrectedExposure() throws {
        // 18m vs 22m: target is shorter by ~0.29 stops (log2(18/22)).
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: 18 * 60,
            comparisonSource: .correctedExposure(22 * 60)
        )

        guard case .available(let availableState) = state,
              let comparison = availableState.comparison,
              let stopDifference = availableState.stopDifference else {
            return XCTFail("Expected available state with quantified comparison")
        }

        XCTAssertEqual(comparison.label, "Corrected Exposure")
        XCTAssertEqual(comparison.seconds, 22 * 60)
        XCTAssertEqual(stopDifference.kind, .shorterThanComparison)
        XCTAssertEqual(stopDifference.stops, log2(18.0 / 22.0), accuracy: 0.001)
    }

    func testComparisonValueZeroFallsBackToUnavailableComparison() throws {
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: 60,
            comparisonSource: .adjustedShutter(0)
        )

        guard case .available(let availableState) = state else {
            return XCTFail("Expected available state")
        }

        XCTAssertEqual(availableState.targetSeconds, 60)
        XCTAssertNil(availableState.comparison)
        XCTAssertNil(availableState.stopDifference)
    }

    func testComparisonValueNonFiniteFallsBackToUnavailableComparison() throws {
        let state = TargetShutterPresenter.makeDisplayState(
            targetSeconds: 60,
            comparisonSource: .correctedExposure(.nan)
        )

        guard case .available(let availableState) = state else {
            return XCTFail("Expected available state")
        }

        XCTAssertNil(availableState.comparison)
        XCTAssertNil(availableState.stopDifference)
    }

    // MARK: - Stop difference formatting

    func testStopDifferenceMatchWhenWithinEpsilon() {
        let result = TargetShutterPresenter.formatStopDifference(0.001)

        XCTAssertEqual(result.kind, .match)
        XCTAssertEqual(result.formattedText, "0 stops")
    }

    func testStopDifferenceExactZeroIsMatch() {
        let result = TargetShutterPresenter.formatStopDifference(0)

        XCTAssertEqual(result.kind, .match)
        XCTAssertEqual(result.formattedText, "0 stops")
    }

    func testStopDifferencePositiveOneThirdSnapsToFraction() {
        let result = TargetShutterPresenter.formatStopDifference(1.0 / 3.0)

        XCTAssertEqual(result.kind, .longerThanComparison)
        // Magnitudes < 1 use singular `stop`; the fraction is the
        // Unicode vulgar one-third glyph (U+2153).
        XCTAssertEqual(result.formattedText, "+\u{2153} stop")
    }

    func testStopDifferenceNegativeTwoThirdsSnapsToFraction() {
        let result = TargetShutterPresenter.formatStopDifference(-2.0 / 3.0)

        XCTAssertEqual(result.kind, .shorterThanComparison)
        // Negative sign is the Unicode minus (U+2212), magnitude is
        // the vulgar two-thirds glyph (U+2154); singular `stop`.
        XCTAssertEqual(result.formattedText, "\u{2212}\u{2154} stop")
    }

    func testStopDifferenceWholeStopRendersAsInteger() {
        let result = TargetShutterPresenter.formatStopDifference(2)

        XCTAssertEqual(result.kind, .longerThanComparison)
        XCTAssertEqual(result.formattedText, "+2 stops")
    }

    func testStopDifferenceMixedFractionRenders() {
        let result = TargetShutterPresenter.formatStopDifference(1.0 + 1.0 / 3.0)

        XCTAssertEqual(result.kind, .longerThanComparison)
        // `1⅓` — whole part 1, vulgar one-third glyph; plural form.
        XCTAssertEqual(result.formattedText, "+1\u{2153} stops")
    }

    func testStopDifferenceNearOneThirdSnapsToOneThird() {
        // 0.36 sits ~0.027 from 1/3 — within the third-snap epsilon,
        // so it should snap to ⅓ rather than render as 0.36.
        let result = TargetShutterPresenter.formatStopDifference(0.36)

        XCTAssertEqual(result.kind, .longerThanComparison)
        XCTAssertEqual(result.formattedText, "+\u{2153} stop")
    }

    func testStopDifferenceRoundingToZeroThirdsIsTreatedAsMatch() {
        // 0.14 stops sits between 0 and 1/3 — the third-snap rounds
        // it to 0 thirds. Anything that snaps to 0 must surface as
        // a match (`0 stops` without a signed sign), never as the
        // awkward `+0 stops` / `−0 stops` shape that the result
        // section's arrow would otherwise pair with.
        let positive = TargetShutterPresenter.formatStopDifference(0.14)
        XCTAssertEqual(positive.kind, .match)
        XCTAssertEqual(positive.formattedText, "0 stops")

        let negative = TargetShutterPresenter.formatStopDifference(-0.14)
        XCTAssertEqual(negative.kind, .match)
        XCTAssertEqual(negative.formattedText, "0 stops")
    }

    func testStopDifferenceNonFiniteFallsBackToMatchString() {
        let result = TargetShutterPresenter.formatStopDifference(.nan)

        XCTAssertEqual(result.kind, .match)
        XCTAssertEqual(result.formattedText, "0 stops")
    }

    /// Boundary invariant: NEVER emit a signed `+0 stops` / `−0 stops`
    /// string. The view pairs the kind with an arrow icon, so a
    /// signed-zero string would render as `↑ +0 stops` / `↓ −0 stops`
    /// — meaningless. Sweeping a range of values around the snap-to-0
    /// zone confirms the invariant holds in both directions.
    func testStopDifferenceNeverEmitsSignedZeroAcrossSnapZone() {
        let cases: [Double] = [
            -0.16, -0.12, -0.08, -0.04, -0.001,
            0, 0.001, 0.04, 0.08, 0.12, 0.16,
        ]
        for value in cases {
            let result = TargetShutterPresenter.formatStopDifference(value)
            XCTAssertFalse(
                result.formattedText.contains("+0"),
                "Stop diff for \(value) must not emit a signed `+0`; got \(result.formattedText)"
            )
            XCTAssertFalse(
                result.formattedText.contains("\u{2212}0"),
                "Stop diff for \(value) must not emit a signed `−0`; got \(result.formattedText)"
            )
            XCTAssertFalse(
                result.formattedText.contains("-0"),
                "Stop diff for \(value) must not emit a hyphen-prefixed `-0`; got \(result.formattedText)"
            )
        }
    }
}
