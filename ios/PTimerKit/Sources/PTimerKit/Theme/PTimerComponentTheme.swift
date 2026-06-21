// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Semantic surface / fill / accent tokens consumed by PTimerKit's reusable
/// SwiftUI components.
///
/// The kit is platform-neutral: components read these tokens from the
/// environment instead of reaching for UIKit-backed colors like
/// the UIKit `secondarySystemBackground` family. The host app maps the platform's
/// semantic colors into a theme value and injects it with
/// `.ptimerComponentTheme(_:)`; the `default` below is a SwiftUI-native
/// fallback so the kit builds and previews without a host.
public struct PTimerComponentTheme: Sendable {
    /// Base screen/background surface.
    public var surface: Color
    /// Raised card / grouped-cell surface.
    public var surfaceSecondary: Color
    /// Inset surface nested inside a secondary surface.
    public var surfaceTertiary: Color
    /// Recessed control fill (e.g. a value chip background).
    public var recessedFill: Color
    /// Hairline divider / border.
    public var separator: Color
    /// Accent for a running / active state.
    public var accentRunning: Color
    /// Accent for informational emphasis.
    public var accentInfo: Color
    /// Accent for a caution / paused state.
    public var accentWarning: Color
    /// Accent for an interactive action control (e.g. a start-timer glyph
    /// and its tinted background).
    public var timerActionAccent: Color
    /// Glyph color for a disabled action control.
    public var timerActionDisabledGlyph: Color
    /// Domain colors for the reciprocity graph component.
    public var graph: GraphPalette

    public init(
        surface: Color,
        surfaceSecondary: Color,
        surfaceTertiary: Color,
        recessedFill: Color,
        separator: Color,
        accentRunning: Color,
        accentInfo: Color,
        accentWarning: Color,
        timerActionAccent: Color = .accentColor,
        timerActionDisabledGlyph: Color = .secondary,
        graph: GraphPalette = .default
    ) {
        self.surface = surface
        self.surfaceSecondary = surfaceSecondary
        self.surfaceTertiary = surfaceTertiary
        self.recessedFill = recessedFill
        self.separator = separator
        self.accentRunning = accentRunning
        self.accentInfo = accentInfo
        self.accentWarning = accentWarning
        self.timerActionAccent = timerActionAccent
        self.timerActionDisabledGlyph = timerActionDisabledGlyph
        self.graph = graph
    }

    /// Semantic colors for the reciprocity graph. Kept as SwiftUI-native values
    /// so the kit stays platform-neutral; the host app may override them. The
    /// graph's domain colors were always SwiftUI-native (no UIKit), so the
    /// defaults below reproduce the shipping appearance.
    public struct GraphPalette: Sendable {
        /// The plotted reciprocity calculation curve.
        public var calculationCurve: Color
        /// Marker for the current result point.
        public var currentResultPoint: Color
        /// Guide line / shading for the current input.
        public var currentInputGuide: Color
        /// Source-reference data point markers.
        public var sourceReference: Color
        /// No-correction region shading and boundary.
        public var noCorrectionRegion: Color
        /// In-range supported region shading.
        public var supportedRegion: Color
        /// Region beyond the published source range.
        public var beyondSourceRegion: Color
        /// Region outside supported policy (unsupported).
        public var unsupportedRegion: Color
        /// Not-recommended boundary line.
        public var notRecommendedBoundary: Color
        /// Marker for values outside the visible range.
        public var outOfRangeMarker: Color
        /// Grid / axis / hairline guide lines.
        public var guideLine: Color
        /// Primary graph text.
        public var textPrimary: Color
        /// Secondary graph text (axis labels, captions).
        public var textSecondary: Color

        public init(
            calculationCurve: Color,
            currentResultPoint: Color,
            currentInputGuide: Color,
            sourceReference: Color,
            noCorrectionRegion: Color,
            supportedRegion: Color,
            beyondSourceRegion: Color,
            unsupportedRegion: Color,
            notRecommendedBoundary: Color,
            outOfRangeMarker: Color,
            guideLine: Color,
            textPrimary: Color,
            textSecondary: Color
        ) {
            self.calculationCurve = calculationCurve
            self.currentResultPoint = currentResultPoint
            self.currentInputGuide = currentInputGuide
            self.sourceReference = sourceReference
            self.noCorrectionRegion = noCorrectionRegion
            self.supportedRegion = supportedRegion
            self.beyondSourceRegion = beyondSourceRegion
            self.unsupportedRegion = unsupportedRegion
            self.notRecommendedBoundary = notRecommendedBoundary
            self.outOfRangeMarker = outOfRangeMarker
            self.guideLine = guideLine
            self.textPrimary = textPrimary
            self.textSecondary = textSecondary
        }

        /// SwiftUI-native defaults reproducing the shipping graph appearance.
        public static let `default` = GraphPalette(
            calculationCurve: .accentColor,
            currentResultPoint: .blue,
            currentInputGuide: .red,
            sourceReference: .green,
            noCorrectionRegion: .green,
            supportedRegion: .green,
            beyondSourceRegion: .pink,
            unsupportedRegion: .red,
            notRecommendedBoundary: .red,
            outOfRangeMarker: .orange,
            guideLine: .primary,
            textPrimary: .primary,
            textSecondary: .secondary
        )
    }

    /// SwiftUI-native fallback. Adaptive system colors are supplied by the host
    /// app; these approximations only exist so the kit is self-contained.
    public static let `default` = PTimerComponentTheme(
        surface: Color(white: 1.0),
        surfaceSecondary: Color(white: 0.95),
        surfaceTertiary: Color(white: 0.92),
        recessedFill: Color.gray.opacity(0.12),
        separator: Color.gray.opacity(0.30),
        accentRunning: .green,
        accentInfo: .blue,
        accentWarning: .orange
    )
}

private struct PTimerComponentThemeKey: EnvironmentKey {
    static let defaultValue = PTimerComponentTheme.default
}

public extension EnvironmentValues {
    /// Active component theme. Reusable kit components read this; the host app
    /// sets it with `.ptimerComponentTheme(_:)`.
    var ptimerComponentTheme: PTimerComponentTheme {
        get { self[PTimerComponentThemeKey.self] }
        set { self[PTimerComponentThemeKey.self] = newValue }
    }
}

public extension View {
    /// Injects the theme that PTimerKit components read from the environment.
    func ptimerComponentTheme(_ theme: PTimerComponentTheme) -> some View {
        environment(\.ptimerComponentTheme, theme)
    }
}
