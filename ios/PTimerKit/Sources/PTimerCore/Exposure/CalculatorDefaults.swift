import Foundation

/// Shipping defaults for a fresh calculator surface (a brand-new
/// camera slot, the digital workflow before the user touches a wheel,
/// the post-reset working context). One source of truth so the
/// ViewModel, fresh-slot snapshot factory, and any future surface
/// (lock-screen widget reset, settings restore-defaults) read the same
/// values.
public enum CalculatorDefaults {
    /// Base shutter the calculator opens with. `1/30 s` matches the
    /// shipping shutter ladder's default selection per
    /// `docs/specs/Calculator.md`.
    public static let baseShutterSeconds: Double = 1.0 / 30.0

    /// ND stop the calculator opens with. Whole-stop zero — the
    /// calculator presents "no ND" by default.
    public static let ndStop: Int = 0

    /// Canonical fractional ND value matching `ndStop`.
    public static let ndStep: NDStep = NDStep(stops: Double(CalculatorDefaults.ndStop))

    /// Active exposure scale for fresh surfaces. One-third-stop is the
    /// shipping mode per `docs/specs/Calculator.md` §1.4.
    public static let scaleMode: ExposureScaleMode = .oneThirdStop
}
