// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Minimal page indicator for the camera-slot pager. Renders a row of
/// dots (active dot is wider + darker) followed by a small "N of M"
/// counter so the photographer can read the current slot position
/// without occupying meaningful vertical space.
///
/// The indicator is presentation-only — slot transitions go through
/// the ViewModel's `selectCameraSlot(_:)` / `selectNextCameraSlot()` /
/// `selectPreviousCameraSlot()` paths. Tapping a dot is intentionally
/// not wired: with four slots the swipe-and-text combo carries enough
/// affordance, and adding a tap target encourages users to fight the
/// indicator's small footprint. VoiceOver users navigate slots
/// through the workspace's named "Next/Previous camera slot"
/// accessibility actions, not through this view.
struct CameraSlotPagerIndicator: View {
    let count: Int
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index == activeIndex
                                ? Color.primary.opacity(0.7)
                                : Color.primary.opacity(0.18)
                        )
                        .frame(
                            width: index == activeIndex ? 12 : 5,
                            height: 5
                        )
                        .animation(.easeInOut(duration: 0.18), value: activeIndex)
                }
            }

            Text(pageText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("camera-slot-page-counter")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera slot")
        .accessibilityValue(pageText)
        .accessibilityIdentifier("camera-slot-page-indicator")
    }

    private var pageText: String {
        "\(activeIndex + 1) of \(count)"
    }
}
