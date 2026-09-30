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

                // Every mounted identity stays whole on Main
                // (FILTER-AUX-002): whole names at the regular size, then
                // one point smaller; only when neither fits the column
                // does it fall back to the one-line form.
                ViewThatFits(in: .vertical) {
                    itemList(nameFont: style.auxiliarySummaryNameFont)
                    itemList(nameFont: style.auxiliarySummaryTightNameFont)
                    itemList(nameFont: nil)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
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

    /// Whole-name items at `nameFont`, or the one-line form when `nil`.
    private func itemList(nameFont: Font?) -> some View {
        VStack(alignment: .leading, spacing: style.auxiliarySummaryRowSpacing) {
            ForEach(summary.items, id: \.itemID) { item in
                if let nameFont {
                    fullNameItem(item, nameFont: nameFont)
                } else {
                    oneLineItem(item)
                }
            }
        }
    }

    /// The whole registered name, wrapped over as many lines as it
    /// needs and never shortened. The contribution stays beside the
    /// name when both fit one line; otherwise it leads the detail line
    /// under the name.
    private func fullNameItem(_ item: AuxiliaryFilterSummaryItemDisplay, nameFont: Font) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    nameText(item, font: nameFont, wraps: false)
                    Spacer(minLength: 2)
                    contributionText(item)
                }
                detailText(item)
            }
            VStack(alignment: .leading, spacing: 0) {
                nameText(item, font: nameFont, wraps: true)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    contributionText(item)
                    detailText(item)
                }
            }
        }
    }

    /// The previous one-line form, kept only for a combination whose
    /// full names cannot fit the column.
    private func oneLineItem(_ item: AuxiliaryFilterSummaryItemDisplay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                opticalDot(item)
                Text(item.name)
                    .font(style.auxiliarySummaryNameFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                contributionText(item)
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

    @ViewBuilder
    private func opticalDot(_ item: AuxiliaryFilterSummaryItemDisplay) -> some View {
        if let opticalColor = item.opticalColor {
            Circle()
                .fill(Color.filterSet(opticalColor))
                .frame(width: 6, height: 6)
        }
    }

    /// The name with its optical-color dot. One line without shrinking
    /// when `wraps` is false (the fit test fails instead); otherwise as
    /// many lines as the name needs.
    private func nameText(_ item: AuxiliaryFilterSummaryItemDisplay, font: Font, wraps: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            opticalDot(item)
            Text(item.name)
                .font(font)
                .foregroundStyle(.primary)
                .lineLimit(wraps ? nil : 1)
                .fixedSize(horizontal: !wraps, vertical: true)
        }
    }

    private func contributionText(_ item: AuxiliaryFilterSummaryItemDisplay) -> some View {
        Text(item.contributionText)
            .font(style.auxiliarySummaryValueFont)
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    /// Mode, registered density, or optical color, never shortened in
    /// the full-name layout: on one line when it fits, otherwise one
    /// part per line (`Record only` / `2 stops`), each part wrapping if
    /// it must.
    @ViewBuilder
    private func detailText(_ item: AuxiliaryFilterSummaryItemDisplay) -> some View {
        if let detail = item.detailText {
            ViewThatFits(in: .horizontal) {
                Text(detail)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(item.detailSegments.enumerated()), id: \.offset) { _, segment in
                        Text(segment)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(style.auxiliarySummaryDetailFont)
            .foregroundStyle(.secondary)
        }
    }
}
