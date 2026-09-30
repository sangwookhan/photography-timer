// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// The Main summary space for the mounted auxiliary filters
/// (FILTER-AUX-001/002): one non-scrolling column immediately after
/// Base Shutter, present only while at least one auxiliary item is
/// mounted, showing up to three items as compact rows (identifier and
/// current contribution in stops) and a `+ N more` line for the rest. It is
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

                // One compact row per visible item (FILTER-AUX-002):
                // identifier and contribution only; modes and densities
                // stay in the shooting popup. The first three rows are
                // spread evenly over the summary height, and any further
                // items are counted in a `+ N more` line. The summary
                // itself never scrolls; tapping it opens the full list.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(summary.visibleItems, id: \.itemID) { item in
                        Spacer(minLength: 2)
                        compactRow(item)
                    }
                    if let moreText = summary.moreText {
                        Spacer(minLength: 2)
                        Text(moreText)
                            .font(style.auxiliarySummaryTitleFont)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .accessibilityIdentifier("auxiliary-filter-summary-more")
                    }
                    Spacer(minLength: 2)
                }
                .frame(maxHeight: .infinity, alignment: .top)
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
        // The wheels block input during the short reshaping window after
        // an ND commit. The summary is blocked with them but must not be
        // drawn disabled: its content has not changed, and dimming it for
        // that window made it flicker while an ND wheel was adjusted.
        .allowsHitTesting(isInteractive)
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
