import Foundation
import PTimerKit

/// Pure value planner for calculator-context restore. Reads the
/// outputs of `CameraSlotSessionPersistenceController.loadSession()`
/// and `FilmSelectionModel.restoreContext()` and packages them into
/// a `RestorePlan` that the ViewModel applies in order. Performs no
/// side effects: every persistence read, model mutation, and
/// `applyCameraSlotSnapshot(...)` call stays on the ViewModel.
struct CalculatorContextRestorePlanBuilder {

    struct RestorePlan {
        enum Source {
            /// Multi-slot session snapshot loaded by
            /// `CameraSlotSessionPersistenceController`. Carries the
            /// active slot's snapshot pre-separated from the inactive
            /// map so the ViewModel can apply restoration in the
            /// persist-ordering-safe sequence (active id, inactive
            /// snapshots, custom names, active snapshot apply).
            case session(SessionRestorePlan)
            /// Legacy single-context fallback when no session snapshot
            /// exists. The calc inputs have already been sanitised
            /// against the active scale's ladder and the ND range.
            case legacy(LegacyRestorePlan)
        }

        let source: Source
    }

    struct SessionRestorePlan {
        let activeSlotID: CameraSlotID
        let activeSlotSnapshot: CameraSlotCalculatorSnapshot
        let inactiveSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot]
        let customDisplayNames: [CameraSlotID: String]
    }

    struct LegacyRestorePlan {
        let activeCameraSlotID: CameraSlotID?
        /// True when the persisted snapshot referenced a film id that
        /// is no longer in the catalog. The ViewModel restores the
        /// active slot id but skips applying the calc inputs.
        let hadInvalidFilmReference: Bool
        /// Sanitised base shutter, or `nil` to fall back to the
        /// shipping default at apply time.
        let baseShutterSeconds: Double?
        /// Sanitised ND step, or `nil` to fall back to the shipping
        /// default at apply time.
        let ndStep: NDStep?
        let scaleMode: ExposureScaleMode
    }

    func plan(
        from session: CameraSlotSessionPersistenceController.RestoredSession
    ) -> RestorePlan {
        var snapshotsBySlotID = session.snapshotsBySlotID
        let activeSnapshot = snapshotsBySlotID.removeValue(forKey: session.activeSlotID)
            ?? .initial
        return RestorePlan(
            source: .session(
                SessionRestorePlan(
                    activeSlotID: session.activeSlotID,
                    activeSlotSnapshot: activeSnapshot,
                    inactiveSnapshots: snapshotsBySlotID,
                    customDisplayNames: session.customDisplayNames
                )
            )
        )
    }

    func plan(
        fromLegacy restored: FilmSelectionModel.RestoredContext
    ) -> RestorePlan {
        RestorePlan(
            source: .legacy(
                LegacyRestorePlan(
                    activeCameraSlotID: restored.activeCameraSlotID,
                    hadInvalidFilmReference: restored.hadInvalidFilmReference,
                    baseShutterSeconds: Self.sanitizedBaseShutter(
                        from: restored.baseShutterSeconds,
                        mode: restored.scaleMode
                    ),
                    ndStep: Self.sanitizedNDStep(from: restored.ndStep),
                    scaleMode: restored.scaleMode
                )
            )
        )
    }

    /// Matches a stored base-shutter value against the active scale's
    /// shutter ladder so a one-third-stop value (e.g.,
    /// `(1/30) · 2^(1/3)`) round-trips after a relaunch in 1/3-stop
    /// mode. Returns `nil` for out-of-ladder or absent values.
    static func sanitizedBaseShutter(
        from storedValue: Double?,
        mode: ExposureScaleMode = .oneThirdStop
    ) -> Double? {
        guard let storedValue else {
            return nil
        }
        return ExposureScale.scale(for: mode).shutterSteps.first {
            abs($0.seconds - storedValue) <= ExposureCalculator.stabilityEpsilon
        }?.seconds
    }

    /// Rejects ND values outside the 0…30 stop range supported by the
    /// shipping picker. One-third-stop values inherit the same
    /// envelope.
    static func sanitizedNDStep(from storedValue: NDStep?) -> NDStep? {
        guard let storedValue else {
            return nil
        }
        guard storedValue.stops >= -ExposureCalculator.stabilityEpsilon,
              storedValue.stops <= Double(ExposureScale.maximumWholeNDStops) + ExposureCalculator.stabilityEpsilon else {
            return nil
        }
        return storedValue
    }
}
