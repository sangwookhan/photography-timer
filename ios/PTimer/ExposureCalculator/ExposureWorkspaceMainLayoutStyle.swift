// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import PTimerCore
import PTimerKit
import UIKit

/// Density-driven layout knobs shared by the camera workspace, the
/// target shutter row, and the result section. Owns paddings,
/// spacings, font sizes, and the wheel-picker column layout that
/// keeps the ND-stop / shutter columns aligned across densities.
///
/// Lives in its own file so callers (CameraSlotCalculatorPage,
/// TargetShutterSectionView, the picker rows) can reach the style
/// without pulling in the entire ExposureCalculatorScreen.swift
/// surface.
enum ExposureWorkspaceMainLayoutStyle {
    case regular
    case compact
    case dense

    init(density: ExposureWorkspaceLayoutDensity) {
        switch density {
        case .regular:
            self = .regular
        case .compact:
            self = .compact
        case .dense:
            self = .dense
        }
    }

    var density: ExposureWorkspaceLayoutDensity {
        switch self {
        case .regular:
            return .regular
        case .compact:
            return .compact
        case .dense:
            return .dense
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular:
            return 18
        case .compact, .dense:
            return 16
        }
    }

    var topPadding: CGFloat {
        switch self {
        case .regular:
            return 14
        case .compact:
            return 6
        case .dense:
            return 6
        }
    }

    var bottomPadding: CGFloat {
        switch self {
        case .regular:
            return 6
        case .compact:
            return 2
        case .dense:
            return 2
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .regular:
            return 12
        case .compact:
            return 10
        case .dense:
            return 8
        }
    }

    var resultFlowSpacerMinLength: CGFloat {
        switch self {
        case .regular:
            return 14
        case .compact:
            return 10
        case .dense:
            return 8
        }
    }

    var sectionCardPadding: CGFloat {
        switch self {
        case .regular:
            return 13
        case .compact:
            return 11
        case .dense:
            return 9
        }
    }

    var sectionCornerRadius: CGFloat {
        switch self {
        case .regular:
            return 18
        case .compact, .dense:
            return 16
        }
    }

    var headerTitleFont: Font {
        switch headerTitleTextStyle {
        case .largeTitle:
            return .largeTitle.weight(.bold)
        case .title1:
            return .title.weight(.bold)
        default:
            return .title2.weight(.bold)
        }
    }

    /// Text style behind `headerTitleFont`; the content budget reads
    /// its line height so the title row is measured, not guessed.
    var headerTitleTextStyle: UIFont.TextStyle {
        switch self {
        case .regular:
            return .largeTitle
        case .compact:
            return .title1
        case .dense:
            return .title2
        }
    }

    /// Height of the inline segmented reciprocity-model selector shown
    /// under the film row for multi-model films (UISegmentedControl's
    /// intrinsic height); the worst-case header row.
    var reciprocityModelSelectorHeight: CGFloat {
        32
    }

    var bodySpacing: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact:
            return 6
        case .dense:
            return 6
        }
    }

    var headerContentSpacing: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact:
            return 4
        case .dense:
            return 4
        }
    }

    var pickerHeight: CGFloat {
        switch self {
        case .regular:
            return 164
        case .compact:
            return 108
        case .dense:
            return 92
        }
    }

    var pickerValueFont: Font {
        switch self {
        case .regular:
            return .system(size: pickerValuePointSize, weight: .bold, design: .rounded)
        case .compact:
            return .system(size: pickerValuePointSize, weight: .bold, design: .rounded)
        case .dense:
            return .system(size: pickerValuePointSize, weight: .semibold, design: .rounded)
        }
    }

    /// Numeric size of a single full-width wheel (Base Shutter alone
    /// beside one ND wheel).
    var pickerValuePointSize: CGFloat {
        switch self {
        case .regular:
            return 32
        case .compact:
            return 26
        case .dense:
            return 19
        }
    }

    var pickerUnitFont: Font {
        switch self {
        case .regular:
            return .footnote.weight(.medium)
        case .compact:
            return .caption.weight(.medium)
        case .dense:
            return .caption2.weight(.medium)
        }
    }

    var pickerOverlayUnitFont: Font {
        switch self {
        case .regular:
            return .system(size: 22, weight: .medium, design: .rounded)
        case .compact:
            return .system(size: 18, weight: .medium, design: .rounded)
        case .dense:
            return .system(size: 16, weight: .medium, design: .rounded)
        }
    }

    var pickerSelectionBandHeight: CGFloat {
        switch self {
        case .regular:
            return 42
        case .compact:
            return 36
        case .dense:
            return 30
        }
    }

    var resultPrimaryFont: Font {
        switch self {
        case .regular:
            return .system(size: 28, weight: .bold, design: .rounded)
        case .compact:
            return .system(size: 24, weight: .bold, design: .rounded)
        case .dense:
            return .system(size: 22, weight: .bold, design: .rounded)
        }
    }

    /// Primary duration font for the single-line result rows shared by
    /// No Film and Film modes (PTIMER-172). Smaller than
    /// `resultPrimaryFont` because the value now shares one horizontal
    /// line with a leading label, an optional seconds comparison, and
    /// the trailing timer affordance.
    var unifiedResultPrimaryFont: Font {
        switch self {
        case .regular:
            return .system(size: 21, weight: .semibold, design: .rounded)
        case .compact:
            return .system(size: 19, weight: .semibold, design: .rounded)
        case .dense:
            return .system(size: 18, weight: .semibold, design: .rounded)
        }
    }

    /// Fixed width of the leading label column in the shared result row
    /// (PTIMER-172). Sized to hold the intentional two-line English labels
    /// ("Adjusted / Shutter", "Corrected / Exposure") and, per PTIMER-183,
    /// the single-line localized labels (e.g. "ND 적용 셔터") without
    /// wrapping, so the label never competes with the value area for width
    /// and the primary duration gets a stable, dominant column.
    var resultLabelColumnWidth: CGFloat {
        switch self {
        case .regular:
            return 96
        case .compact:
            return 90
        case .dense:
            return 84
        }
    }

    /// Fixed width of the secondary seconds-comparison column in the
    /// shared result row (PTIMER-172). Reserved even when no seconds are
    /// shown so the primary duration's right edge stays anchored as wheel
    /// values cross the 60 s / 1 d thresholds; the seconds value shrinks
    /// or truncates within this column rather than pushing the primary.
    var resultSecondsColumnWidth: CGFloat {
        switch self {
        case .regular:
            return 64
        case .compact:
            return 58
        case .dense:
            return 54
        }
    }

    var resultBlockPadding: CGFloat {
        switch self {
        case .regular:
            return 12
        case .compact:
            return 8
        case .dense:
            return 8
        }
    }

    var resultActionSpacing: CGFloat {
        switch self {
        case .regular:
            return 12
        case .compact:
            return 10
        case .dense:
            return 8
        }
    }

    var filmResultRowMinHeight: CGFloat {
        // PTIMER-172: result rows are now a single horizontal line, so
        // the floor only needs to clear the trailing timer button
        // rather than reserve room for a stacked label-over-value.
        switch self {
        case .regular:
            return 44
        case .compact:
            return 40
        case .dense:
            return 38
        }
    }

    /// Minimum height of the result-section *inner* block (after
    /// `resultBlockPadding` is applied). Sized to fit three film
    /// rows at their respective row-level minimums plus dividers,
    /// body spacings, and the corrected-exposure row's extra
    /// height. Acts as a hard floor for the result card under
    /// sibling compression so the inner content never overflows
    /// the section's clipShape.
    var filmResultCardMinHeight: CGFloat {
        let rowsAtFloor = 3 * filmResultRowMinHeight
        let dividers: CGFloat = 2
        let interRowSpacings = 4 * bodySpacing
        let correctedExposureExtra = correctedExposureValueMinHeight - filmResultRowMinHeight
        let innerContent = rowsAtFloor
            + dividers
            + interRowSpacings
            + max(0, correctedExposureExtra)
        return innerContent + 2 * resultBlockPadding
    }

    var correctedExposureValueMinHeight: CGFloat {
        // PTIMER-172: the corrected-exposure row is single-line like the
        // others, so it no longer needs extra height over a result row.
        filmResultRowMinHeight
    }

    var timerActionSize: CGFloat {
        switch self {
        case .regular:
            return 44
        case .compact:
            return 42
        case .dense:
            return 40
        }
    }

    var timerActionIconSize: CGFloat {
        switch self {
        case .regular:
            return 15
        case .compact:
            return 14
        case .dense:
            return 13
        }
    }

    var resultTopSpacerMinLength: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact:
            return 8
        case .dense:
            return 6
        }
    }

    var inputColumnSpacing: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact, .dense:
            return 8
        }
    }

    var pickerLabelSpacing: CGFloat {
        switch self {
        case .regular:
            return 6
        case .compact, .dense:
            return 5
        }
    }

    var workspaceSeparation: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact:
            return 8
        case .dense:
            return 6
        }
    }

    /// Distance from the top of the camera workspace area down to the
    /// film selector overlay's top edge. Mirrors the offset the
    /// overlay had when it was scoped inside the workspace; used by
    /// the screen-level renderer to drop the overlay underneath the
    /// camera title area.
    var selectorOverlayTopPadding: CGFloat {
        switch self {
        case .regular:
            return 112
        case .compact:
            return 98
        case .dense:
            return 86
        }
    }

    var pickerSelectionBandContentTrailingInset: CGFloat {
        switch self {
        case .regular:
            return 14
        case .compact:
            return 12
        case .dense:
            return 10
        }
    }

    var pickerSelectionBandHorizontalInset: CGFloat {
        10
    }

    /// Value font for a wheel inside a multi-wheel ND stack
    /// (PTIMER-199). Columns narrow as wheels multiply, so the font
    /// steps down with the count — paired with
    /// `stackedNDValueHorizontalPadding(forWheelCount:)` so glyphs
    /// stay fully legible instead of relying on minimum-scale
    /// squeezing alone.
    func stackedNDValueFont(forWheelCount count: Int) -> Font {
        let size = stackedNDValuePointSize(forWheelCount: count)
        switch self {
        case .regular:
            return .system(size: size, weight: count >= 4 ? .semibold : .bold, design: .rounded)
        case .compact:
            return .system(size: size, weight: count >= 3 ? .semibold : .bold, design: .rounded)
        case .dense:
            return .system(size: size, weight: .semibold, design: .rounded)
        }
    }

    /// The established numeric-value hierarchy for stacked wheels
    /// (FILTER-STACK-007): Regular 28 / 24 / 20, Compact 23 / 20 / 17,
    /// Dense 18 / 16 / 14 points for two / three / four actual wheels.
    /// Base Shutter and every filter wheel share it at rest and while
    /// moving; the type rail fits around it, never the other way round.
    func stackedNDValuePointSize(forWheelCount count: Int) -> CGFloat {
        switch self {
        case .regular:
            switch count {
            case ...2: return 28
            case 3: return 24
            default: return 20
            }
        case .compact:
            switch count {
            case ...2: return 23
            case 3: return 20
            default: return 17
            }
        case .dense:
            switch count {
            case ...2: return 18
            case 3: return 16
            default: return 14
            }
        }
    }

    /// Horizontal padding partner of `stackedNDValueFont` — shrinks
    /// with the wheel count so narrow columns spend their width on
    /// glyphs.
    func stackedNDValueHorizontalPadding(forWheelCount count: Int) -> CGFloat {
        count >= 3 ? 1 : 3
    }

    /// Spacing between the filter wheels (and Plus) inside the ND
    /// group — deliberately narrower than the outer column spacing so
    /// three or four columns keep their width for complete registered
    /// representations (FILTER-STACK-007).
    var filterWheelSpacing: CGFloat {
        switch self {
        case .regular:
            return 4
        case .compact, .dense:
            return 3
        }
    }

    /// Height of the persistent type / mode label row above every
    /// wheel viewport (FILTER-STACK-007). The Base Shutter column keeps
    /// an equal blank row, composed exactly like a filter column, so
    /// every wheel shares one vertical axis (`wheelColumnGeometry`).
    var filterWheelLabelRowHeight: CGFloat {
        switch self {
        case .regular:
            return 16
        case .compact, .dense:
            return 14
        }
    }

    var filterWheelLabelFont: Font {
        .system(size: 10, weight: .semibold, design: .rounded)
    }

    /// Width of the type-color rail at the leading edge of every picker
    /// row (FILTER-STACK-007). Drawn as an overlay inside the row's
    /// existing geometry, so the centered numeric column, the picker
    /// bounds, and the touch center never move.
    var filterWheelTypeRailWidth: CGFloat {
        3
    }

    /// Inset of the rail from the row's leading edge.
    var filterWheelTypeRailInset: CGFloat {
        2
    }

    /// Height of the rail inside the 32 pt row.
    var filterWheelTypeRailHeight: CGFloat {
        20
    }

    /// Height reserved for the single status region under the wheel
    /// row (FILTER-STACK-008) at the default text size: exactly one
    /// caption row plus its ordinary vertical padding (the view scales
    /// it with Dynamic Type). The removed second line reserves no
    /// capacity; its height returns to the wheel row and to the
    /// density budget. Content changes stay inside this one row, so no
    /// picker or touch center moves.
    var filterStatusRegionHeight: CGFloat {
        Self.lineHeight(filterStatusRegionTextStyle) + 2 * filterStatusRegionVerticalPadding
    }

    /// Vertical padding above and below the one status row.
    var filterStatusRegionVerticalPadding: CGFloat {
        1
    }

    var filterStatusRegionTextStyle: UIFont.TextStyle {
        switch self {
        case .regular, .compact:
            return .caption1
        case .dense:
            return .caption2
        }
    }

    var filterStatusRegionFont: Font {
        switch self {
        case .regular, .compact:
            return .caption
        case .dense:
            return .caption2
        }
    }

    /// THE wheel-row value font (user rule, 2026-07-15): every wheel
    /// on the main screen — Base Shutter AND all ND wheels — always
    /// renders its values at the SAME size for a given wheel count.
    /// One wheel keeps the established `pickerValueFont`; stacks step
    /// the shared size down with the ND wheel count.
    func wheelRowValueFont(forNDWheelCount count: Int) -> Font {
        count <= 1 ? pickerValueFont : stackedNDValueFont(forWheelCount: count)
    }

    /// Point size behind `wheelRowValueFont(forNDWheelCount:)` — the
    /// one numeric size Base Shutter and every filter wheel render for
    /// a density and wheel count, settled or moving.
    func wheelRowValuePointSize(forNDWheelCount count: Int) -> CGFloat {
        count <= 1 ? pickerValuePointSize : stackedNDValuePointSize(forWheelCount: count)
    }

    /// Width cap for the Base Shutter column while the ND stack holds
    /// 3+ wheels (PTIMER-199, user feedback): the default 50/50 split
    /// starves the ND columns while Base Shutter reads fine at about
    /// HALF its two-column width — the value text scales down within
    /// the column when "1/8000" runs tight. `nil` keeps the equal
    /// split at 1–2 wheels so the established two-column look is
    /// untouched.
    func baseShutterColumnMaxWidth(forNDWheelCount count: Int) -> CGFloat? {
        guard count >= 3 else {
            return nil
        }
        // Tightened for the Filter Set contract: the released width
        // goes to the filter columns so `ND1000` / `OD 0.9` / `CPL 1.5`
        // stay complete; `1/8000` still fits at the shared value font.
        switch self {
        case .regular:
            return count == 3 ? 96 : 76
        case .compact:
            return count == 3 ? 90 : 72
        case .dense:
            return count == 3 ? 84 : 68
        }
    }

    fileprivate func pickerColumnLayout(for column: CalculatorPickerColumn) -> PickerColumnLayout {
        switch (self, column) {
        case (.regular, .ndStop):
            return PickerColumnLayout(
                unitTextWidth: 88,
                unitTextTrailingInset: 6,
                valueAlignmentPolicy: .offsetBeforeWideUnitLabel,
                valueAlignmentCompensation: -8
            )
        case (.compact, .ndStop):
            return PickerColumnLayout(
                unitTextWidth: 72,
                unitTextTrailingInset: 5,
                valueAlignmentPolicy: .offsetBeforeWideUnitLabel,
                valueAlignmentCompensation: -8
            )
        case (.dense, .ndStop):
            return PickerColumnLayout(
                unitTextWidth: 60,
                unitTextTrailingInset: 4,
                valueAlignmentPolicy: .offsetBeforeWideUnitLabel,
                valueAlignmentCompensation: -8
            )
        case (.regular, .shutter):
            return PickerColumnLayout(
                unitTextWidth: 30,
                unitTextTrailingInset: 3,
                valueAlignmentPolicy: .offsetBeforeCompactUnitGlyph,
                valueAlignmentCompensation: 1
            )
        case (.compact, .shutter):
            return PickerColumnLayout(
                unitTextWidth: 26,
                unitTextTrailingInset: 2,
                valueAlignmentPolicy: .offsetBeforeCompactUnitGlyph,
                valueAlignmentCompensation: 0
            )
        case (.dense, .shutter):
            return PickerColumnLayout(
                unitTextWidth: 22,
                unitTextTrailingInset: 2,
                valueAlignmentPolicy: .offsetBeforeCompactUnitGlyph,
                valueAlignmentCompensation: 0
            )
        }
    }
}

private enum CalculatorPickerColumn {
    case ndStop
    case shutter
}

private enum PickerValueAlignmentPolicy {
    case offsetBeforeWideUnitLabel
    case offsetBeforeCompactUnitGlyph
}

private struct PickerColumnLayout {
    let unitTextWidth: CGFloat
    let unitTextTrailingInset: CGFloat
    let valueAlignmentPolicy: PickerValueAlignmentPolicy
    let valueAlignmentCompensation: CGFloat

    func valueTextTrailingInset(selectionBandContentTrailingInset: CGFloat) -> CGFloat {
        let baseInset = unitTextWidth + selectionBandContentTrailingInset
        switch valueAlignmentPolicy {
        case .offsetBeforeWideUnitLabel:
            return baseInset + valueAlignmentCompensation
        case .offsetBeforeCompactUnitGlyph:
            return baseInset + unitTextTrailingInset + valueAlignmentCompensation
        }
    }
}

/// Two-column shutter / ND-filter wheel-picker block. Lives in this
/// file because it composes the two pickers below using
/// `pickerColumnLayout(for:)`, which is fileprivate.
struct VariableSectionView: View {
    @Binding var baseShutter: Double
    /// Per-wheel active contributions (count and font ladder).
    let ndFilterSteps: [NDStep]
    /// The mixed Filter Stack's wheels and their resolved rows
    /// (Filter Set contract), parallel to `ndFilterSteps`.
    let filterWheels: [FilterWheel]
    let filterRows: [ResolvedFilterRow]
    /// Per-wheel BINDING selections (pending over committed).
    let displaySelections: [FilterWheelSelection]
    /// Per-wheel selection the persistent label follows: the live row
    /// at the touch center while moving, else the display selection.
    let trackedSelections: [FilterWheelSelection]
    let ndFilterWheelIDs: [Int]
    let shutterSpeeds: [Double]
    let rowOptionsForWheel: (Int) -> [FilterWheelRowOption]
    let filterSetColor: (FilterSource) -> FilterSetColor?
    let filterSourceName: (FilterSource) -> String
    let formatShutter: (TimeInterval) -> String
    let ndNotationMode: NDNotationMode
    let onSelectNotationMode: (NDNotationMode) -> Void
    let onContinuousBaseShutterChange: (Double) -> Void
    let onBaseShutterInteractionEnd: () -> Void
    /// Owned-picker measurements (PTIMER-199 v2), keyed by wheel
    /// IDENTITY and stamped with the generation they were issued
    /// under. The ViewModel's state machine judges them; the view
    /// layer only forwards.
    let onNDWheelRowObserved: (Int, FilterWheelSelection, Int) -> Void
    let onNDWheelSelected: (Int, FilterWheelSelection, Int) -> Void
    let onNDWheelTouchBegan: (Int, Int) -> Void
    let onNDWheelTouchEnded: (Int) -> Void
    let onNDWheelOverscrollReleased: (Int, Int) -> Void
    let isNDWheelResolved: (Int) -> Bool
    let areNDWheelsInteractive: Bool
    let ndWheelGeneration: Int
    let showsAddFilterWheelControl: Bool
    /// No wheel moving, reshaping, or touched: adding may proceed.
    let isFilterInteractionQuiet: Bool
    /// Adds one wheel for the given source (FILTER-PLUS-003).
    let onAddFilterWheel: (FilterSource) -> Void
    /// Plus wheel inputs (FILTER-PLUS): sources in order, the settled
    /// source, and the reason a given source cannot add (`nil` when it
    /// can) — asked for the source the Plus displays.
    let filterSources: [FilterSource]
    let selectedFilterSource: FilterSource
    let addUnavailabilityText: (FilterSource) -> String?
    let onManageFilterSets: () -> Void
    /// The wheel currently in motion (expanded label + live
    /// contribution) for the status region.
    let movingWheelStatus: MovingWheelStatus?
    let filterRejectionNotice: FilterRejectionNotice?
    /// The settled source summary the idle status region shows for a
    /// stack holding a Filter Set wheel (FILTER-STACK-008); composed by
    /// the view model, `nil` for a Standard-only stack.
    let idleSourceSummary: [FilterStatusSourceSummaryItem]?
    let ndStackTotalDisplayState: NDStackTotalDisplayState
    let style: ExposureWorkspaceMainLayoutStyle

    /// Candidate source while the Plus wheel is being browsed
    /// (FILTER-PLUS-002); rendered in the status region below the
    /// row, never over a picker.
    @State private var browsingSource: FilterSource?

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            HStack(alignment: .top, spacing: style.inputColumnSpacing) {
                ShutterSelectionRow(
                    baseShutter: $baseShutter,
                    shutterSpeeds: shutterSpeeds,
                    formatShutter: formatShutter,
                    onContinuousSelectionChange: onContinuousBaseShutterChange,
                    onInteractionEnd: onBaseShutterInteractionEnd,
                    ndWheelCount: ndFilterSteps.count,
                    labelRowHeight: style.filterWheelLabelRowHeight,
                    pickerHeight: style.pickerHeight,
                    style: style
                )
                // 3+ ND wheels: cap the Base column so the narrower
                // ND columns get the released width (PTIMER-199).
                .frame(
                    maxWidth: style.baseShutterColumnMaxWidth(
                        forNDWheelCount: ndFilterSteps.count
                    ) ?? .infinity
                )

                NDFilterGroupView(
                    ndFilterSteps: ndFilterSteps,
                    filterWheels: filterWheels,
                    filterRows: filterRows,
                    displaySelections: displaySelections,
                    trackedSelections: trackedSelections,
                    ndFilterWheelIDs: ndFilterWheelIDs,
                    rowOptionsForWheel: rowOptionsForWheel,
                    filterSetColor: filterSetColor,
                    filterSourceName: filterSourceName,
                    ndNotationMode: ndNotationMode,
                    onSelectNotationMode: onSelectNotationMode,
                    onWheelRowObserved: onNDWheelRowObserved,
                    onWheelSelected: onNDWheelSelected,
                    onWheelTouchBegan: onNDWheelTouchBegan,
                    onWheelTouchEnded: onNDWheelTouchEnded,
                    onWheelOverscrollReleased: onNDWheelOverscrollReleased,
                    isWheelResolved: isNDWheelResolved,
                    areWheelsInteractive: areNDWheelsInteractive,
                    ndWheelGeneration: ndWheelGeneration,
                    showsAddFilterWheelControl: showsAddFilterWheelControl,
                    isFilterInteractionQuiet: isFilterInteractionQuiet,
                    onAddFilterWheel: onAddFilterWheel,
                    filterSources: filterSources,
                    selectedFilterSource: selectedFilterSource,
                    addUnavailabilityText: addUnavailabilityText,
                    onManageFilterSets: onManageFilterSets,
                    onBrowsingSourceChanged: { browsingSource = $0 },
                    totalDisplayState: ndStackTotalDisplayState,
                    pickerHeight: style.pickerHeight,
                    style: style
                )
            }

            // The ONE stable status region (FILTER-STACK-008): below
            // both columns, outside every picker viewport, with fixed
            // height so its content never moves a wheel. At idle a
            // stack with a Filter Set wheel keeps its source summary
            // and total visible at secondary emphasis.
            FilterStatusRegionView(
                content: FilterStatusRegionPresenter.content(
                    moving: movingWheelStatus,
                    browsingSourceName: browsingSource.map(filterSourceName),
                    rejection: filterRejectionNotice,
                    total: ndStackTotalDisplayState,
                    idleSourceSummary: idleSourceSummary
                ),
                style: style
            )
        }
        .sectionCardStyle(style: style)
    }
}

/// Renders the single stable status region: two caption lines in a
/// fixed-height slot. Content, priority, and the one-at-a-time rule
/// come from `FilterStatusRegionPresenter`; timing and stale-task
/// safety come from `FilterStatusRegionViewModel`. The persistent
/// idle source summary renders at secondary emphasis (system secondary
/// label color, regular weight) so moving and rejection content stand
/// out at normal emphasis. The slot keeps its geometry while empty, so
/// pickers and touch centers never move. Assistive technology reaches
/// the leading text and the complete total as two separate elements
/// (FILTER-A11Y-005): the total is focusable directly, without first
/// listening through the source summary or item detail.
struct FilterStatusRegionView: View {
    let content: FilterStatusRegionContent?
    let style: ExposureWorkspaceMainLayoutStyle

    @StateObject private var controller = FilterStatusRegionViewModel()
    /// The two caption lines grow with Dynamic Type; the reserved
    /// height grows with them so the persistent summary and total stay
    /// complete at every supported standard text size. The region is
    /// below every picker, so growing it never moves a touch center.
    @ScaledMetric(relativeTo: .caption) private var textScale: CGFloat = 1

    /// Held detail (moving, browsing, rejection) renders straight from
    /// the composed content, so it commits in the same render pass as
    /// the persistent type label and the centered row it describes
    /// (FILTER-STACK-007); routed through the controller's published
    /// state it would trail them by one render. The controller keeps
    /// the settle linger and the idle total's fade, which only ever
    /// govern content that is not held detail.
    private var displayedContent: FilterStatusRegionContent? {
        isShowingHeldDetail ? content : controller.visibleContent
    }

    /// Held detail also switches without the 0.15 s crossfade, so a
    /// row crossing never shows the previous candidate's text fading
    /// under the new one; the fade stays for the idle summary and the
    /// total, which do not race the wheel.
    private var isShowingHeldDetail: Bool {
        guard let content else { return false }
        return content.isHeld && !content.isPersistentIdle
    }

    var body: some View {
        // A concrete container (not `Group`): the region must exist even
        // while it shows nothing, so `onAppear` applies the first
        // content and the reserved height never collapses.
        VStack(alignment: .leading, spacing: 0) {
            if let visible = displayedContent {
                // Exactly one visual row in every state (FILTER-STACK-
                // 007/008): the leading text yields space and truncates
                // at its tail; the total keeps layout priority and is
                // never truncated. No second line, no font shrinking.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let leading = leadingText(for: visible), let leadingLabel = visible.primaryText {
                        leading
                            .font(style.filterStatusRegionFont.weight(visible.isSecondaryEmphasis ? .regular : .semibold))
                            .foregroundStyle(primaryStyle(for: visible))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // The complete leading text, however much
                            // of it the row could show.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(leadingLabel))
                            .accessibilityIdentifier("filter-status-leading")
                        Spacer(minLength: 0)
                    }
                    if let trailing = visible.secondaryText {
                        Text(trailing)
                            .font(style.filterStatusRegionFont)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                            // Its own focusable target: Total is reached
                            // directly, never behind the leading text.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(trailing))
                            .accessibilityIdentifier("filter-status-total")
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: style.filterStatusRegionHeight * max(1, textScale), alignment: .top)
        .clipped()
        .animation(isShowingHeldDetail ? nil : .easeInOut(duration: 0.15), value: displayedContent)
        .onAppear { controller.apply(content) }
        .onChange(of: content) { _, newValue in
            controller.apply(newValue)
        }
        .accessibilityIdentifier("filter-status-region")
    }

    /// The leading text of the row: the idle source summary with its
    /// source-color cues, or the detail / reason text. `nil` for the
    /// Standard-only idle total, which keeps its existing leading
    /// placement.
    private func leadingText(for content: FilterStatusRegionContent) -> Text? {
        if content.isPersistentIdle, let items = content.idleSourceSummary {
            return summaryText(items)
        }
        return content.primaryText.map { Text($0) }
    }

    /// `● NiSi kit · ● Lee holder ×2 · Standard` as one `Text`, so the
    /// whole summary truncates once at its tail instead of squeezing
    /// each name; each Filter Set name carries its user-selected
    /// source-color cue, Standard stays text only.
    private func summaryText(_ items: [FilterStatusSourceSummaryItem]) -> Text {
        items.enumerated().reduce(Text(verbatim: "")) { partial, entry in
            var piece = entry.offset > 0 ? Text(verbatim: " · ") : Text(verbatim: "")
            if let color = entry.element.color {
                piece = piece
                    + Text(Image(systemName: "circle.fill"))
                        .font(.system(size: 6))
                        .baselineOffset(2)
                        .foregroundColor(Color.filterSet(color))
                    + Text(verbatim: " ")
            }
            return partial + piece + Text(entry.element.text)
        }
    }

    private func primaryStyle(for content: FilterStatusRegionContent) -> Color {
        if content.isWarning {
            return .orange
        }
        return content.isSecondaryEmphasis ? Color.secondary : Color.primary
    }
}

/// ND filter group: the ND header row (title + notation toggle)
/// spanning the ND wheel area, above a horizontal row of 1–4 ND
/// wheels plus the edge Add control (PTIMER-199).
///
/// Add/remove paths (PTIMER-199 v2): the Plus wheel adds a wheel from
/// the displayed source; removal is self-cleaning (§4.2.2) plus the
/// overscroll-past-zero gesture (§4.2.3) — there are no menus. With a
/// screen reader, Add, source stepping, and Filter Set management live
/// on the focusable Plus element itself (FILTER-A11Y-001); automatic
/// cleanup has no separate Remove action and announces an actual
/// removal once (FILTER-STACK-006).
private struct NDFilterGroupView: View {
    let ndFilterSteps: [NDStep]
    let filterWheels: [FilterWheel]
    let filterRows: [ResolvedFilterRow]
    /// Display selections (pending/live over committed, §4.5): what
    /// the wheel bindings and the idle re-sync target — a mid-epoch
    /// selection must never be visually reverted before the set
    /// commit lands.
    let displaySelections: [FilterWheelSelection]
    let trackedSelections: [FilterWheelSelection]
    /// Stable identity parallel to `ndFilterSteps` (PTIMER-199 (S)4.3)
    /// so the ForEach keys wheels by wheel, not by position; a
    /// commit-sort reorder moves each stable wheel directly to its new
    /// position with its value, label, and cue attached
    /// (FILTER-STACK-005).
    let ndFilterWheelIDs: [Int]
    let rowOptionsForWheel: (Int) -> [FilterWheelRowOption]
    let filterSetColor: (FilterSource) -> FilterSetColor?
    let filterSourceName: (FilterSource) -> String
    let ndNotationMode: NDNotationMode
    let onSelectNotationMode: (NDNotationMode) -> Void
    let onWheelRowObserved: (Int, FilterWheelSelection, Int) -> Void
    let onWheelSelected: (Int, FilterWheelSelection, Int) -> Void
    let onWheelTouchBegan: (Int, Int) -> Void
    let onWheelTouchEnded: (Int) -> Void
    let onWheelOverscrollReleased: (Int, Int) -> Void
    let isWheelResolved: (Int) -> Bool
    let areWheelsInteractive: Bool
    let ndWheelGeneration: Int
    let showsAddFilterWheelControl: Bool
    let isFilterInteractionQuiet: Bool
    /// Adds one wheel for the given source (FILTER-PLUS-003).
    let onAddFilterWheel: (FilterSource) -> Void
    let filterSources: [FilterSource]
    let selectedFilterSource: FilterSource
    let addUnavailabilityText: (FilterSource) -> String?
    let onManageFilterSets: () -> Void
    /// Candidate source while Plus is browsed, reported to the parent
    /// which renders it in the status region (FILTER-PLUS-002).
    let onBrowsingSourceChanged: (FilterSource?) -> Void
    let totalDisplayState: NDStackTotalDisplayState
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

    /// ForEach data pairing each wheel's stable id with its current
    /// position. Falls back to positional identity if the two arrays
    /// ever disagree in length (defensive; they mutate together).
    private struct NDWheelSlot: Identifiable {
        let id: Int
        let index: Int
    }

    private var wheelSlots: [NDWheelSlot] {
        ndFilterSteps.indices.map { index in
            NDWheelSlot(
                id: ndFilterWheelIDs.indices.contains(index) ? ndFilterWheelIDs[index] : index,
                index: index
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.pickerLabelSpacing) {
            HStack(spacing: 4) {
                // Title carries the group's weight; the selector labels
                // are intentionally smaller and compact so the control
                // does not dominate the header (PTIMER-187). The native
                // segmented control clips "Stops" in this half-width
                // area, so a compact custom toggle is used to match the
                // Android placement and keep all three labels readable.
                //
                // No long-press menus anywhere in the group (user
                // product decision, PTIMER-199 §4.2.5): removal is
                // handled by the self-cleaning rules and the
                // accessibility custom actions below.
                Text("ND Filter")
                    .font(.footnote.weight(.semibold))
                    .fixedSize()

                // Persistent Filter Set management entry
                // (FILTER-SET-001): stays reachable when four wheels
                // hide the Plus wheel. Compact glyph, 44 pt hit area.
                Button(action: onManageFilterSets) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18, height: 22)
                        // 18 × 22 glyph, 44 × 48 hit shape.
                        .contentShape(Rectangle().inset(by: -13))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Filter Sets"))
                .accessibilityHint(Text("Create, edit, and reorder your Filter Sets"))
                .accessibilityIdentifier("filter-sets-manage-button")

                Spacer(minLength: 4)

                NDNotationToggle(mode: ndNotationMode, onSelect: onSelectNotationMode)
                    .accessibilityIdentifier("nd-notation-mode-control")
            }
            .frame(height: pickerHeaderHeight)

            HStack(spacing: style.filterWheelSpacing) {
                ForEach(wheelSlots) { slot in
                    let index = slot.index
                    NDWheelView(
                        displaySelection: displaySelections.indices.contains(index)
                            ? displaySelections[index]
                            : filterWheels[index].selection,
                        trackedSelection: trackedSelections.indices.contains(index)
                            ? trackedSelections[index]
                            : filterWheels[index].selection,
                        committedRow: filterRows.indices.contains(index)
                            ? filterRows[index]
                            : ResolvedFilterRow(selection: filterWheels[index].selection, contributionStops: ndFilterSteps[index].stops, registeredStops: ndFilterSteps[index].stops, item: nil),
                        rowOptions: rowOptionsForWheel(index),
                        source: filterWheels[index].source,
                        sourceColor: filterSetColor(filterWheels[index].source),
                        sourceName: filterSourceName(filterWheels[index].source),
                        position: index + 1,
                        ndNotationMode: ndNotationMode,
                        wheelCount: ndFilterSteps.count,
                        isResolved: isWheelResolved(slot.id),
                        isInputEnabled: areWheelsInteractive,
                        generation: ndWheelGeneration,
                        onRowObserved: { onWheelRowObserved(slot.id, $0, $1) },
                        onSelected: { onWheelSelected(slot.id, $0, $1) },
                        onTouchBegan: { onWheelTouchBegan(slot.id, $0) },
                        onTouchEnded: { onWheelTouchEnded(slot.id) },
                        onOverscrollReleased: { onWheelOverscrollReleased(slot.id, $0) },
                        totalDisplayState: totalDisplayState,
                        pickerHeight: pickerHeight,
                        style: style
                    )
                    // Automatic cleanup (and manual overscroll/add)
                    // animate as fade + width collapse; siblings
                    // re-flow via the implicit count animation below.
                    .transition(.ndWheelCollapse)
                }

                if showsAddFilterWheelControl {
                    // Plus has no type label; keep its body aligned with
                    // the wheel viewports below the label row.
                    FilterSourcePlusControl(
                        sources: filterSources,
                        selectedSource: selectedFilterSource,
                        sourceName: filterSourceName,
                        sourceColor: filterSetColor,
                        pickerHeight: pickerHeight,
                        isInteractionQuiet: isFilterInteractionQuiet,
                        addUnavailabilityText: addUnavailabilityText,
                        onAdd: onAddFilterWheel,
                        onManage: onManageFilterSets,
                        onBrowsingChanged: onBrowsingSourceChanged
                    )
                    .padding(.top, style.filterWheelLabelRowHeight)
                }
            }
            // No overlay over the pickers: the expanded label, the
            // browsed source, a rejection reason, and the live total all
            // render in the single status region below the row
            // (FILTER-STACK-007/008).
            // Drives the wheel add/remove transitions (incl. the
            // delayed auto-removal fired from the view model, which
            // mutates state outside any withAnimation scope).
            .animation(.easeInOut(duration: 0.35), value: ndFilterSteps.count)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // A plain container: every assistive command lives on the
        // focusable elements inside it (each wheel's adjustable value,
        // the Plus element's Add / source / Manage actions, the header
        // button), never on this non-focusable group (FILTER-A11Y-001).
        .accessibilityElement(children: .contain)
        .accessibilityValue(accessibilityTotalValue)
    }

    /// The stack total stays in the accessibility tree regardless of
    /// the overlay's visual state (§4.6), e.g. "4 filters, total 19
    /// stops". Single wheel: no stack, no value.
    private var accessibilityTotalValue: Text {
        guard totalDisplayState.isVisibleCandidate else {
            return Text(verbatim: "")
        }
        return Text(
            "\(totalDisplayState.wheelCount) filters, total \(totalDisplayState.totalStopsText) stops"
        )
    }
}

/// Fade + width-collapse rendering for a wheel leaving (or joining)
/// the ND row (PTIMER-199 UX follow-up: delayed auto-removal).
private struct NDWheelCollapseModifier: ViewModifier {
    let collapsed: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: collapsed ? 0 : .infinity)
            .opacity(collapsed ? 0 : 1)
            .clipped()
    }
}

extension AnyTransition {
    /// Wheel removal collapses its width while fading; insertion is
    /// the reverse (grow + fade in).
    static var ndWheelCollapse: AnyTransition {
        .modifier(
            active: NDWheelCollapseModifier(collapsed: true),
            identity: NDWheelCollapseModifier(collapsed: false)
        )
    }
}

/// A single filter wheel picker column (value wheel + live-scroll
/// observer + unit selection band), header-less so the group above
/// can lay out 1–4 of them in one row (PTIMER-199). A Standard wheel
/// shows the ladder in the active notation; a Filter Set wheel shows
/// Empty plus its items' rows as centered numeric values, each with a
/// type-color rail at its leading edge, under a persistent full type /
/// mode label for the row at the touch center (FILTER-STACK-003/007).
/// Unavailable rows render dimmed; selecting one is refused at the set
/// commit and the wheel reverts.
private struct NDWheelView: View {
    /// The wheel's display selection (pending selection while the set
    /// commit is open, committed value otherwise).
    let displaySelection: FilterWheelSelection
    /// The row the persistent label follows: the live candidate at the
    /// touch center while moving, the settled row at rest
    /// (FILTER-STACK-007).
    let trackedSelection: FilterWheelSelection
    let committedRow: ResolvedFilterRow
    let rowOptions: [FilterWheelRowOption]
    let source: FilterSource
    let sourceColor: FilterSetColor?
    let sourceName: String
    /// 1-based position in the stack for assistive technology.
    let position: Int
    let ndNotationMode: NDNotationMode
    /// Wheels sharing the ND row (1–4). Above one wheel the values
    /// center, the per-wheel unit band text drops (the single-column
    /// band metrics push the value out of a narrow stacked column —
    /// PTIMER-199 R2 evidence), and fonts/paddings step down with the
    /// count so values stay legible in the narrower columns.
    let wheelCount: Int
    /// v2 state inputs: display enforcement only while resolved;
    /// input blocked during RESHAPING; generation stamps events.
    let isResolved: Bool
    let isInputEnabled: Bool
    let generation: Int
    let onRowObserved: (FilterWheelSelection, Int) -> Void
    let onSelected: (FilterWheelSelection, Int) -> Void
    let onTouchBegan: (Int) -> Void
    let onTouchEnded: () -> Void
    let onOverscrollReleased: (Int) -> Void
    /// The stack's current complete Total, spoken after the committed
    /// value so a successful assistive adjustment ends with the Total
    /// (FILTER-A11Y-005).
    let totalDisplayState: NDStackTotalDisplayState
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

    private var isCompact: Bool {
        wheelCount > 1
    }

    private var layout: PickerColumnLayout {
        style.pickerColumnLayout(for: .ndStop)
    }

    private var rowDisplays: [FilterWheelRowDisplay] {
        rowOptions.map { FilterWheelPresenter.rowDisplay(for: $0, notationMode: ndNotationMode) }
    }

    private var rows: [FilterWheelSelection] {
        rowOptions.map(\.selection)
    }

    /// The display selection must be one of the picker's rows; a
    /// pending selection that the barrier later refuses is still a
    /// valid row, so this only guards against transient mismatches.
    private var selectedRow: FilterWheelSelection {
        rows.contains(displaySelection) ? displaySelection : (rows.first ?? displaySelection)
    }

    /// Mode-dependent unit shown in the selection band (`stops` / `OD`
    /// / `ND`) for Standard wheels. Filter Set rows carry their own
    /// registered representation (`OD 0.9`, `ND1000`, `3 stops`), so
    /// the band shows no unit for them.
    private var unitText: String {
        switch source {
        case .standard:
            return NDNotationFormatter.display(for: committedRow.contributionStops.asNDStep, mode: ndNotationMode).unit
        case .filterSet:
            return ""
        }
    }

    private var committedDisplay: FilterWheelRowDisplay {
        FilterWheelPresenter.rowDisplay(for: committedRow, notationMode: ndNotationMode)
    }

    /// Display of the row the label tracks; falls back to the committed
    /// row for a transient selection the picker no longer offers.
    private var trackedDisplay: FilterWheelRowDisplay {
        rowDisplays.first { $0.selection == trackedSelection } ?? committedDisplay
    }

    var body: some View {
        VStack(spacing: 0) {
            // Persistent type / mode label immediately above the
            // viewport (FILTER-STACK-007): `ND`, `CPL`, `GND REC` /
            // `GND FULL`, or `EMPTY`, with the Filter Set color as an
            // adjacent redundant cue. Follows the candidate at the
            // touch center while the wheel moves.
            HStack(spacing: 3) {
                if let sourceColor {
                    Circle()
                        .fill(Color.filterSet(sourceColor))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(trackedDisplay.typeLabel)
                    .font(style.filterWheelLabelFont)
                    .foregroundStyle(.secondary)
                if let modeLabel = trackedDisplay.modeLabel {
                    Text(modeLabel)
                        .font(style.filterWheelLabelFont)
                        .foregroundStyle(.primary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: style.filterWheelLabelRowHeight)
            .accessibilityHidden(true)

            wheel
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(wheelAccessibilityLabel))
        // The dynamic value VoiceOver speaks after each successful
        // adjustment: item or Empty, type or mode, contribution, then
        // the current Total, once. Rejections and boundaries announce
        // their reason alone below and never change this value.
        .accessibilityValue(Text(FilterWheelPresenter.wheelAccessibilityValue(committed: committedDisplay, total: totalDisplayState)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                accessibilityAdjust(.increment)
            case .decrement:
                accessibilityAdjust(.decrement)
            @unknown default:
                break
            }
        }
    }

    private var wheel: some View {
        NDWheelPickerView(
            steps: rows,
            selectedStep: selectedRow,
            isCleanableRow: { selection in
                switch selection {
                case .standard(let step): return step.stops == 0
                case .empty: return true
                case .item: return false
                }
            },
            isResolved: isResolved,
            isInputEnabled: isInputEnabled,
            generation: generation,
            rowConfiguration: AnyHashable(NDWheelRowConfiguration(
                notationMode: ndNotationMode,
                wheelCount: wheelCount,
                displays: rowDisplays
            )),
            rowHeight: 32,
            rowContent: { selection in
                let display = rowDisplays.first { $0.selection == selection }
                    ?? FilterWheelPresenter.rowDisplay(
                        for: ResolvedFilterRow(selection: selection, contributionStops: 0, registeredStops: 0, item: nil),
                        notationMode: ndNotationMode
                    )
                NDStopPickerValue(
                    valueText: display.compactValueText,
                    typeRailColor: Color.filterType(display.typeCategory),
                    isDimmed: !display.isAvailable,
                    style: style,
                    layout: layout,
                    stackedWheelCount: isCompact ? wheelCount : nil
                )
                .accessibilityLabel(Text(rowAccessibilityText(display)))
            },
            onRowObserved: onRowObserved,
            onSelected: onSelected,
            onTouchBegan: onTouchBegan,
            onTouchEnded: onTouchEnded,
            onOverscrollReleased: onOverscrollReleased
        )
        .frame(maxWidth: .infinity)
        .frame(height: pickerHeight)
        .clipped()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            PickerUnitSelectionBand(
                unitText: isCompact ? "" : unitText,
                style: style,
                layout: layout
            )
        }
    }

    /// Stable wheel identity (FILTER-A11Y-001). The changing committed
    /// selection is exposed separately through `accessibilityValue`.
    private var wheelAccessibilityLabel: String {
        FilterWheelPresenter.wheelAccessibilityLabel(
            position: position,
            wheelCount: wheelCount,
            sourceName: sourceName
        )
    }

    private func rowAccessibilityText(_ display: FilterWheelRowDisplay) -> String {
        if let unavailabilityText = display.unavailabilityText {
            return "\(display.expandedLabelText), \(unavailabilityText)"
        }
        return display.expandedLabelText
    }

    private func accessibilityAdjust(_ direction: FilterWheelAdjustmentDirection) {
        let outcome = FilterWheelAccessibilityAdjustment.outcome(
            from: committedRow.selection,
            direction: direction,
            options: rowOptions
        )
        switch outcome {
        case .selection(let selection):
            onSelected(selection, generation)
        case .unavailable(let rejection):
            // Skipped candidates prevented progress: the actual reason.
            UIAccessibility.post(
                notification: .announcement,
                argument: FilterWheelPresenter.rejectionText(for: rejection)
            )
        case .boundary:
            // The plain end of the wheel, no rejected candidate.
            UIAccessibility.post(
                notification: .announcement,
                argument: FilterWheelPresenter.boundaryText()
            )
        }
    }
}

extension Color {
    /// The fixed semantic type palette behind every row's type-color
    /// rail (FILTER-STACK-007): ND blue, CPL amber/orange, GND a
    /// green-leaning teal, Empty neutral gray. Stable across Filter
    /// Sets, cameras, and appearances, and independent of the
    /// user-selected Filter Set color — a set may legitimately look
    /// like a type hue.
    static func filterType(_ category: FilterRowTypeCategory) -> Color {
        switch category {
        case .nd: return .blue
        case .cpl: return .orange
        case .gnd: return .filterTypeGND
        case .empty: return .gray
        }
    }

    /// GND rail color: a green-leaning teal, dynamic per appearance.
    /// System teal (hue about 195°) sits next to system blue on a faded
    /// row, so GND uses hue about 165° instead — light `#009D78`
    /// (0, 157, 120), dark `#3FCFA1` (63, 207, 161). Contrast against
    /// the picker card: about 3.6:1 on light `secondarySystemBackground`
    /// and about 8.4:1 on dark `secondarySystemBackground`, and the hue
    /// gap to ND blue (about 45°) survives the 30 % dimming of
    /// unavailable rows.
    static let filterTypeGND = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 63 / 255, green: 207 / 255, blue: 161 / 255, alpha: 1)
            : UIColor(red: 0, green: 157 / 255, blue: 120 / 255, alpha: 1)
    })
}

/// Opaque row-rendering key for the owned picker: any change to the
/// notation, the wheel count, or the row texts (an item rename, a new
/// unavailability) forces a locked reload.
private struct NDWheelRowConfiguration: Hashable {
    let notationMode: NDNotationMode
    let wheelCount: Int
    let displays: [FilterWheelRowDisplay]
}

private extension Double {
    var asNDStep: NDStep { NDStep(stops: self) }
}

/// Shared height for the two picker-column headers so the notation
/// control on the ND header does not push the ND wheel below the
/// shutter wheel (PTIMER-187).
private let pickerHeaderHeight: CGFloat = 30

/// One wheel column's vertical geometry (FILTER-STACK-007), in points
/// from the top of the header row. Base Shutter and every filter wheel
/// share it for a density and wheel count.
struct WheelColumnGeometry: Equatable {
    let headerHeight: CGFloat
    let labelSpacing: CGFloat
    let labelRowHeight: CGFloat
    let viewportHeight: CGFloat
    let selectionBandHeight: CGFloat
    /// The shared numeric size of the selected value.
    let valuePointSize: CGFloat

    var labelRowTop: CGFloat { headerHeight + labelSpacing }
    var viewportTop: CGFloat { labelRowTop + labelRowHeight }
    var viewportBottom: CGFloat { viewportTop + viewportHeight }
    /// The selection band is centered in the viewport; the picker's
    /// selected row, the value's baseline row, and the touch center all
    /// sit on it.
    var selectionBandCenter: CGFloat { viewportTop + viewportHeight / 2 }
    var selectionBandTop: CGFloat { selectionBandCenter - selectionBandHeight / 2 }
    var selectionBandBottom: CGFloat { selectionBandCenter + selectionBandHeight / 2 }
    var touchCenter: CGFloat { selectionBandCenter }
}

extension ExposureWorkspaceMainLayoutStyle {
    /// Line height of a text style at the default (Large) content size.
    /// Tier selection is a function of available height only
    /// (SHELL-011), so the budget deliberately ignores the live
    /// Dynamic Type setting.
    private static func lineHeight(_ textStyle: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(
            forTextStyle: textStyle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).lineHeight
    }

    /// This tier's complete worst-case visible content (SHELL-012),
    /// mirroring `CameraSlotCalculatorPage`: header card (title row,
    /// `Film` label, film selector button with its two text lines,
    /// model selector row), active Target Shutter card, variable card
    /// (picker header, wheel label row, picker, status region), film
    /// result card, page padding, and the required result spacer.
    /// Vertical geometry of one wheel column measured from the top of
    /// its header row (FILTER-STACK-007): the Base Shutter column and
    /// every filter column are composed the same way — header, label
    /// spacing, the label row (blank for Base), then the viewport with
    /// no further spacing — so both read this one description and
    /// share the viewport top and bottom, the selection-band center,
    /// the value baseline row, and the vertical touch center.
    func wheelColumnGeometry(ndWheelCount: Int) -> WheelColumnGeometry {
        WheelColumnGeometry(
            headerHeight: pickerHeaderHeight,
            labelSpacing: pickerLabelSpacing,
            labelRowHeight: filterWheelLabelRowHeight,
            viewportHeight: pickerHeight,
            selectionBandHeight: pickerSelectionBandHeight,
            valuePointSize: wheelRowValuePointSize(forNDWheelCount: ndWheelCount)
        )
    }

    /// The Base Shutter column's geometry: `ShutterSelectionRow` renders
    /// its blank label row and viewport in a zero-spacing stack under
    /// the shared header, matching `NDWheelView`.
    func baseShutterColumnGeometry(ndWheelCount: Int) -> WheelColumnGeometry {
        wheelColumnGeometry(ndWheelCount: ndWheelCount)
    }

    /// A filter wheel column's geometry: `NDWheelView` renders its label
    /// row and viewport in a zero-spacing stack under the group header.
    func filterWheelColumnGeometry(ndWheelCount: Int) -> WheelColumnGeometry {
        wheelColumnGeometry(ndWheelCount: ndWheelCount)
    }

    var worstCaseContentBudget: ExposureWorkspaceContentBudget {
        ExposureWorkspaceContentBudget(
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            resultSpacer: resultFlowSpacerMinLength,
            cardPadding: sectionCardPadding,
            headerTitleRow: max(Self.lineHeight(headerTitleTextStyle), Self.lineHeight(.body)),
            headerContentSpacing: headerContentSpacing,
            filmLabelRow: Self.lineHeight(.subheadline),
            filmLabelSpacing: pickerLabelSpacing,
            filmSelectorButton: Self.lineHeight(.body) + 2 + Self.lineHeight(.caption1) + 2 * sectionCardPadding,
            modelRow: reciprocityModelSelectorHeight,
            targetRow: max(Self.lineHeight(.subheadline), timerActionSize - 8),
            pickerHeader: pickerHeaderHeight,
            pickerLabelSpacing: pickerLabelSpacing,
            wheelLabelRow: filterWheelLabelRowHeight,
            picker: pickerHeight,
            wheelBodySpacing: bodySpacing,
            statusRegion: filterStatusRegionHeight,
            filmResultBlock: filmResultCardMinHeight
        )
    }
}

/// Compact 3-state ND notation toggle (Stops / OD / ND) for the ND
/// Filter header. Reads as one cohesive segmented control — a subtle
/// rounded track with a raised, filled selected segment — so the two
/// platforms share the same horizontal `ND Filter [Stops | OD | ND]`
/// placement while fitting the half-width column where a native
/// segmented control clips "Stops" (PTIMER-187). Labels stay one step
/// smaller than the title so the control stays subordinate.
private struct NDNotationToggle: View {
    let mode: NDNotationMode
    let onSelect: (NDNotationMode) -> Void

    private static let options: [(mode: NDNotationMode, label: String)] = [
        (.stops, String(localized: "Stops")),
        (.opticalDensity, "OD"),
        (.filterFactor, "ND"),
    ]

    private static let segmentShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.options, id: \.mode) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    @ViewBuilder
    private func segment(_ option: (mode: NDNotationMode, label: String)) -> some View {
        let isSelected = option.mode == mode
        Text(option.label)
            .font(.caption2.weight(isSelected ? .semibold : .regular))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    Self.segmentShape
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                }
            }
            .contentShape(Self.segmentShape)
            .onTapGesture { onSelect(option.mode) }
            .accessibilityLabel(option.label)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

private struct ShutterSelectionRow: View {
    @Binding var baseShutter: Double
    let shutterSpeeds: [Double]
    let formatShutter: (TimeInterval) -> String
    let onContinuousSelectionChange: (Double) -> Void
    let onInteractionEnd: () -> Void
    /// ND wheels sharing the row (PTIMER-199). At 3+ the Base column
    /// is width-capped (`baseShutterColumnMaxWidth`), so the value
    /// font and band metrics condense with it — otherwise labels like
    /// "1/8000" truncate instead of scaling.
    let ndWheelCount: Int
    /// Height of the filter wheels' type-label row, kept blank here so
    /// the Base Shutter viewport top aligns with the filter viewports.
    var labelRowHeight: CGFloat = 0
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

    private var isCondensed: Bool {
        style.baseShutterColumnMaxWidth(forNDWheelCount: ndWheelCount) != nil
    }

    private var layout: PickerColumnLayout {
        isCondensed
            ? PickerColumnLayout(
                unitTextWidth: 12,
                unitTextTrailingInset: 2,
                valueAlignmentPolicy: .offsetBeforeCompactUnitGlyph,
                valueAlignmentCompensation: 0
            )
            : style.pickerColumnLayout(for: .shutter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.pickerLabelSpacing) {
            Text("Base Shutter")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: pickerHeaderHeight, alignment: .leading)

            // The blank label row and the viewport form one
            // zero-spacing stack, exactly like a filter column's label
            // and wheel, so both columns share the same viewport top,
            // selection-band center, value baseline, and touch center
            // (FILTER-STACK-007, `wheelColumnGeometry`).
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: labelRowHeight)

                Picker("Base Shutter", selection: $baseShutter) {
                    ForEach(shutterSpeeds, id: \.self) { speed in
                        ShutterPickerValue(
                            valueText: shutterValueText(for: speed),
                            style: style,
                            layout: layout,
                            ndWheelCount: ndWheelCount,
                            isCondensed: isCondensed
                        )
                        .tag(speed)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .frame(height: pickerHeight)
                .clipped()
                .background {
                    WheelPickerContinuousObserver(
                        onSelectedRowChange: { row in
                            guard shutterSpeeds.indices.contains(row) else {
                                return
                            }

                            onContinuousSelectionChange(shutterSpeeds[row])
                        },
                        onInteractionEnd: onInteractionEnd
                    )
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    // Condensed column drops the in-band "s" glyph like the
                    // stacked ND columns drop theirs — the released width
                    // goes to the value.
                    PickerUnitSelectionBand(
                        unitText: isCondensed ? "" : "s",
                        style: style,
                        layout: layout
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func shutterValueText(for speed: TimeInterval) -> String {
        formatShutter(speed)
            .replacingOccurrences(of: "s", with: "")
    }
}

private struct NDStopPickerValue: View {
    let valueText: String
    /// Color of the type rail at the row's leading edge
    /// (FILTER-STACK-007): part of the row content, so it travels with
    /// its candidate through dragging, fling, commit, and snap-back.
    /// Visual only; accessibility keeps the full names.
    var typeRailColor: Color?
    /// Unavailable rows (item mounted elsewhere, over the cap) render
    /// dimmed; selecting one is refused at the set commit.
    var isDimmed = false
    let style: ExposureWorkspaceMainLayoutStyle
    let layout: PickerColumnLayout
    /// Non-nil when the wheel is part of a multi-wheel stack: the
    /// fixed unit-band metrics assume the full half-width column and
    /// push the value out of a narrow stacked wheel, so stacked
    /// wheels center the value, drop the per-wheel unit, and step
    /// fonts/paddings down with the wheel count (PTIMER-199).
    var stackedWheelCount: Int?

    var body: some View {
        Group {
            if let stackedWheelCount {
                Text(valueText)
                    .font(style.wheelRowValueFont(forNDWheelCount: stackedWheelCount))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, style.stackedNDValueHorizontalPadding(forWheelCount: stackedWheelCount))
            } else {
                Text(valueText)
                    .font(style.pickerValueFont)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(
                        .trailing,
                        layout.valueTextTrailingInset(
                            selectionBandContentTrailingInset: style.pickerSelectionBandContentTrailingInset
                        )
                    )
            }
        }
        // The rail is an overlay at the fixed leading edge: it takes
        // no layout space, so the numeric column, picker bounds, and
        // touch center are exactly as without it.
        .overlay(alignment: .leading) {
            if let typeRailColor {
                RoundedRectangle(cornerRadius: style.filterWheelTypeRailWidth / 2, style: .continuous)
                    .fill(typeRailColor)
                    .frame(width: style.filterWheelTypeRailWidth, height: style.filterWheelTypeRailHeight)
                    .padding(.leading, style.filterWheelTypeRailInset)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isDimmed ? 0.3 : 1)
    }
}

private struct ShutterPickerValue: View {
    let valueText: String
    let style: ExposureWorkspaceMainLayoutStyle
    let layout: PickerColumnLayout
    /// ND wheels sharing the row. The value font ALWAYS matches the
    /// ND wheels' (user rule: every wheel on the main screen renders
    /// at the same size); at 3+ wheels the width-capped column also
    /// switches to condensed centered rendering.
    var ndWheelCount = 1
    /// Condensed rendering for the width-capped Base column while 3+
    /// ND wheels share the row (PTIMER-199): deeper minimum scale,
    /// centered — mirroring the stacked ND columns.
    var isCondensed = false

    var body: some View {
        if isCondensed {
            Text(valueText)
                .font(style.wheelRowValueFont(forNDWheelCount: ndWheelCount))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 2)
        } else {
            Text(valueText)
                .font(style.wheelRowValueFont(forNDWheelCount: ndWheelCount))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(
                    .trailing,
                    layout.valueTextTrailingInset(
                        selectionBandContentTrailingInset: style.pickerSelectionBandContentTrailingInset
                    )
                )
        }
    }
}

private struct PickerUnitSelectionBand: View {
    let unitText: String
    let style: ExposureWorkspaceMainLayoutStyle
    let layout: PickerColumnLayout

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(height: style.pickerSelectionBandHeight)
            .overlay {
                HStack {
                    Spacer()

                    Text(unitText)
                        .font(style.pickerOverlayUnitFont)
                        .foregroundStyle(.secondary)
                        .opacity(unitText == "s" ? 0.92 : 0.96)
                        .frame(width: layout.unitTextWidth, alignment: .trailing)
                        .padding(.trailing, layout.unitTextTrailingInset)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                .padding(.trailing, style.pickerSelectionBandContentTrailingInset)
            }
            .padding(.horizontal, style.pickerSelectionBandHorizontalInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
