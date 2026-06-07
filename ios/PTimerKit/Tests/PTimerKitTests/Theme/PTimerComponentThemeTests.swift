import SwiftUI
import XCTest
@testable import PTimerKit

/// Foundation coverage for the reusable-component theme token layer (C8a).
/// The kit ships a SwiftUI-native fallback and exposes a public token API so
/// the host app can inject platform semantic colors without the kit touching
/// UIKit.
final class PTimerComponentThemeTests: XCTestCase {
    func testDefaultThemeIsAvailableAndDistinctAccents() {
        let theme = PTimerComponentTheme.default
        // Accents are distinct semantic roles, not the same color reused.
        let accents: Set<Color> = [
            theme.accentRunning,
            theme.accentInfo,
            theme.accentWarning,
            theme.accentError,
        ]
        XCTAssertEqual(accents.count, 4)
    }

    func testCustomThemeRoundTripsTokens() {
        let theme = PTimerComponentTheme(
            surface: .white,
            surfaceSecondary: .gray,
            surfaceTertiary: .gray,
            surfaceGrouped: .gray,
            recessedFill: .gray,
            separator: .gray,
            accentRunning: .green,
            accentInfo: .blue,
            accentWarning: .orange,
            accentError: .red,
            accentNeutral: .brown
        )
        XCTAssertEqual(theme.accentRunning, .green)
        XCTAssertEqual(theme.separator, .gray)
    }
}
