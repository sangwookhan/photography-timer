// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
@testable import PTimer

/// SHELL-011/012: density-tier eligibility is derived from each tier's
/// complete worst-case content budget — the same production estimate
/// the screen uses to pick a tier — never from a hand-tuned floor.
final class BottomSheetWorkspaceLayoutMetricsTests: XCTestCase {
    /// iPhone 17 and iPhone 17 Pro share one body (402 x 874 pt, 62 + 34
    /// pt safe areas), so both have the same workspace budget after the
    /// rail reservation. A shorter 844 pt body (59 + 34 pt safe areas)
    /// covers the Dense floor.
    private let iPhone17Budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(workspaceArea: 874 - 62 - 34)
    private let iPhone17ProBudget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(workspaceArea: 874 - 62 - 34)
    private let shortPhoneBudget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(workspaceArea: 844 - 59 - 34)

    func testTierSelectionAndThresholdsUseTheProductionBudget() {
        for density in [ExposureWorkspaceLayoutDensity.regular, .compact, .dense] {
            XCTAssertEqual(
                ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: density),
                ExposureWorkspaceMainLayoutStyle(density: density).worstCaseContentBudget.total,
                "The floor is the derived budget, not a separate constant."
            )
        }
        let regular = ExposureWorkspaceMainLayoutStyle.regular.worstCaseContentBudget.total
        let compact = ExposureWorkspaceMainLayoutStyle.compact.worstCaseContentBudget.total
        let dense = ExposureWorkspaceMainLayoutStyle.dense.worstCaseContentBudget.total
        XCTAssertLessThan(dense, compact)
        XCTAssertLessThan(compact, regular)

        // Exactly the requirement selects its tier; one point less falls back.
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: regular), .regular)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: regular - 1), .compact)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: compact), .compact)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: compact - 1), .dense)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: dense), .dense)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: dense - 1), .dense, "Dense is the floor tier.")
    }

    /// The 611 pt workspace of a shorter 844 pt body uses Dense, and
    /// Dense fits it.
    func testShortPhoneBudgetUsesDenseAndDenseFits() {
        let style = ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: shortPhoneBudget)
        XCTAssertEqual(shortPhoneBudget, 611)
        XCTAssertEqual(style, .dense)
        XCTAssertLessThanOrEqual(ExposureWorkspaceMainLayoutStyle.dense.worstCaseContentBudget.total, shortPhoneBudget)
    }

    /// SHELL-012 / FILTER-STACK-008 reference outcome: with the status
    /// region one row tall and the Total's numerals at the ND numeral
    /// size, Compact's complete derived worst case still fits the 638 pt
    /// iPhone 17 / iPhone 17 Pro workspace, so both render Compact (one
    /// wheel at 26 pt, not Dense 19 pt); the approximately 720 pt
    /// iPhone 17 Pro Max workspace also qualifies for Compact.
    func testIPhone17AndIPhone17ProAndIPhone17ProMaxUseCompact() {
        let compact = ExposureWorkspaceMainLayoutStyle.compact.worstCaseContentBudget.total
        XCTAssertEqual(iPhone17Budget, 638)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: iPhone17Budget), .compact)
        XCTAssertEqual(iPhone17ProBudget, 638)
        XCTAssertLessThanOrEqual(compact, iPhone17ProBudget, "The worst film-result plus active-Target-Shutter composition fits Compact on the Pro.")
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: iPhone17ProBudget), .compact)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: iPhone17ProBudget).wheelRowValuePointSize(forNDWheelCount: 1), 26)

        let proMaxBudget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(workspaceArea: 956 - 62 - 34)
        XCTAssertEqual(proMaxBudget, 720)
        XCTAssertLessThanOrEqual(compact, proMaxBudget)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: proMaxBudget), .compact)
    }

    /// The derived budgets with the Total's numerals at the ND numeral
    /// size: about 795 / 637.6 / 579.3 points for Regular / Compact /
    /// Dense (previously 793 / 636 / 582 with a caption-sized Total).
    /// The region grows to the numerals' cap height and the gap above
    /// it shrinks from the body spacing to 2 pt.
    func testDerivedBudgetsMatchTheApprovedReferenceValues() {
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.regular.worstCaseContentBudget.total, 795, accuracy: 1.5)
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.compact.worstCaseContentBudget.total, 637.6, accuracy: 0.5)
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.dense.worstCaseContentBudget.total, 579.3, accuracy: 1.5)
    }

    /// The status region is counted once, as exactly one visual row —
    /// the taller of one caption row plus its padding and the Total's
    /// numeral cap height plus the caption descent — with no stale
    /// second-line capacity anywhere in the budget (FILTER-STACK-008).
    func testStatusRegionIsCountedOnceAsOneRow() {
        for style in [ExposureWorkspaceMainLayoutStyle.regular, .compact, .dense] {
            let budget = style.worstCaseContentBudget
            let oneRow = UIFont.preferredFont(
                forTextStyle: style.filterStatusRegionTextStyle,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
            ).lineHeight
            XCTAssertEqual(budget.statusRegion, style.filterStatusRegionHeight, "\(style): the budget reads the style's region height.")
            XCTAssertEqual(
                style.filterStatusRegionHeight,
                max(oneRow + 2 * style.filterStatusRegionVerticalPadding, style.filterStatusTotalReservedAscent + style.filterStatusRegionBaselineDescent),
                accuracy: 0.001,
                "\(style): one visual row."
            )
            XCTAssertLessThan(style.filterStatusRegionHeight, 2 * oneRow, "\(style): no room for a second line.")
            XCTAssertEqual(
                budget.variableCard,
                budget.pickerHeader + budget.pickerLabelSpacing + budget.wheelLabelRow + budget.picker + budget.wheelBodySpacing + budget.statusRegion + 2 * budget.cardPadding,
                accuracy: 0.001,
                "\(style): the region appears exactly once in the variable card."
            )
        }
    }

    /// FILTER-STACK-008: in every tier and for one to four occupied
    /// filter spaces, the Total's numerals are at least the ND numeral
    /// size of the same layout, and the fixed region reserves their cap
    /// height, so no layout clips them or resizes the row.
    func testTotalNumeralsMatchTheNDNumeralsAndFitTheRegion() {
        for style in [ExposureWorkspaceMainLayoutStyle.regular, .compact, .dense] {
            for count in 1...4 {
                let totalSize = style.filterStatusTotalValuePointSize(forOccupiedSpaceCount: count)
                XCTAssertGreaterThanOrEqual(totalSize, style.wheelRowValuePointSize(forNDWheelCount: count), "\(style), \(count) spaces")
                let base = UIFont.systemFont(ofSize: totalSize, weight: .semibold)
                let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: totalSize) } ?? base
                XCTAssertLessThanOrEqual(font.capHeight, style.filterStatusTotalReservedAscent, "\(style), \(count) spaces")
            }
        }
    }

    /// Changing a contributing style value moves the derived
    /// requirement by the same amount — there is no parallel formula.
    func testContributingValuesMoveTheDerivedRequirement() {
        let base = ExposureWorkspaceMainLayoutStyle.compact.worstCaseContentBudget
        var taller = base
        taller.picker += 10
        XCTAssertEqual(taller.total, base.total + 10, accuracy: 0.001)
        var wider = base
        wider.statusRegion += 6
        XCTAssertEqual(wider.total, base.total + 6, accuracy: 0.001)
        var padded = base
        padded.cardPadding += 1
        XCTAssertEqual(padded.total, base.total + 8, accuracy: 0.001, "Card padding counts twice on each of four cards.")
        var spaced = base
        spaced.headerContentSpacing += 2
        XCTAssertEqual(spaced.total, base.total + 4, accuracy: 0.001, "Header spacing separates the film row and the model row.")
    }

    /// Records the derived totals in the test log so a style change
    /// leaves a visible trace of the new requirements.
    func testDerivedTotalsAreReported() {
        for style in [ExposureWorkspaceMainLayoutStyle.regular, .compact, .dense] {
            let budget = style.worstCaseContentBudget
            XCTContext.runActivity(named: "\(style) budget") { activity in
                let attachment = XCTAttachment(string: """
                    total=\(budget.total) header=\(budget.headerCard) target=\(budget.targetCard) \
                    variable=\(budget.variableCard) result=\(budget.resultCard) \
                    titleRow=\(budget.headerTitleRow) filmLabel=\(budget.filmLabelRow) filmButton=\(budget.filmSelectorButton) \
                    modelRow=\(budget.modelRow) targetRow=\(budget.targetRow) spacer=\(budget.resultSpacer) \
                    padding=\(budget.topPadding + budget.bottomPadding)
                    """)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            XCTAssertGreaterThan(budget.total, 0)
            // Also on stdout so a plain `xcodebuild` log shows the totals.
            print("BUDGET_TOTALS \(style) total=\(budget.total) statusRegion=\(budget.statusRegion) picker=\(budget.picker) labelRow=\(budget.wheelLabelRow)")
        }
    }
}
