// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// The Main summary space for the mounted auxiliary filters
/// (FILTER-AUX-001/002): one non-scrolling column immediately after
/// Base Shutter, present only while at least one auxiliary item is
/// mounted, listing every item's name and current contribution in
/// stops with the detail that keeps a GND's registered density or a
/// Color filter's optical color distinct from the contribution. It is
/// a button: tapping it reopens the shooting popup on this camera's
/// current selection (FILTER-FLOW-002). With a screen reader it is one
/// element that speaks every mounted identity, mode, and contribution
/// (FILTER-A11Y-001); it never pretends to be an adjustable wheel.
struct AuxiliaryFilterSummaryView: View {
    let summary: AuxiliaryFilterSummaryDisplayState
    /// The column's height: the wheels' label row plus their viewport,
    /// so the summary shares the row's vertical extent without moving
    /// any wheel's touch center.
    let height: CGFloat
    let isInteractive: Bool
    let style: ExposureWorkspaceMainLayoutStyle
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: style.auxiliarySummaryRowSpacing) {
                HStack(spacing: 1) {
                    Text(AuxiliaryFilterSummaryPresenter.title)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                }
                .font(style.auxiliarySummaryTitleFont)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                // One compact row per mounted item (FILTER-AUX-002):
                // identifier and contribution only; modes and densities
                // stay in the shooting popup.
                ForEach(summary.items, id: \.itemID) { item in
                    compactRow(item)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .disabled(!isInteractive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary.accessibilityLabel))
        .accessibilityHint(Text("Opens the shooting filter selection"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("auxiliary-filter-summary")
    }

    /// `● MARUMI  2`, `CPL  1.5`, `GND  0`: the optical-color circle of
    /// a Color item, the first identifier candidate that fits the column
    /// whole, and the trailing contribution. Neither the identifier nor
    /// the contribution is ever truncated; only the last, shortest
    /// candidate may shrink slightly if even it does not fit.
    private func compactRow(_ item: AuxiliaryFilterSummaryItemDisplay) -> some View {
        // Spacing is explicit so a six-letter name and a one-digit
        // contribution fit a 74 pt column at full size.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let opticalColor = item.opticalColor {
                Circle()
                    .fill(Color.filterSet(opticalColor))
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 3)
            }
            ViewThatFits(in: .horizontal) {
                ForEach(Array(item.compactLabels.dropLast().enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(item.compactLabels.last ?? item.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(style.auxiliarySummaryNameFont)
            .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(item.contributionText)
                .font(style.auxiliarySummaryValueFont)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }
}
