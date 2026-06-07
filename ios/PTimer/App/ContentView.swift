import SwiftUI
import PTimerKit

struct ContentView: View {
    var body: some View {
        ExposureCalculatorScreen()
            .ptimerComponentTheme(.system)
    }
}

private extension PTimerComponentTheme {
    /// Maps the platform's UIKit semantic colors into the kit theme. The
    /// UIKit-backed color mapping lives here in the host app so PTimerKit
    /// stays platform-neutral.
    static let system = PTimerComponentTheme(
        surface: Color(.systemBackground),
        surfaceSecondary: Color(.secondarySystemBackground),
        surfaceTertiary: Color(.tertiarySystemBackground),
        surfaceGrouped: Color(.systemGroupedBackground),
        recessedFill: Color(.tertiarySystemFill),
        separator: Color(.separator),
        accentRunning: Color(.systemGreen),
        accentInfo: Color(.systemBlue),
        accentWarning: Color(.systemOrange),
        accentError: Color(.systemRed),
        accentNeutral: Color(.systemBrown),
        // The graph's domain colors shipped as SwiftUI-native values
        // (.accentColor / .blue / .red / .green / .orange / .pink / .primary /
        // .secondary), so the kit's GraphPalette default reproduces the exact
        // shipping appearance — no UIKit-backed mapping is required here.
        graph: .default
    )
}
