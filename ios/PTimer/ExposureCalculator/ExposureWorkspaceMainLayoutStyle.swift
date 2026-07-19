// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import PTimerCore
import PTimerKit

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
        switch self {
        case .regular:
            return .largeTitle.weight(.bold)
        case .compact:
            return .title.weight(.bold)
        case .dense:
            return .title2.weight(.bold)
        }
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
            return .system(size: 32, weight: .bold, design: .rounded)
        case .compact:
            return .system(size: 26, weight: .bold, design: .rounded)
        case .dense:
            return .system(size: 19, weight: .semibold, design: .rounded)
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
        switch self {
        case .regular:
            switch count {
            case ...2: return .system(size: 28, weight: .bold, design: .rounded)
            case 3: return .system(size: 24, weight: .bold, design: .rounded)
            default: return .system(size: 20, weight: .semibold, design: .rounded)
            }
        case .compact:
            switch count {
            case ...2: return .system(size: 23, weight: .bold, design: .rounded)
            case 3: return .system(size: 20, weight: .semibold, design: .rounded)
            default: return .system(size: 17, weight: .semibold, design: .rounded)
            }
        case .dense:
            switch count {
            case ...2: return .system(size: 18, weight: .semibold, design: .rounded)
            case 3: return .system(size: 16, weight: .semibold, design: .rounded)
            default: return .system(size: 14, weight: .semibold, design: .rounded)
            }
        }
    }

    /// Horizontal padding partner of `stackedNDValueFont` — shrinks
    /// with the wheel count so narrow columns spend their width on
    /// glyphs.
    func stackedNDValueHorizontalPadding(forWheelCount count: Int) -> CGFloat {
        count >= 4 ? 2 : 4
    }

    /// THE wheel-row value font (user rule, 2026-07-15): every wheel
    /// on the main screen — Base Shutter AND all ND wheels — always
    /// renders its values at the SAME size for a given wheel count.
    /// One wheel keeps the established `pickerValueFont`; stacks step
    /// the shared size down with the ND wheel count.
    func wheelRowValueFont(forNDWheelCount count: Int) -> Font {
        count <= 1 ? pickerValueFont : stackedNDValueFont(forWheelCount: count)
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
        switch self {
        case .regular:
            return count == 3 ? 118 : 88
        case .compact:
            return count == 3 ? 108 : 84
        case .dense:
            return count == 3 ? 100 : 80
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
    let ndFilterSteps: [NDStep]
    let ndDisplaySteps: [NDStep]
    let ndFilterWheelIDs: [Int]
    let shutterSpeeds: [Double]
    let ndStepValuesForWheel: (Int) -> [NDStep]
    let formatShutter: (TimeInterval) -> String
    let ndNotationMode: NDNotationMode
    let onSelectNotationMode: (NDNotationMode) -> Void
    let onContinuousBaseShutterChange: (Double) -> Void
    let onBaseShutterInteractionEnd: () -> Void
    /// Owned-picker measurements (PTIMER-199 v2), keyed by wheel
    /// IDENTITY and stamped with the generation they were issued
    /// under. The ViewModel's state machine judges them; the view
    /// layer only forwards.
    let onNDWheelRowObserved: (Int, NDStep, Int) -> Void
    let onNDWheelSelected: (Int, NDStep, Int) -> Void
    let onNDWheelTouchBegan: (Int, Int) -> Void
    let onNDWheelTouchEnded: (Int) -> Void
    let onNDWheelOverscrollReleased: (Int, Int) -> Void
    let isNDWheelResolved: (Int) -> Bool
    let areNDWheelsInteractive: Bool
    let ndWheelGeneration: Int
    let showsAddFilterWheelControl: Bool
    let canAddFilterWheel: Bool
    let onAddFilterWheel: () -> Void
    let canRemoveEmptyFilterWheel: Bool
    let onRemoveEmptyFilterWheel: () -> Void
    let ndStackTotalDisplayState: NDStackTotalDisplayState
    let style: ExposureWorkspaceMainLayoutStyle

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
                    ndDisplaySteps: ndDisplaySteps,
                    ndFilterWheelIDs: ndFilterWheelIDs,
                    ndStepValuesForWheel: ndStepValuesForWheel,
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
                    canAddFilterWheel: canAddFilterWheel,
                    onAddFilterWheel: onAddFilterWheel,
                    canRemoveEmptyFilterWheel: canRemoveEmptyFilterWheel,
                    onRemoveEmptyFilterWheel: onRemoveEmptyFilterWheel,
                    totalDisplayState: ndStackTotalDisplayState,
                    pickerHeight: style.pickerHeight,
                    style: style
                )
            }
        }
        .sectionCardStyle(style: style)
    }
}

/// ND filter group: the ND header row (title + notation toggle)
/// spanning the ND wheel area, above a horizontal row of 1–4 ND
/// wheels plus the edge Add control (PTIMER-199).
///
/// Add/remove paths (PTIMER-199 v2): the edge Add control appends a
/// 0-stop wheel; removal is self-cleaning (§4.2.2) plus the
/// overscroll-past-zero gesture (§4.2.3) — there are no menus.
/// VoiceOver custom actions mirror Add filter / Remove empty filter.
private struct NDFilterGroupView: View {
    let ndFilterSteps: [NDStep]
    /// Display values (pending/live over committed, §4.5): what the
    /// wheel bindings and the idle re-sync target — a mid-epoch
    /// selection must never be visually reverted before the set
    /// commit lands.
    let ndDisplaySteps: [NDStep]
    /// Stable identity parallel to `ndFilterSteps` (PTIMER-199 (S)4.3)
    /// so the ForEach keys wheels by wheel, not by position, and a
    /// commit-sort reorder animates as movement.
    let ndFilterWheelIDs: [Int]
    let ndStepValuesForWheel: (Int) -> [NDStep]
    let ndNotationMode: NDNotationMode
    let onSelectNotationMode: (NDNotationMode) -> Void
    let onWheelRowObserved: (Int, NDStep, Int) -> Void
    let onWheelSelected: (Int, NDStep, Int) -> Void
    let onWheelTouchBegan: (Int, Int) -> Void
    let onWheelTouchEnded: (Int) -> Void
    let onWheelOverscrollReleased: (Int, Int) -> Void
    let isWheelResolved: (Int) -> Bool
    let areWheelsInteractive: Bool
    let ndWheelGeneration: Int
    let showsAddFilterWheelControl: Bool
    let canAddFilterWheel: Bool
    let onAddFilterWheel: () -> Void
    let canRemoveEmptyFilterWheel: Bool
    let onRemoveEmptyFilterWheel: () -> Void
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

    /// Transient Total-overlay visibility (PTIMER-199 §4.6). Pure
    /// view-layer timing state: the overlay re-shows on any effective
    /// change while stacked, then fades after a short idle — slightly
    /// longer right after a wheel was added.
    @State private var isTotalOverlayVisible = false
    @State private var totalOverlayHideTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: style.pickerLabelSpacing) {
            HStack(spacing: 6) {
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

                Spacer(minLength: 4)

                NDNotationToggle(mode: ndNotationMode, onSelect: onSelectNotationMode)
                    .accessibilityIdentifier("nd-notation-mode-control")
            }
            .frame(height: pickerHeaderHeight)

            HStack(spacing: style.inputColumnSpacing) {
                ForEach(wheelSlots) { slot in
                    let index = slot.index
                    NDWheelView(
                        displayStep: ndDisplaySteps.indices.contains(index)
                            ? ndDisplaySteps[index]
                            : ndFilterSteps[index],
                        ndStepValues: ndStepValuesForWheel(index),
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
                        pickerHeight: pickerHeight,
                        style: style
                    )
                    // Automatic cleanup (and manual overscroll/add)
                    // animate as fade + width collapse; siblings
                    // re-flow via the implicit count animation below.
                    .transition(.ndWheelCollapse)
                }

                if showsAddFilterWheelControl {
                    AddFilterWheelControl(
                        pickerHeight: pickerHeight,
                        isEnabled: canAddFilterWheel,
                        action: onAddFilterWheel
                    )
                }
            }
            // Transient Total overlay (§4.6): non-blocking — touches
            // always pass through to the wheels beneath; content and
            // the ≥ 2 wheels precondition come from the display state,
            // fade timing lives here in the view layer.
            .overlay(alignment: .top) {
                if isTotalOverlayVisible, totalDisplayState.isVisibleCandidate {
                    NDStackTotalOverlayBadge(state: totalDisplayState, style: style)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .padding(.top, 2)
                }
            }
            .onChange(of: totalDisplayState) { oldValue, newValue in
                guard newValue.isVisibleCandidate else {
                    totalOverlayHideTask?.cancel()
                    isTotalOverlayVisible = false
                    return
                }
                // Any effective change re-shows; a fresh wheel shows
                // slightly longer so the add is acknowledged.
                showTotalOverlay(
                    for: newValue.wheelCount > oldValue.wheelCount ? 2.5 : 1.5
                )
            }
            // Drives the wheel add/remove transitions (incl. the
            // delayed auto-removal fired from the view model, which
            // mutates state outside any withAnimation scope).
            .animation(.easeInOut(duration: 0.35), value: ndFilterSteps.count)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityValue(accessibilityTotalValue)
        // Actions are registered CONDITIONALLY so VoiceOver never
        // surfaces a dead command — same availability rules as the
        // menu items (PTIMER-199 §4.2).
        .accessibilityActions {
            if canAddFilterWheel {
                Button(String(localized: "Add filter"), action: onAddFilterWheel)
            }
            if canRemoveEmptyFilterWheel {
                Button(String(localized: "Remove empty filter"), action: onRemoveEmptyFilterWheel)
            }
        }
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

    private func showTotalOverlay(for seconds: Double) {
        totalOverlayHideTask?.cancel()
        withAnimation(.easeIn(duration: 0.15)) {
            isTotalOverlayVisible = true
        }
        totalOverlayHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.4)) {
                isTotalOverlayVisible = false
            }
        }
    }

}

/// Edge Add control (PTIMER-199): the trailing-edge affordance of the
/// ND wheel row — a real, tappable control rendered as a dim ghost
/// column with a plus glyph. Visible only while a wheel can be added.
/// The visual stays hint-width (26 pt, per user feedback on the M1a
/// captures) so it never competes with the wheels for row space; the
/// HIG 44 pt touch target is recovered by extending the hit shape
/// into the surrounding card padding and column gap. Deliberately
/// menu-free (§4.2.5): removal is covered by the self-cleaning
/// rules and the accessibility custom actions.
private struct AddFilterWheelControl: View {
    let pickerHeight: CGFloat
    /// False while any wheel interaction is in flight (§4.3): the
    /// control stays IN the layout (so wheels never resize under a
    /// moving finger) but dims and ignores taps until the epoch
    /// closes.
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.tertiarySystemFill), lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill).opacity(0.35))
                )
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .frame(height: pickerHeight)
                .contentShape(Rectangle().inset(by: -9))
        }
        .buttonStyle(.plain)
        .frame(width: 26)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(Text("Add filter"))
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

/// Transient Total badge over the ND wheel row (PTIMER-199 §4.6):
/// the effective sum, always in stops, plus a Maximum marker at the
/// 30-stop cap. Rendering only — visibility timing and hit-test
/// pass-through are owned by `NDFilterGroupView`.
private struct NDStackTotalOverlayBadge: View {
    let state: NDStackTotalDisplayState
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        Group {
            if state.isAtMaximum {
                Text("Total \(state.totalStopsText) stops · Maximum")
            } else {
                Text("Total \(state.totalStopsText) stops")
            }
        }
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            // User field feedback: the ultra-thin capsule blended
            // into the wheel area. A more opaque material plus a
            // soft drop shadow lifts the badge off the wheels
            // without redesigning it.
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
    }
}

/// A single ND wheel picker column (value wheel + live-scroll
/// observer + unit selection band), header-less so the group above
/// can lay out 1–4 of them in one row (PTIMER-199).
private struct NDWheelView: View {
    /// The wheel's display value (pending selection while the set
    /// commit is open, committed value otherwise).
    let displayStep: NDStep
    let ndStepValues: [NDStep]
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
    let onRowObserved: (NDStep, Int) -> Void
    let onSelected: (NDStep, Int) -> Void
    let onTouchBegan: (Int) -> Void
    let onTouchEnded: () -> Void
    let onOverscrollReleased: (Int) -> Void
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

    private var isCompact: Bool {
        wheelCount > 1
    }

    private var layout: PickerColumnLayout {
        style.pickerColumnLayout(for: .ndStop)
    }

    /// Mode-dependent unit shown in the selection band (`stops` / `OD`
    /// / `ND`). Constant per mode, so the selected step is just a
    /// convenient input.
    private var unitText: String {
        NDNotationFormatter.display(for: displayStep, mode: ndNotationMode).unit
    }

    var body: some View {
        NDWheelPickerView(
            steps: ndStepValues,
            selectedStep: displayStep,
            isResolved: isResolved,
            isInputEnabled: isInputEnabled,
            generation: generation,
            rowConfiguration: AnyHashable("\(ndNotationMode)-\(wheelCount)"),
            rowHeight: 32,
            rowContent: { step in
                NDStopPickerValue(
                    valueText: NDNotationFormatter.display(for: step, mode: ndNotationMode).value,
                    style: style,
                    layout: layout,
                    stackedWheelCount: isCompact ? wheelCount : nil
                )
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
}

/// Shared height for the two picker-column headers so the notation
/// control on the ND header does not push the ND wheel below the
/// shutter wheel (PTIMER-187).
private let pickerHeaderHeight: CGFloat = 30

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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func shutterValueText(for speed: TimeInterval) -> String {
        formatShutter(speed)
            .replacingOccurrences(of: "s", with: "")
    }
}

private struct NDStopPickerValue: View {
    let valueText: String
    let style: ExposureWorkspaceMainLayoutStyle
    let layout: PickerColumnLayout
    /// Non-nil when the wheel is part of a multi-wheel stack: the
    /// fixed unit-band metrics assume the full half-width column and
    /// push the value out of a narrow stacked wheel, so stacked
    /// wheels center the value, drop the per-wheel unit, and step
    /// fonts/paddings down with the wheel count (PTIMER-199).
    var stackedWheelCount: Int?

    var body: some View {
        if let stackedWheelCount {
            Text(valueText)
                .font(style.wheelRowValueFont(forNDWheelCount: stackedWheelCount))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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
