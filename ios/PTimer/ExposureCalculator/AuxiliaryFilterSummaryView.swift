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

                ForEach(summary.items, id: \.itemID) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            if let opticalColor = item.opticalColor {
                                Circle()
                                    .fill(Color.filterOptical(opticalColor))
                                    .frame(width: 6, height: 6)
                            }
                            // The full name is the identity (FILTER-AUX-002):
                            // it shrinks before it truncates in the narrow
                            // column.
                            Text(item.name)
                                .font(style.auxiliarySummaryNameFont)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
                                .truncationMode(.tail)
                            Spacer(minLength: 2)
                            Text(item.contributionText)
                                .font(style.auxiliarySummaryValueFont)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                        }
                        if let detail = item.detailText {
                            Text(detail)
                                .font(style.auxiliarySummaryDetailFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
                                .truncationMode(.tail)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
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
}
