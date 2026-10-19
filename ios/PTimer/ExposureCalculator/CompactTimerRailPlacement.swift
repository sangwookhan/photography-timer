// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit

/// Where the compact timer summary sits as a side rail in the system side
/// area (WORKSPACE-032/034), all in the window's coordinate space.
struct CompactTimerRailPlacement: Equatable {
    enum Side: Equatable {
        case leading
        case trailing
    }

    let side: Side
    /// The side area's horizontal extent.
    let minX: CGFloat
    let width: CGFloat
    /// The longest vertical run of the side area clear of reserved regions.
    let top: CGFloat
    let height: CGFloat

    /// Card width inside the rail, keeping a margin on both sides.
    var cardWidth: CGFloat { width - 2 * Self.margin }

    /// Space kept between the rail cards and the side area's edges and
    /// any reserved region.
    static let margin: CGFloat = 6

    /// The narrowest card that keeps the compact card's content readable.
    static let minimumCardWidth: CGFloat = 64

    /// The rail for a content area of [content] (the safe area) inside a
    /// window of [window] bounds, or nil when neither side area is wide
    /// enough for a readable card or tall enough for one card. The side
    /// is the wider side area, so it follows the actual system geometry
    /// rather than a fixed edge. The run is limited to the safe area's
    /// height (below the status area and above the home indicator) and
    /// avoids every [reserved] region (cameras and similar) that overlaps
    /// the side area.
    static func placement(
        content: CGRect,
        window: CGRect,
        reserved: [CGRect],
        cardHeight: CGFloat
    ) -> CompactTimerRailPlacement? {
        let leadingWidth = content.minX - window.minX
        let trailingWidth = window.maxX - content.maxX
        let side: Side = trailingWidth >= leadingWidth ? .trailing : .leading
        let width = max(leadingWidth, trailingWidth)
        guard width - 2 * margin >= minimumCardWidth else { return nil }
        let minX = side == .trailing ? content.maxX : window.minX

        let blocks = reserved
            .filter { $0.maxX > minX && $0.minX < minX + width }
            .map { ($0.minY - margin, $0.maxY + margin) }
            .sorted { $0.0 < $1.0 }
        var best = (top: content.minY, height: CGFloat(0))
        var cursor = content.minY
        for block in blocks {
            let run = min(block.0, content.maxY) - cursor
            if run > best.height { best = (cursor, run) }
            cursor = max(cursor, block.1)
        }
        if content.maxY - cursor > best.height { best = (cursor, content.maxY - cursor) }
        guard best.height >= cardHeight else { return nil }
        return CompactTimerRailPlacement(side: side, minX: minX, width: width, top: best.top, height: best.height)
    }
}

/// The window's bounds, its active occluding reserved regions (cameras
/// and similar) and an active fold, in window coordinates.
struct ReservedRegionSnapshot: Equatable {
    var window: CGRect = .zero
    var occlusions: [CGRect] = []
    /// The active fold (a half-open hinge), widened by the margins the
    /// system asks content to keep from it; nil when the window has no
    /// fold or it lies flat.
    var fold: CGRect?
}

/// Reports the window's reserved regions whenever its layout changes
/// (rotation, resizing, folding). Reserved regions are read on iOS 27.1
/// and later; earlier systems report none.
struct ReservedRegionReader: UIViewRepresentable {
    let onChange: (ReservedRegionSnapshot) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: UIView {
        var onChange: ((ReservedRegionSnapshot) -> Void)?
        private var last = ReservedRegionSnapshot()

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        private func report() {
            guard let window else { return }
            var snapshot = ReservedRegionSnapshot(window: window.bounds)
            if #available(iOS 27.1, *) {
                snapshot.occlusions = window.reservedRegions(kind: .occlusion)
                    .filter(\.isActive)
                    .map(\.frame)
                snapshot.fold = window.reservedRegions(kind: .division)
                    .first(where: \.isActive)
                    .map { $0.frame.inset(by: UIEdgeInsets(
                        top: -$0.margins.top,
                        left: -$0.margins.left,
                        bottom: -$0.margins.bottom,
                        right: -$0.margins.right
                    )) }
            }
            guard snapshot != last else { return }
            last = snapshot
            // Reported after the current update so SwiftUI state is not
            // changed while views are being updated.
            DispatchQueue.main.async { [onChange] in onChange?(snapshot) }
        }
    }
}
