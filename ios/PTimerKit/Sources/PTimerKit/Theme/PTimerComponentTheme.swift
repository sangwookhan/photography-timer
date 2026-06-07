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
    /// Grouped-list background.
    public var surfaceGrouped: Color
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
    /// Accent for an error / destructive state.
    public var accentError: Color
    /// Neutral accent for secondary identity tints.
    public var accentNeutral: Color

    public init(
        surface: Color,
        surfaceSecondary: Color,
        surfaceTertiary: Color,
        surfaceGrouped: Color,
        recessedFill: Color,
        separator: Color,
        accentRunning: Color,
        accentInfo: Color,
        accentWarning: Color,
        accentError: Color,
        accentNeutral: Color
    ) {
        self.surface = surface
        self.surfaceSecondary = surfaceSecondary
        self.surfaceTertiary = surfaceTertiary
        self.surfaceGrouped = surfaceGrouped
        self.recessedFill = recessedFill
        self.separator = separator
        self.accentRunning = accentRunning
        self.accentInfo = accentInfo
        self.accentWarning = accentWarning
        self.accentError = accentError
        self.accentNeutral = accentNeutral
    }

    /// SwiftUI-native fallback. Adaptive system colors are supplied by the host
    /// app; these approximations only exist so the kit is self-contained.
    public static let `default` = PTimerComponentTheme(
        surface: Color(white: 1.0),
        surfaceSecondary: Color(white: 0.95),
        surfaceTertiary: Color(white: 0.92),
        surfaceGrouped: Color(white: 0.95),
        recessedFill: Color.gray.opacity(0.12),
        separator: Color.gray.opacity(0.30),
        accentRunning: .green,
        accentInfo: .blue,
        accentWarning: .orange,
        accentError: .red,
        accentNeutral: .brown
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
