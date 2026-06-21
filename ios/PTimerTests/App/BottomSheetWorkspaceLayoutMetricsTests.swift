// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
@testable import PTimer

final class BottomSheetWorkspaceLayoutMetricsTests: XCTestCase {

    /// iPhone 17 budget lands in the compact tier (at/above the compact
    /// floor, below the regular floor) and clears the dense minimum —
    /// the compact/dense fallback boundary guard.
    func testIPhone17BudgetUsesCompactTierAndFitsDenseMinimum() {
        let area: CGFloat = 844 - 59 - 34
        let budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: area
        )
        let regularFloor = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .regular)
        let compactFloor = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .compact)
        let denseFloor = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .dense)

        XCTAssertGreaterThanOrEqual(budget, compactFloor)
        XCTAssertLessThan(budget, regularFloor)
        XCTAssertGreaterThanOrEqual(budget, denseFloor)
    }

    /// Compact-tier intrinsic for the worst case (film result
    /// hierarchy + Target Shutter active + Reset row) fits within
    /// the compact floor plus the page Spacer's slack.
    func testCompactTierIntrinsicFitsWorstCaseInsideCompactFloor() {
        let style = ExposureWorkspaceMainLayoutStyle.compact
        let intrinsic = Self.estimatedPageIntrinsicHeight(
            style: style,
            includesFilmResultHierarchy: true,
            includesTargetShutterRow: true,
            includesResetRow: true
        )
        let compactFloor = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .compact)

        XCTAssertLessThanOrEqual(
            intrinsic,
            compactFloor + style.resultFlowSpacerMinLength
        )
    }

    /// Worst-case page intrinsic fits the iPhone 17 budget after
    /// rail reservation.
    @MainActor
    func testWorstCasePageIntrinsicFitsIPhone17Budget() {
        let area: CGFloat = 844 - 59 - 34
        let budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: area
        )
        let style = ExposureWorkspaceMainLayoutStyle.compact
        let intrinsic = Self.estimatedPageIntrinsicHeight(
            style: style,
            includesFilmResultHierarchy: true,
            includesTargetShutterRow: true,
            includesResetRow: true
        )
        let pagePadding = style.topPadding + style.bottomPadding

        XCTAssertGreaterThanOrEqual(
            budget,
            intrinsic + pagePadding,
            "Worst-case page intrinsic (film + Target Shutter active + Reset row) must fit the iPhone 17 workspace budget."
        )
    }

    /// Estimated page-VStack intrinsic height derived from style
    /// constants. Mirrors `CameraSlotCalculatorPage`'s section
    /// stack so changes to style values propagate without
    /// re-deriving magic numbers.
    private static func estimatedPageIntrinsicHeight(
        style: ExposureWorkspaceMainLayoutStyle,
        includesFilmResultHierarchy: Bool,
        includesTargetShutterRow: Bool,
        includesResetRow: Bool
    ) -> CGFloat {
        // HeaderView card: title line + film selector row + inter-row
        // spacings + outer card padding. PTIMER-172 moved Reset onto the
        // title row (beside the title), so it no longer contributes a
        // separate row of height. `includesResetRow` is retained for
        // call-site clarity / worst-case intent but adds no height.
        _ = includesResetRow
        let titleApprox: CGFloat = 30
        let filmRowApprox: CGFloat = 75
        let headerInner = titleApprox
            + style.headerContentSpacing
            + filmRowApprox
        let headerCard = headerInner + 2 * style.sectionCardPadding

        // VariableSectionView: label + label spacing + picker + outer
        // card padding.
        let variableLabelApprox: CGFloat = 17
        let variableInner = variableLabelApprox
            + style.pickerLabelSpacing
            + style.pickerHeight
        let variableCard = variableInner + 2 * style.sectionCardPadding

        // ResultSectionView: film mode uses the filmResultCardMinHeight
        // floor (already includes resultBlockPadding); digital mode
        // sizes to its single result row plus that padding.
        let resultInnerBlock: CGFloat = includesFilmResultHierarchy
            ? style.filmResultCardMinHeight
            : (50 + 2 * style.resultBlockPadding)
        let resultCard = resultInnerBlock + 2 * style.sectionCardPadding

        // TargetShutterSectionView active row: HStack height ≈
        // max(label line, timer-action button) + outer card padding.
        // PTIMER-172 shrank the row's play button to timerActionSize - 8.
        let targetRowApprox: CGFloat = includesTargetShutterRow
            ? (max(17, style.timerActionSize - 8))
            : 0
        let targetCard = includesTargetShutterRow
            ? (targetRowApprox + 2 * style.sectionCardPadding)
            : 0

        return headerCard + variableCard + resultCard + targetCard
    }
}
