import XCTest
import PTimerKit

final class BottomSheetWorkspaceCompactProgressTests: XCTestCase {
    /// Table-driven compact-progress contract. One row per duration
    /// scale (seconds, sixty-four-seconds, eight-minute,
    /// thirty-four-minute, multi-hour) that exercises the layer
    /// selection policy: how many layers are visible, which layers
    /// are nil, and the expected fraction on each visible layer at
    /// the timer's current "remaining" point.
    func testCompactProgressLayerSelectionForRepresentativeDurationScales() throws {
        for expectation in makeCompactProgressLayerExpectations() {
            let snapshot = makeBottomSheetSnapshot(from: [expectation.timer])
            let item = bottomSheetTryUnwrapCompactItem(from: snapshot)

            XCTAssertEqual(
                item.visibleLayerCount,
                expectation.visibleLayerCount,
                "[\(expectation.label)] visibleLayerCount mismatch"
            )
            try assertOriginalScaleLayer(matches: expectation, on: item)
            try assertSixtyMinuteLayer(matches: expectation, on: item)
            XCTAssertEqual(
                item.sixtySecondLayer.fraction,
                expectation.expectedSixtySecondFraction,
                accuracy: 0.001,
                "[\(expectation.label)] sixtySecondLayer.fraction mismatch"
            )
        }
    }

    private struct CompactProgressLayerExpectation {
        let label: String
        let timer: RunningTimerItem
        let visibleLayerCount: Int
        let expectedOriginalScaleFraction: Double?
        let expectedSixtyMinuteFraction: Double?
        let expectedSixtySecondFraction: Double
    }

    private func makeCompactProgressLayerExpectations() -> [CompactProgressLayerExpectation] {
        [
            CompactProgressLayerExpectation(
                label: "short (seconds scale)",
                timer: bottomSheetSecondsScaleTimer(),
                visibleLayerCount: 1,
                expectedOriginalScaleFraction: nil,
                expectedSixtyMinuteFraction: nil,
                expectedSixtySecondFraction: 25.0 / 60.0
            ),
            CompactProgressLayerExpectation(
                label: "64-second (sixty-second + sixty-minute)",
                timer: bottomSheetMinuteScaleTimer(),
                visibleLayerCount: 2,
                expectedOriginalScaleFraction: nil,
                expectedSixtyMinuteFraction: 54.0 / 3600.0,
                expectedSixtySecondFraction: 54.0 / 60.0
            ),
            CompactProgressLayerExpectation(
                label: "eight-minute",
                timer: bottomSheetEightMinuteScaleTimer(),
                visibleLayerCount: 2,
                expectedOriginalScaleFraction: nil,
                expectedSixtyMinuteFraction: 478.0 / 3600.0,
                expectedSixtySecondFraction: 58.0 / 60.0
            ),
            CompactProgressLayerExpectation(
                label: "thirty-four-minute",
                timer: bottomSheetThirtyFourMinuteScaleTimer(),
                visibleLayerCount: 2,
                expectedOriginalScaleFraction: nil,
                expectedSixtyMinuteFraction: 2048.0 / 3600.0,
                expectedSixtySecondFraction: 8.0 / 60.0
            ),
            CompactProgressLayerExpectation(
                label: "long-running (original-scale + minute + second)",
                timer: bottomSheetHourScaleTimer(),
                visibleLayerCount: 3,
                expectedOriginalScaleFraction: 2.0 / 24.0,
                expectedSixtyMinuteFraction: 1.0,
                expectedSixtySecondFraction: 1.0
            ),
        ]
    }

    private func assertOriginalScaleLayer(
        matches expectation: CompactProgressLayerExpectation,
        on item: BottomSheetCompactItem
    ) throws {
        guard let expectedFraction = expectation.expectedOriginalScaleFraction else {
            XCTAssertNil(item.originalScaleLayer, "[\(expectation.label)] expected no original-scale layer")
            return
        }
        let layer = try XCTUnwrap(
            item.originalScaleLayer,
            "[\(expectation.label)] expected an original-scale layer"
        )
        XCTAssertEqual(
            layer.fraction,
            expectedFraction,
            accuracy: 0.001,
            "[\(expectation.label)] originalScaleLayer.fraction mismatch"
        )
    }

    private func assertSixtyMinuteLayer(
        matches expectation: CompactProgressLayerExpectation,
        on item: BottomSheetCompactItem
    ) throws {
        guard let expectedFraction = expectation.expectedSixtyMinuteFraction else {
            XCTAssertNil(item.sixtyMinuteLayer, "[\(expectation.label)] expected no 60-minute layer")
            return
        }
        let layer = try XCTUnwrap(
            item.sixtyMinuteLayer,
            "[\(expectation.label)] expected a 60-minute layer"
        )
        XCTAssertEqual(
            layer.fraction,
            expectedFraction,
            accuracy: 0.001,
            "[\(expectation.label)] sixtyMinuteLayer.fraction mismatch"
        )
    }

    func testCompactVisibleLayerCountPolicyBoundaries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let timer59 = RunningTimerItem(
            id: UUID(), order: 1, name: "59s", basisSummary: "", duration: 59,
            startDate: now, endDate: now.addingTimeInterval(59),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let item59 = BottomSheetWorkspaceSnapshot.make(
            from: [timer59],
            formatRemaining: { _ in "" },
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        ).compactItems[0]
        XCTAssertEqual(item59.visibleLayerCount, 1)

        let timer60 = RunningTimerItem(
            id: UUID(), order: 1, name: "60s", basisSummary: "", duration: 60,
            startDate: now, endDate: now.addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let item60 = BottomSheetWorkspaceSnapshot.make(
            from: [timer60],
            formatRemaining: { _ in "" },
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        ).compactItems[0]
        XCTAssertEqual(item60.visibleLayerCount, 2)

        let timer3599 = RunningTimerItem(
            id: UUID(), order: 1, name: "3599s", basisSummary: "", duration: 3599,
            startDate: now, endDate: now.addingTimeInterval(3599),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let item3599 = BottomSheetWorkspaceSnapshot.make(
            from: [timer3599],
            formatRemaining: { _ in "" },
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        ).compactItems[0]
        XCTAssertEqual(item3599.visibleLayerCount, 2)

        let timer3600 = RunningTimerItem(
            id: UUID(), order: 1, name: "3600s", basisSummary: "", duration: 3600,
            startDate: now, endDate: now.addingTimeInterval(3600),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let item3600 = BottomSheetWorkspaceSnapshot.make(
            from: [timer3600],
            formatRemaining: { _ in "" },
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        ).compactItems[0]
        XCTAssertEqual(item3600.visibleLayerCount, 3)
    }

    func testCompactProgressUsesExactFractionsForComplexRemainingTimes() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let timer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Complex Timer",
            basisSummary: "...",
            duration: 120,
            startDate: now.addingTimeInterval(-35),
            endDate: now.addingTimeInterval(85),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )

        let snapshot = makeBottomSheetSnapshot(from: [timer])
        let item = bottomSheetTryUnwrapCompactItem(from: snapshot)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 25.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressStaysFrozenForPausedTimer() throws {
        let snapshot = makeBottomSheetSnapshot(from: [bottomSheetPausedProgressTimer()])
        let item = bottomSheetTryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 45.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 45.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressSettlesAtCompleteForCompletedTimer() throws {
        let snapshot = makeBottomSheetSnapshot(from: [bottomSheetCompletedProgressTimer()])
        let item = bottomSheetTryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 0, accuracy: 0.001)
    }

    func testCompactProgressClampsOriginalScaleLayerForMultiDayTimer() throws {
        let snapshot = makeBottomSheetSnapshot(from: [bottomSheetLongDurationTimer()])
        let item = bottomSheetTryUnwrapCompactItem(from: snapshot)
        let originalScaleLayer = try XCTUnwrap(item.originalScaleLayer)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 3)
        XCTAssertEqual(originalScaleLayer.fraction, 1, accuracy: 0.001)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 1, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 1, accuracy: 0.001)
    }
}
