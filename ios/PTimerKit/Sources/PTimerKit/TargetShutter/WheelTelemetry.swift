import SwiftUI

/// App-injected live wheel telemetry seam.
///
/// PTimerKit's wheel pickers (e.g. the Target Shutter sheet) update their
/// committed selection only when the platform wheel settles. To drive a live
/// mid-spin readout the host app can observe the platform wheel's centre row
/// while it moves and feed those row indices back in — but that observation
/// needs platform APIs the kit deliberately does not depend on.
///
/// This seam keeps that dependency in the host: the kit asks for a background
/// `View` that reports a wheel's live centre-row index, and the host supplies
/// the implementation (wrapped in `AnyView`). The kit places that view behind
/// each wheel and maps the reported row index to a value; it never sees how
/// the value is observed. The default is `none` — no live telemetry,
/// settle-only updates — so the kit builds and previews without a host.
public struct WheelTelemetry {
    /// Builds a background view that reports the nearest wheel's live
    /// centre-row index. The kit places the returned view behind a wheel and
    /// calls into its model from `onRow` as the wheel moves.
    public var makeObserver: (_ onRow: @escaping (Int) -> Void) -> AnyView

    public init(makeObserver: @escaping (_ onRow: @escaping (Int) -> Void) -> AnyView) {
        self.makeObserver = makeObserver
    }

    /// No live telemetry — wheels report only on settle. The kit default when
    /// the host injects nothing.
    public static let none = WheelTelemetry { _ in AnyView(EmptyView()) }
}

private struct WheelTelemetryKey: EnvironmentKey {
    static let defaultValue = WheelTelemetry.none
}

public extension EnvironmentValues {
    /// Active live-wheel telemetry. Kit wheel views read this; the host app
    /// supplies it with `.wheelTelemetry(_:)`.
    var wheelTelemetry: WheelTelemetry {
        get { self[WheelTelemetryKey.self] }
        set { self[WheelTelemetryKey.self] = newValue }
    }
}

public extension View {
    /// Injects the live-wheel telemetry that kit wheel views read from the
    /// environment. The host owns the observer implementation.
    func wheelTelemetry(_ telemetry: WheelTelemetry) -> some View {
        environment(\.wheelTelemetry, telemetry)
    }
}
