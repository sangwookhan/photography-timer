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
    let shutterSpeeds: [Double]
    let ndStepValues: [NDStep]
    let formatShutter: (TimeInterval) -> String
    let ndNotationMode: NDNotationMode
    let onSelectNotationMode: (NDNotationMode) -> Void
    let onContinuousBaseShutterChange: (Double) -> Void
    let onCommitNDFilterStep: (Int, NDStep) -> Void
    let onContinuousNDStepChange: (Int, NDStep) -> Void
    let onBaseShutterInteractionEnd: () -> Void
    let onNDStopInteractionEnd: (Int) -> Void
    let canAddFilterWheel: Bool
    let onAddFilterWheel: () -> Void
    let canRemoveEmptyFilterWheel: Bool
    let onRemoveEmptyFilterWheel: () -> Void
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
                    pickerHeight: style.pickerHeight,
                    style: style
                )

                NDFilterGroupView(
                    ndFilterSteps: ndFilterSteps,
                    ndStepValues: ndStepValues,
                    ndNotationMode: ndNotationMode,
                    onSelectNotationMode: onSelectNotationMode,
                    onCommitStep: onCommitNDFilterStep,
                    onContinuousSelectionChange: onContinuousNDStepChange,
                    onInteractionEnd: onNDStopInteractionEnd,
                    canAddFilterWheel: canAddFilterWheel,
                    onAddFilterWheel: onAddFilterWheel,
                    canRemoveEmptyFilterWheel: canRemoveEmptyFilterWheel,
                    onRemoveEmptyFilterWheel: onRemoveEmptyFilterWheel,
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
    let ndStepValues: [NDStep]
    let ndNotationMode: NDNotationMode
    let onSelectNotationMode: (NDNotationMode) -> Void
    let onCommitStep: (Int, NDStep) -> Void
    let onContinuousSelectionChange: (Int, NDStep) -> Void
    let onInteractionEnd: (Int) -> Void
    let canAddFilterWheel: Bool
    let onAddFilterWheel: () -> Void
    let canRemoveEmptyFilterWheel: Bool
    let onRemoveEmptyFilterWheel: () -> Void
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

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
                ForEach(ndFilterSteps.indices, id: \.self) { index in
                    NDWheelView(
                        ndStep: wheelBinding(at: index),
                        ndStepValues: ndStepValues,
                        ndNotationMode: ndNotationMode,
                        isCompact: ndFilterSteps.count > 1,
                        onContinuousSelectionChange: { onContinuousSelectionChange(index, $0) },
                        onInteractionEnd: { onInteractionEnd(index) },
                        pickerHeight: pickerHeight,
                        style: style
                    )
                }

                if canAddFilterWheel {
                    AddFilterWheelControl(
                        pickerHeight: pickerHeight,
                        action: onAddFilterWheel
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
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

    /// Per-wheel picker binding: reads the passed-in display value and
    /// routes writes through the indexed commit callback.
    private func wheelBinding(at index: Int) -> Binding<NDStep> {
        Binding(
            get: { ndFilterSteps[index] },
            set: { onCommitStep(index, $0) }
        )
    }
}

/// Edge Add control (PTIMER-199): the trailing-edge affordance of the
/// ND wheel row — a real, tappable control rendered as a dim ghost
/// column with a plus glyph. Visible only while a wheel can be added;
/// the 44 pt frame keeps the HIG minimum touch target while the
/// visual stays subordinate to the wheels. Deliberately menu-free
/// (§4.2.5): removal is covered by the self-cleaning rules and the
/// accessibility custom actions.
private struct AddFilterWheelControl: View {
    let pickerHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.tertiarySystemFill), lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill).opacity(0.35))
                )
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .frame(height: pickerHeight)
        }
        .buttonStyle(.plain)
        .frame(width: 44)
        .accessibilityLabel(Text("Add filter"))
    }
}

/// A single ND wheel picker column (value wheel + live-scroll
/// observer + unit selection band), header-less so the group above
/// can lay out 1–4 of them in one row (PTIMER-199).
private struct NDWheelView: View {
    @Binding var ndStep: NDStep
    let ndStepValues: [NDStep]
    let ndNotationMode: NDNotationMode
    /// True when the wheel is part of a multi-wheel stack: values
    /// center and the per-wheel unit band text drops, because the
    /// single-column band metrics push the value out of the narrow
    /// stacked column (PTIMER-199, R2 evidence).
    let isCompact: Bool
    let onContinuousSelectionChange: (NDStep) -> Void
    let onInteractionEnd: () -> Void
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

    private var layout: PickerColumnLayout {
        style.pickerColumnLayout(for: .ndStop)
    }

    /// Mode-dependent unit shown in the selection band (`stops` / `OD`
    /// / `ND`). Constant per mode, so the selected step is just a
    /// convenient input.
    private var unitText: String {
        NDNotationFormatter.display(for: ndStep, mode: ndNotationMode).unit
    }

    var body: some View {
        Picker("ND Filter", selection: $ndStep) {
                ForEach(ndStepValues, id: \.self) { step in
                    NDStopPickerValue(
                        valueText: NDNotationFormatter.display(for: step, mode: ndNotationMode).value,
                        style: style,
                        layout: layout,
                        isCompact: isCompact
                    )
                    .tag(step)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: pickerHeight)
            .clipped()
            .background {
                WheelPickerContinuousObserver(
                    onSelectedRowChange: { row in
                        guard ndStepValues.indices.contains(row) else {
                            return
                        }

                        onContinuousSelectionChange(ndStepValues[row])
                    },
                    onInteractionEnd: onInteractionEnd
                )
            }
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
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

    private var layout: PickerColumnLayout {
        style.pickerColumnLayout(for: .shutter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.pickerLabelSpacing) {
            Text("Base Shutter")
                .font(.footnote.weight(.semibold))
                .frame(height: pickerHeaderHeight, alignment: .leading)

            Picker("Base Shutter", selection: $baseShutter) {
                ForEach(shutterSpeeds, id: \.self) { speed in
                    ShutterPickerValue(
                        valueText: shutterValueText(for: speed),
                        style: style,
                        layout: layout
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
                PickerUnitSelectionBand(
                    unitText: "s",
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
    /// Multi-wheel (stacked) rendering: the fixed unit-band metrics
    /// assume the full half-width column and push the value out of a
    /// narrow stacked wheel, so stacked wheels center the value and
    /// drop the per-wheel unit instead (PTIMER-199, R2 evidence).
    var isCompact = false

    var body: some View {
        if isCompact {
            Text(valueText)
                .font(style.pickerValueFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 4)
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

    var body: some View {
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
