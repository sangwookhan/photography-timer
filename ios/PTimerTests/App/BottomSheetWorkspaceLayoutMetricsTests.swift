import XCTest
@testable import PTimer

final class BottomSheetWorkspaceLayoutMetricsTests: XCTestCase {
    // MARK: - Rail-stable reservation invariants

    /// Workspace budget does not vary with timer presence — the
    /// rail's footprint is reserved unconditionally.
    func testWorkspaceBudgetIsTimerPresenceIndependent() {
        let workspaceArea: CGFloat = 751

        let budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: workspaceArea
        )
        let expected = workspaceArea
            - ExposureWorkspaceLayoutMetrics.timerStripBottomMargin
            - ExposureWorkspaceLayoutMetrics.timerStripHeight
            - ExposureWorkspaceLayoutMetrics.pageMarkerToStripGap
            - ExposureWorkspaceLayoutMetrics.pageMarkerHeight
            - ExposureWorkspaceLayoutMetrics.workspaceMarkerGap

        XCTAssertEqual(budget, expected)
    }

    /// Budget is a pure subtraction from the workspace area.
    func testWorkspaceBudgetIsLinearInWorkspaceArea() {
        let small = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: 700
        )
        let large = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: 800
        )

        XCTAssertEqual(large - small, 100)
    }

    /// Marker sits above the rail's reserved band.
    func testPageMarkerOffsetSitsAboveReservedRailBand() {
        let expected = ExposureWorkspaceLayoutMetrics.timerStripBottomMargin
            + ExposureWorkspaceLayoutMetrics.timerStripHeight
            + ExposureWorkspaceLayoutMetrics.pageMarkerToStripGap

        XCTAssertEqual(
            ExposureWorkspaceLayoutMetrics.pageMarkerBottomOffset(),
            expected
        )
    }

    /// Marker offset is stable across repeated calls.
    func testPageMarkerOffsetIsStable() {
        let offsets = (0..<8).map { _ in
            ExposureWorkspaceLayoutMetrics.pageMarkerBottomOffset()
        }

        XCTAssertEqual(Set(offsets).count, 1)
    }

    func testTimerStripBottomOffsetMeasuresFromTrimmedBottomEdge() {
        XCTAssertEqual(
            ExposureWorkspaceLayoutMetrics.timerStripBottomOffset(),
            ExposureWorkspaceLayoutMetrics.timerStripBottomMargin
        )
    }

    /// Rail band matches the compact card viewport height exactly.
    func testTimerRailHeightMatchesCompactCardViewport() {
        XCTAssertEqual(
            ExposureWorkspaceLayoutMetrics.timerStripHeight,
            BottomSheetCompactDockMetrics.viewportHeight
        )
    }

    /// Workspace + marker gap + marker + marker-to-rail gap + rail
    /// + rail margin partitions the trimmed area without gap or
    /// overlap, and adding both safe areas equals the device
    /// screen height.
    func testWorkspaceMarkerRailPartitionsTrimmedRegionExactly() {
        let topSafeArea: CGFloat = 59
        let bottomSafeArea: CGFloat = 34
        let workspaceArea: CGFloat = 844 - topSafeArea - bottomSafeArea

        let workspaceHeight = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: workspaceArea
        )

        let trimmedTotal = workspaceHeight
            + ExposureWorkspaceLayoutMetrics.workspaceMarkerGap
            + ExposureWorkspaceLayoutMetrics.pageMarkerHeight
            + ExposureWorkspaceLayoutMetrics.pageMarkerToStripGap
            + ExposureWorkspaceLayoutMetrics.timerStripHeight
            + ExposureWorkspaceLayoutMetrics.timerStripBottomMargin

        XCTAssertEqual(trimmedTotal, workspaceArea)
        XCTAssertEqual(trimmedTotal + topSafeArea + bottomSafeArea, 844)
    }

    /// Marker top edge sits exactly `workspaceMarkerGap` below the
    /// workspace bottom — neither overlapping nor floating away.
    func testPageMarkerSitsBelowWorkspaceNotInsideIt() {
        let workspaceArea: CGFloat = 751
        let workspaceHeight = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: workspaceArea
        )
        let markerBottomFromTop = workspaceArea
            - ExposureWorkspaceLayoutMetrics.pageMarkerBottomOffset()
        let markerTopFromTop = markerBottomFromTop
            - ExposureWorkspaceLayoutMetrics.pageMarkerHeight

        XCTAssertGreaterThanOrEqual(markerBottomFromTop, workspaceHeight)
        XCTAssertEqual(
            markerTopFromTop,
            workspaceHeight + ExposureWorkspaceLayoutMetrics.workspaceMarkerGap
        )
    }

    // MARK: - Device viewport sanity

    /// iPhone 17 budget falls into the compact tier — not regular.
    func testIPhone17FallsIntoCompactTier() {
        let area: CGFloat = 844 - 59 - 34
        let budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: area
        )
        let regularFloor = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .regular)
        let compactFloor = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .compact)

        XCTAssertGreaterThanOrEqual(budget, compactFloor)
        XCTAssertLessThan(budget, regularFloor)
    }

    func testIPhone17ViewportFitsDenseWorkspace() {
        let area: CGFloat = 844 - 59 - 34
        let dense = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .dense)

        let budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            workspaceArea: area
        )

        XCTAssertGreaterThanOrEqual(budget, dense)
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
        // HeaderView card: title line + film selector row + optional
        // reset row + inter-row spacings + outer card padding.
        let titleApprox: CGFloat = 30
        let filmRowApprox: CGFloat = 75
        let resetRowContribution: CGFloat = includesResetRow
            ? (18 + style.headerContentSpacing)
            : 0
        let headerInner = titleApprox
            + style.headerContentSpacing
            + filmRowApprox
            + resetRowContribution
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
        let targetRowApprox: CGFloat = includesTargetShutterRow
            ? (max(17, style.timerActionSize + 4))
            : 0
        let targetCard = includesTargetShutterRow
            ? (targetRowApprox + 2 * style.sectionCardPadding)
            : 0

        return headerCard + variableCard + resultCard + targetCard
    }
}
