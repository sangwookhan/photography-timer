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

    func testDefaultGraphPaletteReproducesShippingColors() {
        let graph = PTimerComponentTheme.GraphPalette.default
        // The graph's domain colors shipped as SwiftUI-native values; the
        // default palette must reproduce them so the host needs no UIKit map.
        XCTAssertEqual(graph.calculationCurve, .accentColor)
        XCTAssertEqual(graph.currentResultPoint, .blue)
        XCTAssertEqual(graph.currentInputGuide, .red)
        XCTAssertEqual(graph.sourceReference, .green)
        XCTAssertEqual(graph.beyondSourceRegion, .pink)
        XCTAssertEqual(graph.outOfRangeMarker, .orange)
        XCTAssertEqual(graph.textSecondary, .secondary)
    }

    func testCustomGraphPaletteRoundTripsThroughTheme() {
        var theme = PTimerComponentTheme.default
        theme.graph = PTimerComponentTheme.GraphPalette(
            calculationCurve: .mint,
            currentResultPoint: .teal,
            currentInputGuide: .pink,
            sourceReference: .indigo,
            noCorrectionRegion: .cyan,
            supportedRegion: .cyan,
            beyondSourceRegion: .purple,
            unsupportedRegion: .red,
            notRecommendedBoundary: .orange,
            outOfRangeMarker: .yellow,
            guideLine: .gray,
            textPrimary: .black,
            textSecondary: .gray
        )
        // A reusable component reads these tokens through the theme; the
        // override must survive intact.
        XCTAssertEqual(theme.graph.calculationCurve, .mint)
        XCTAssertEqual(theme.graph.currentResultPoint, .teal)
        XCTAssertEqual(theme.graph.outOfRangeMarker, .yellow)
        XCTAssertEqual(theme.graph.textPrimary, .black)
    }
}
