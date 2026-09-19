// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
@testable import PTimer

/// SHELL-011/012: density-tier eligibility is derived from each tier's
/// complete worst-case content budget — the same production estimate
/// the screen uses to pick a tier — never from a hand-tuned floor.
final class BottomSheetWorkspaceLayoutMetricsTests: XCTestCase {
    /// iPhone 17 (844 pt tall, 59 + 34 pt safe areas) and iPhone 17 Pro
    /// (874 pt, 62 + 34) workspace budgets after the rail reservation.
    private let iPhone17Budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(workspaceArea: 844 - 59 - 34)
    private let iPhone17ProBudget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(workspaceArea: 874 - 62 - 34)

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

    /// The 611 pt iPhone 17 workspace uses Dense, and Dense fits it.
    func testIPhone17BudgetUsesDenseAndDenseFits() {
        let style = ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: iPhone17Budget)
        XCTAssertEqual(iPhone17Budget, 611)
        XCTAssertEqual(style, .dense)
        XCTAssertLessThanOrEqual(ExposureWorkspaceMainLayoutStyle.dense.worstCaseContentBudget.total, iPhone17Budget)
    }

    /// SHELL-012 / FILTER-STACK-008 reference outcome (spec revision
    /// 56e381e2): with the status region reduced to one row, Compact's
    /// complete derived worst case fits the approximately 638 pt
    /// iPhone 17 Pro workspace, so the Pro renders Compact (one wheel at
    /// 26 pt, not Dense 19 pt); the approximately 720 pt iPhone 17 Pro
    /// Max workspace also qualifies for Compact.
    func testIPhone17ProAndIPhone17ProMaxUseCompact() {
        let compact = ExposureWorkspaceMainLayoutStyle.compact.worstCaseContentBudget.total
        XCTAssertEqual(iPhone17ProBudget, 638)
        XCTAssertLessThanOrEqual(compact, iPhone17ProBudget, "The worst film-result plus active-Target-Shutter composition fits Compact on the Pro.")
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: iPhone17ProBudget), .compact)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: iPhone17ProBudget).wheelRowValuePointSize(forNDWheelCount: 1), 26)

        let proMaxBudget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(workspaceArea: 956 - 62 - 34)
        XCTAssertEqual(proMaxBudget, 720)
        XCTAssertLessThanOrEqual(compact, proMaxBudget)
        XCTAssertEqual(ExposureWorkspaceLayoutMetrics.style(forAvailableHeight: proMaxBudget), .compact)
    }

    /// The derived budgets after the status region became one row
    /// (spec revision 56e381e2): about 793 / 636 / 582 points for
    /// Regular / Compact / Dense with the current style (previously
    /// 811 / 652 / 597 with the two-line region).
    func testDerivedBudgetsMatchTheApprovedReferenceValues() {
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.regular.worstCaseContentBudget.total, 793, accuracy: 1.5)
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.compact.worstCaseContentBudget.total, 636, accuracy: 1.5)
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.dense.worstCaseContentBudget.total, 582, accuracy: 1.5)
    }

    /// The status region is counted once, as exactly one caption row
    /// plus its padding — no stale second-line capacity anywhere in
    /// the budget (FILTER-STACK-008, spec revision 56e381e2).
    func testStatusRegionIsCountedOnceAsOneRow() {
        for style in [ExposureWorkspaceMainLayoutStyle.regular, .compact, .dense] {
            let budget = style.worstCaseContentBudget
            let oneRow = UIFont.preferredFont(
                forTextStyle: style.filterStatusRegionTextStyle,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
            ).lineHeight
            XCTAssertEqual(budget.statusRegion, style.filterStatusRegionHeight, "\(style): the budget reads the style's region height.")
            XCTAssertEqual(style.filterStatusRegionHeight, oneRow + 2 * style.filterStatusRegionVerticalPadding, accuracy: 0.001, "\(style): one caption row plus padding.")
            XCTAssertLessThan(style.filterStatusRegionHeight, 2 * oneRow, "\(style): no room for a second line.")
            XCTAssertEqual(
                budget.variableCard,
                budget.pickerHeader + budget.pickerLabelSpacing + budget.wheelLabelRow + budget.picker + budget.wheelBodySpacing + budget.statusRegion + 2 * budget.cardPadding,
                accuracy: 0.001,
                "\(style): the region appears exactly once in the variable card."
            )
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
