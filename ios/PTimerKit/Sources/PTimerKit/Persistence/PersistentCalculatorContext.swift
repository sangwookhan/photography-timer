// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Legacy single-context calculator persistence. **No longer the
/// source of truth** for camera-slot state — that role belongs to
/// `PersistentCameraSlotSessionSnapshot`, which captures all four
/// camera slots, not just the active one.
///
/// This snapshot survives for two reasons:
///   1. **First-launch-after-upgrade migration** — when a fresh
///      install of the slot-aware build runs against UserDefaults
///      that contains only this older shape, the ViewModel's
///      restore path falls back to this snapshot, applies its
///      values to the active slot, and the next persist writes the
///      new session snapshot. Subsequent launches read the session
///      snapshot and ignore this one.
///   2. **Forward compatibility window** — the active-slot writer in
///      `FilmSelectionModel.persistContext` continues writing here
///      so an older app version reading the legacy `UserDefaults`
///      key sees a sensible single-camera context instead of
///      nothing.
///
/// Treat this type as legacy schema. New fields belong on
/// `PersistentCameraSlotSessionSnapshot` /
/// `PersistentCameraSlotCalculatorSnapshot`.
public struct PersistentCalculatorContextSnapshot: Codable, Equatable {
    public let selectedPresetFilmID: String?
    public let baseShutterSeconds: Double?
    /// Whole-stop ND value, kept for byte-for-byte backward compat with
    /// PTIMER-79 snapshots. Populated only when the active ND value sits
    /// on a whole-stop boundary; fractional steps land in
    /// `ndStopThirds` instead.
    public let ndStop: Int?
    /// Count of one-third-stop increments for the persisted ND value.
    /// PTIMER-80 introduces this field so a `1/3` or `2/3` ND step
    /// survives a relaunch without being silently truncated to an
    /// integer. Optional so existing PTIMER-79 snapshots decode
    /// unchanged.
    public let ndStopThirds: Int?
    /// Persisted exposure-scale mode. Stored as the raw
    /// `ExposureScaleMode` value so the field survives later scale
    /// additions. Optional so legacy snapshots that predate the
    /// field decode unchanged and restore as the shipping
    /// `.oneThirdStop` scale (per `restoredScaleMode`).
    public let exposureScaleMode: String?
    /// Raw `CameraSlotID` for the slot that owned the persisted
    /// context at save time. Optional so older snapshots without
    /// slot awareness decode unchanged (and would restore into
    /// Camera 1 if the legacy fallback path were the only restore
    /// route).
    ///
    /// In the current build the new
    /// `PersistentCameraSlotSessionSnapshot` is the source of truth
    /// for slot identity on restore — this field is only consulted
    /// when no session snapshot exists yet (first launch after
    /// upgrade migration).
    public let activeCameraSlotIDRaw: String?

    public init(
        selectedPresetFilmID: String?,
        baseShutterSeconds: Double?,
        ndStop: Int?,
        ndStopThirds: Int? = nil,
        exposureScaleMode: String? = nil,
        activeCameraSlotIDRaw: String? = nil
    ) {
        self.selectedPresetFilmID = selectedPresetFilmID
        self.baseShutterSeconds = baseShutterSeconds
        self.ndStop = ndStop
        self.ndStopThirds = ndStopThirds
        self.exposureScaleMode = exposureScaleMode
        self.activeCameraSlotIDRaw = activeCameraSlotIDRaw
    }
}

extension PersistentCalculatorContextSnapshot {
    /// Reconstructs the persisted ND value as an `NDStep`, preferring
    /// the fractional-safe `ndStopThirds` field when present so a
    /// PTIMER-80 fractional snapshot decodes losslessly. Falls back to
    /// the legacy `ndStop` integer for PTIMER-79 snapshots.
    public var restoredNDStep: NDStep? {
        if let thirds = ndStopThirds {
            return NDStep.fromThirdStopCount(thirds)
        }
        if let ndStop {
            return NDStep(stops: Double(ndStop))
        }
        return nil
    }

    /// Decodes the persisted scale mode, defaulting to the shipping
    /// `.oneThirdStop` scale when the field is absent (legacy PTIMER-79 /
    /// pre-default-flip snapshot) or when the stored raw value is
    /// unrecognized (forward-compat: an unknown future mode rewinds
    /// safely to the shipping default). The shipping shutter ladder is
    /// a strict superset of the legacy full-stop ladder, so a legacy
    /// whole-stop value remains a valid ladder entry without rewriting
    /// it.
    public var restoredScaleMode: ExposureScaleMode {
        guard let raw = exposureScaleMode,
              let mode = ExposureScaleMode(rawValue: raw) else {
            return .oneThirdStop
        }
        return mode
    }
}

public protocol ExposureCalculatorContextStoring {
    func loadSnapshot() -> PersistentCalculatorContextSnapshot?
    func saveSnapshot(_ snapshot: PersistentCalculatorContextSnapshot)
    func clearSnapshot()
}

public struct NoOpCalculatorContextStore: ExposureCalculatorContextStoring {
    public init() {}
    public func loadSnapshot() -> PersistentCalculatorContextSnapshot? { nil }
    public func saveSnapshot(_ snapshot: PersistentCalculatorContextSnapshot) {}
    public func clearSnapshot() {}
}
