// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import PTimerKit

struct ContentView: View {
    var body: some View {
        ExposureCalculatorScreen()
            .ptimerComponentTheme(.system)
            #if DEBUG
            .overlay(alignment: .topTrailing) {
                DebugBuildRibbon()
            }
            #endif
    }
}

#if DEBUG
/// Small corner marker shown only in debug builds (PTIMER-203) so a debug
/// install is visually distinguishable from release on screen, not just by
/// launcher icon/name. Auto-hides after 10s so it doesn't linger over
/// screenshots taken later in the session.
///
/// The ribbon owns its hide state: keeping it out of `ContentView`
/// means the auto-hide does not re-evaluate `ContentView.body` and
/// therefore does not run `ExposureCalculatorScreen.init()` again,
/// which would build a throwaway `WorkspaceCoordinator` (with its own
/// restore, persistence, and cleanup timers) beside the live one.
private struct DebugBuildRibbon: View {
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            ribbon
                .task {
                    try? await Task.sleep(for: .seconds(10))
                    isVisible = false
                }
        }
    }

    private var ribbon: some View {
        Text("DEBUG")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red)
            .padding(.top, 4)
            .padding(.trailing, 4)
    }
}
#endif

private extension PTimerComponentTheme {
    /// Maps the platform's UIKit semantic colors into the kit theme. The
    /// UIKit-backed color mapping lives here in the host app so PTimerKit
    /// stays platform-neutral.
    static let system = PTimerComponentTheme(
        surface: Color(.systemBackground),
        surfaceSecondary: Color(.secondarySystemBackground),
        surfaceTertiary: Color(.tertiarySystemBackground),
        recessedFill: Color(.tertiarySystemFill),
        separator: Color(.separator),
        accentRunning: Color(.systemGreen),
        accentInfo: Color(.systemBlue),
        accentWarning: Color(.systemOrange),
        // The graph's domain colors shipped as SwiftUI-native values
        // (.accentColor / .blue / .red / .green / .orange / .pink / .primary /
        // .secondary), so the kit's GraphPalette default reproduces the exact
        // shipping appearance — no UIKit-backed mapping is required here.
        graph: .default
    )
}
