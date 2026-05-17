import Foundation
import Observation

/// `TargetShutterModel` owns the optional Target Shutter slice — the
/// photographer-supplied final exposure duration that the calculator
/// compares its current result against.
///
/// The model carries one piece of state: `targetSeconds`. `nil` means
/// inactive (no comparison). A non-nil value enables the comparison
/// path; the comparison value itself (Adjusted Shutter or Corrected
/// Exposure) flows in from the calc / reciprocity slices via
/// presenter input, never stored on this model.
///
/// Per-slot isolation is delegated to the snapshot layer:
/// `CameraSlotCalculatorSnapshot.targetShutterSeconds` carries each
/// slot's value, and the ViewModel's slot-switch handshake captures
/// the model into the outgoing slot's snapshot and reapplies the
/// incoming slot's snapshot via `setTarget(_:)`. This model therefore
/// holds only the active slot's value at any moment; a target set on
/// Camera 1 does not bleed into Camera 2.
///
/// Per-slot persistence across app relaunches is handled by
/// `PersistentCameraSlotCalculatorSnapshot`'s additive
/// `targetShutterSeconds` field. The same `isFinite && > 0`
/// sanitiser runs at decode time and inside `setTarget(_:)` so a
/// corrupted snapshot can never resurface as an invalid timer
/// duration.
@MainActor
@Observable
final class TargetShutterModel {
    /// Photographer-supplied target duration in seconds. `nil` means
    /// inactive — no Target Shutter comparison or timer action is
    /// available.
    private(set) var targetSeconds: TimeInterval?

    /// Last positive target the photographer set anywhere in the
    /// current session. Survives slot switches and even `clear()`.
    /// Updated only when `setTarget` accepts a positive value —
    /// clearing or restoring `nil` does not erase the memory.
    ///
    /// **Not wired to the input sheet's seed path.** This memory is
    /// shared across all camera slots (single `TargetShutterModel`
    /// instance), so using it as a fallback seed for an inactive
    /// slot would leak Camera 1's last value onto Camera 2. The
    /// sheet seeds only from the active slot's committed target;
    /// a slot with no committed target seeds to the default. The
    /// field is preserved here as a read-only accessor for tests
    /// and any future surface that explicitly wants session-global
    /// memory, but it must not be re-wired into per-slot UI.
    ///
    /// Resets when the app process terminates; per-slot relaunch
    /// persistence is the snapshot layer's job
    /// (`CameraSlotCalculatorSnapshot.targetShutterSeconds`).
    private(set) var lastUsedTargetSeconds: TimeInterval?

    var isActive: Bool {
        targetSeconds != nil
    }

    init(targetSeconds: TimeInterval? = nil) {
        self.targetSeconds = Self.sanitized(targetSeconds)
        self.lastUsedTargetSeconds = self.targetSeconds
    }

    /// Sets the target duration. Non-finite, zero, and negative values
    /// are rejected and clear the target back to `nil`. Centralised
    /// here so every entry point (UI, tests, future deep-link) gets
    /// the same validation. A positive value also updates
    /// `lastUsedTargetSeconds`, which is preserved for read-only
    /// callers but is **not** used as the input sheet's seed fallback
    /// (see `lastUsedTargetSeconds` docs for the slot-leak rationale).
    func setTarget(_ seconds: TimeInterval?) {
        let sanitized = Self.sanitized(seconds)
        targetSeconds = sanitized
        if let sanitized {
            lastUsedTargetSeconds = sanitized
        }
    }

    /// Clears the target so the comparison path goes inert. Equivalent
    /// to `setTarget(nil)` but communicates intent at the call site.
    /// `lastUsedTargetSeconds` is preserved (it tracks the last positive
    /// value the photographer set anywhere in the session) but, as
    /// documented on that field, is not consumed by the input sheet's
    /// seed path.
    func clear() {
        targetSeconds = nil
    }

    private static func sanitized(_ seconds: TimeInterval?) -> TimeInterval? {
        guard let seconds, seconds.isFinite, seconds > 0 else {
            return nil
        }
        return seconds
    }
}
