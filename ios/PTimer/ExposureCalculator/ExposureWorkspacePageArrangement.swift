// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Places one camera page's header, inputs and results in the chosen
/// arrangement (SHELL-057/059): stacked in one column, or the header
/// across the top with the inputs and results side by side below it.
/// The page is width-bounded and centered so it never stretches
/// without limit on a wide window.
///
/// Both arrangements lay out the same views; only the layout changes.
/// The views therefore keep their identity and state (an open Target
/// Shutter entry, for example) when the window changes the arrangement
/// (SHELL-053). The single column is the plain stack the page always
/// used, so its sizing is unchanged.
struct ExposureWorkspacePageArrangement<Header: View, Inputs: View, Results: View>: View {
    let arrangement: ExposureWorkspaceArrangement
    /// Minimum space kept below the results.
    let resultSpacerMinLength: CGFloat
    @ViewBuilder let header: () -> Header
    @ViewBuilder let inputs: () -> Inputs
    @ViewBuilder let results: () -> Results

    var body: some View {
        let layout: AnyLayout = switch arrangement {
        case .singleColumn:
            AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        case .sideBySide:
            AnyLayout(SideBySidePageLayout(columnGap: ExposureWorkspaceLayoutMetrics.columnGap))
        case let .book(leadingEnd, trailingStart):
            AnyLayout(FoldPageLayout(fold: .book(leadingEnd: leadingEnd, trailingStart: trailingStart)))
        case let .tabletop(lowerStart):
            AnyLayout(FoldPageLayout(fold: .tabletop(lowerStart: lowerStart)))
        }
        layout {
            Group { header() }
                .layoutValue(key: PageBlockRole.self, value: .header)
            Group { inputs() }
                .layoutValue(key: PageBlockRole.self, value: .inputs)
            Group { results() }
                .layoutValue(key: PageBlockRole.self, value: .results)
            Spacer(minLength: resultSpacerMinLength)
                .layoutValue(key: PageBlockRole.self, value: .spacer)
        }
        .frame(maxWidth: arrangement.maximumWidth)
    }
}

/// Which part of the page a view belongs to.
private enum PageBlockRole: LayoutValueKey {
    case header
    case inputs
    case results
    case spacer

    static let defaultValue = PageBlockRole.spacer
}

/// The header across the top; below it the inputs stacked in the
/// leading column and the results stacked in the trailing column, each
/// at its natural height. The page fills the proposed size.
private struct SideBySidePageLayout: Layout {
    let columnGap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = (bounds.width - columnGap) / 2
        var y = bounds.minY
        for subview in subviews where subview[PageBlockRole.self] == .header {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height
        }
        let columns: [(PageBlockRole, CGFloat)] = [
            (.inputs, bounds.minX),
            (.results, bounds.minX + columnWidth + columnGap),
        ]
        for (role, x) in columns {
            var columnY = y
            for subview in subviews where subview[PageBlockRole.self] == role {
                let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                subview.place(at: CGPoint(x: x, y: columnY), proposal: ProposedViewSize(width: columnWidth, height: size.height))
                columnY += size.height
            }
        }
        for subview in subviews where subview[PageBlockRole.self] == .spacer {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), proposal: .zero)
        }
    }
}

/// Places the blocks around a fold (SHELL-062), each at its natural
/// height: book puts the header and inputs before the fold and the
/// results after it; tabletop puts the header and results above the fold
/// and the inputs below it, in one column bounded like the stacked page.
private struct FoldPageLayout: Layout {
    let fold: ExposureWorkspaceArrangement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        func stack(_ roles: [PageBlockRole], x: CGFloat, width: CGFloat, from top: CGFloat) {
            var y = top
            for role in roles {
                for subview in subviews where subview[PageBlockRole.self] == role {
                    let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                    subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
                    y += size.height
                }
            }
        }
        switch fold {
        case let .book(leadingEnd, trailingStart):
            stack([.header, .inputs], x: bounds.minX, width: leadingEnd, from: bounds.minY)
            stack([.results], x: bounds.minX + trailingStart, width: bounds.width - trailingStart, from: bounds.minY)
        case let .tabletop(lowerStart):
            let width = min(bounds.width, ExposureWorkspaceArrangement.singleColumn.maximumWidth)
            let x = bounds.minX + (bounds.width - width) / 2
            stack([.header, .results], x: x, width: width, from: bounds.minY)
            stack([.inputs], x: x, width: width, from: bounds.minY + lowerStart)
        case .singleColumn, .sideBySide:
            break
        }
        for subview in subviews where subview[PageBlockRole.self] == .spacer {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), proposal: .zero)
        }
    }
}
