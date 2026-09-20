// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class FilterWheelAccessibilityAdjustmentTests: XCTestCase {
    func testIncrementSkipsMountedItemAndSelectsNextAvailableRow() {
        let nd3 = selection("nd3")
        let nd6 = selection("nd6")
        let nd10 = selection("nd10")
        let cpl = selection("cpl", choice: .cplLoss(1))
        let options = [
            option(nd3),
            option(nd6),
            option(nd10, rejection: .itemAlreadyMounted),
            option(cpl),
        ]

        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: cpl,
                direction: .decrement,
                options: options
            ),
            .selection(nd6)
        )
    }

    func testAdjustmentSkipsMultipleConsecutiveUnavailableRows() {
        let current = selection("current")
        let overCap = selection("over-cap")
        let mounted = selection("mounted")
        let available = selection("available")
        let options = [
            option(current),
            option(overCap, rejection: .exceedsTotalLimit),
            option(mounted, rejection: .itemAlreadyMounted),
            option(available),
        ]

        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: current,
                direction: .increment,
                options: options
            ),
            .selection(available)
        )
    }

    func testNoAvailableCandidatePreservesNearestLocalizedReason() {
        let current = selection("current")
        let mounted = selection("mounted")
        let overCap = selection("over-cap")
        let options = [
            option(current),
            option(mounted, rejection: .itemAlreadyMounted),
            option(overCap, rejection: .exceedsTotalLimit),
        ]

        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: current,
                direction: .increment,
                options: options
            ),
            .unavailable(.itemAlreadyMounted)
        )
        XCTAssertEqual(
            FilterWheelPresenter.rejectionText(for: .itemAlreadyMounted),
            String(localized: "Already mounted on this camera")
        )
    }

    /// FILTER-A11Y-004: an ordinary end of the wheel — no rejected
    /// candidate caused the stop — is a boundary with its own localized
    /// reason, never a fabricated item conflict.
    func testAdjustmentDoesNotWrapAtEitherBoundaryAndReportsABoundary() {
        let first = selection("first")
        let last = selection("last")
        let options = [option(first), option(last)]

        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: first,
                direction: .decrement,
                options: options
            ),
            .boundary
        )
        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: last,
                direction: .increment,
                options: options
            ),
            .boundary
        )
        XCTAssertEqual(
            FilterWheelPresenter.boundaryText(),
            String(localized: "No more filters in this direction")
        )
    }

    /// Skipped unavailable rows followed by the end of the wheel report
    /// the actual rejection that prevented progress, not a boundary.
    func testSkippedCandidatesBeforeTheEndReportTheRejectionNotABoundary() {
        let current = selection("current")
        let overCap = selection("over-cap")
        let options = [option(current), option(overCap, rejection: .exceedsTotalLimit)]

        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: current,
                direction: .increment,
                options: options
            ),
            .unavailable(.exceedsTotalLimit)
        )
        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: current,
                direction: .decrement,
                options: options
            ),
            .boundary,
            "The other direction has no candidate at all."
        )
    }

    func testDecrementSkipsOverCapCandidate() {
        let available = selection("available")
        let overCap = selection("over-cap")
        let current = selection("current")
        let options = [
            option(available),
            option(overCap, rejection: .exceedsTotalLimit),
            option(current),
        ]

        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: current,
                direction: .decrement,
                options: options
            ),
            .selection(available)
        )
    }

    func testMissingCommittedRowReportsExistingUnavailableReason() {
        XCTAssertEqual(
            FilterWheelAccessibilityAdjustment.outcome(
                from: selection("missing"),
                direction: .increment,
                options: [option(selection("available"))]
            ),
            .unavailable(.unresolvedSelection)
        )
        XCTAssertEqual(
            FilterWheelPresenter.rejectionText(for: .unresolvedSelection),
            String(localized: "Filter not available")
        )
    }

    private func selection(
        _ id: String,
        choice: FilterRowChoice = .fixed
    ) -> FilterWheelSelection {
        .item(FilterRowSelection(itemID: FilterItemID(rawValue: id), choice: choice))
    }

    private func option(
        _ selection: FilterWheelSelection,
        rejection: FilterStackRejection? = nil
    ) -> FilterWheelRowOption {
        FilterWheelRowOption(
            row: ResolvedFilterRow(
                selection: selection,
                contributionStops: 0,
                registeredStops: 0,
                item: nil
            ),
            unavailability: rejection
        )
    }
}
