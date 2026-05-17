import Foundation

/// Per-slot snapshot of the calculator working state. This carries the
/// fields the active slot would otherwise hold on `CalculatorModel` and
/// `FilmSelectionModel`; inactive slots keep their snapshot here so a
/// switch can restore the slot's exposure inputs and film selection
/// without touching reciprocity policy or preset data.
///
/// The snapshot deliberately does not include live preview overlays
/// (`liveBaseShutter` / `liveNDStep`). A live preview only exists while
/// the user is dragging a wheel on the active slot, so the inactive
/// snapshot stays clean.
struct CameraSlotCalculatorSnapshot: Equatable {
    var baseShutterSeconds: Double
    var ndStep: NDStep
    var scaleMode: ExposureScaleMode
    var selectedPresetFilm: FilmIdentity?
    var selectedProfileOverride: ReciprocityProfile?
    /// Optional Target Shutter duration captured per slot. `nil` means
    /// the photographer has not set a target on this slot — Target
    /// Shutter is part of each slot's shooting context (the same axis
    /// as base shutter / ND / film), not a global ViewModel concern,
    /// so a target set on Camera 1 must not bleed into Camera 2.
    var targetShutterSeconds: TimeInterval?

    /// Default snapshot used when a slot is initialized without prior
    /// state. Reads through `CalculatorDefaults` so a fresh slot is
    /// indistinguishable from a fresh app — one source of truth for
    /// shipping defaults across the ViewModel and slot snapshots.
    static let initial = CameraSlotCalculatorSnapshot(
        baseShutterSeconds: CalculatorDefaults.baseShutterSeconds,
        ndStep: CalculatorDefaults.ndStep,
        scaleMode: CalculatorDefaults.scaleMode,
        selectedPresetFilm: nil,
        selectedProfileOverride: nil,
        targetShutterSeconds: nil
    )
}
