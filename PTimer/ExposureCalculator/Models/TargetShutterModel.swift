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
/// First-iteration scope per `docs/tasks/PTIMER-25.md`: in-session
/// state only — no persistence across launches and no per-camera-slot
/// snapshot. The target is global to the current calculator session.
@MainActor
@Observable
final class TargetShutterModel {
    /// Photographer-supplied target duration in seconds. `nil` means
    /// inactive — no Target Shutter comparison or timer action is
    /// available.
    private(set) var targetSeconds: TimeInterval?

    /// Last positive target the photographer set anywhere in the
    /// current session. Survives slot switches and even
    /// `clear()` so the input sheet can pre-select the
    /// most-recent value when the active slot has no target. Updated
    /// only when `setTarget` accepts a positive value — clearing or
    /// restoring `nil` does not erase the memory.
    ///
    /// Resets when the app process terminates; persistence is
    /// intentionally per-slot via `CameraSlotCalculatorSnapshot`,
    /// so this in-session memory is a UX convenience and not a
    /// new persisted state surface.
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
    /// `lastUsedTargetSeconds` so the sheet can pre-fill it on the
    /// next open even after a `clear()`.
    func setTarget(_ seconds: TimeInterval?) {
        let sanitized = Self.sanitized(seconds)
        targetSeconds = sanitized
        if let sanitized {
            lastUsedTargetSeconds = sanitized
        }
    }

    /// Clears the target so the comparison path goes inert. Equivalent
    /// to `setTarget(nil)` but communicates intent at the call site.
    /// `lastUsedTargetSeconds` is preserved so re-opening the sheet
    /// still pre-fills the last value the photographer entered.
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
