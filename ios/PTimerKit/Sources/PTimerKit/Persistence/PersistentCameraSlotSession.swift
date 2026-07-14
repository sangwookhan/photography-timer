// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// On-disk shape of the camera-slot session. Captures every slot's
/// calculator snapshot plus which slot was active at save time so a
/// relaunch restores all four pages, not just the one the user was
/// on. Distinct from the runtime `CameraSlotSessionModel` /
/// `CameraSlotCalculatorSnapshot` types so the persistence schema can
/// evolve without forcing the domain types into `Codable`.
///
/// Schema versioning lets a future migration step diverge the on-disk
/// format from the runtime types without flooding the call sites with
/// `try?` decode noise — the storing layer rejects unknown versions.
public struct PersistentCameraSlotSessionSnapshot: Codable, Equatable {
    /// Stable schema version. Bumped when fields are removed or
    /// semantics change; additive Optional fields do not require a
    /// version bump.
    public let schemaVersion: Int
    /// `CameraSlotID.rawValue` for the slot that was active at save
    /// time. Stored as `String` so an unknown future raw value
    /// decodes without exploding — the load layer falls back to
    /// `.camera1` when the raw value cannot be resolved.
    public let activeSlotIDRaw: String
    /// Persistent snapshots represent visited or captured slot
    /// states. Unvisited slots are not stored — they restore as
    /// `CameraSlotCalculatorSnapshot.initial` (fresh defaults). This
    /// keeps the on-disk shape compact and avoids serialising
    /// "untouched defaults" that the runtime can already produce.
    public let slots: [PersistentCameraSlotCalculatorSnapshot]

    /// Schema version the current implementation writes. Bump when
    /// changing the on-disk shape in a way that is not Optional-add.
    public static let currentSchemaVersion: Int = 1
    public init(schemaVersion: Int, activeSlotIDRaw: String, slots: [PersistentCameraSlotCalculatorSnapshot]) {
        self.schemaVersion = schemaVersion
        self.activeSlotIDRaw = activeSlotIDRaw
        self.slots = slots
    }
}

/// Per-slot calculator snapshot in its on-disk shape. Stores raw
/// identifiers (film id, profile id) instead of the runtime
/// `FilmIdentity` / `ReciprocityProfile` value types so the on-disk
/// format does not have to track every Codable detail of the
/// reciprocity domain. The runtime side resolves the ids back to
/// objects through the preset catalog and falls back to safe
/// "No film" semantics when an id no longer exists.
public struct PersistentCameraSlotCalculatorSnapshot: Codable, Equatable {
    public let slotIDRaw: String
    public let selectedPresetFilmID: String?
    public let selectedProfileID: String?
    public let baseShutterSeconds: Double?
    /// Whole-stop ND value, kept for byte-for-byte parity with the
    /// legacy `PersistentCalculatorContextSnapshot.ndStop`.
    public let ndStop: Int?
    /// Count of one-third-stop increments for a reserved third-stop ND
    /// value. Mirrors the legacy `ndStopThirds` field so a third-stop
    /// snapshot survives a relaunch without truncation. (Commercial
    /// presets use `ndStopsExact` instead.)
    public let ndStopThirds: Int?
    /// Exact ND strength in stops for a supported commercial preset
    /// (PTIMER-209: 6.6, 7.6, 16.6) — values that are neither whole nor
    /// on the third-stop grid. Additive Optional: whole-stop and
    /// third-stop snapshots leave it `nil`, so a pre-PTIMER-209 record
    /// stays backward-compatible and simply omits this key. Preferred by
    /// `restoredNDStep` (when it matches a preset) so 6.6 is not
    /// truncated to 6 2/3.
    public let ndStopsExact: Double?
    /// Persisted exposure-scale mode `rawValue`. Optional so legacy
    /// snapshots default to the shipping `.oneThirdStop` scale.
    public let exposureScaleMode: String?
    /// Photographer-supplied display name for this slot. Optional so
    /// a slot left at its canonical `Camera N` label persists no
    /// custom entry — the field is additive and pre-PTIMER-123
    /// snapshots decode unchanged. The decode path treats
    /// whitespace-only values as "no custom name" to mirror the
    /// editing path; the load layer also performs that trim before
    /// handing values to `CameraSlotSessionModel`.
    public let customDisplayName: String?
    /// Optional per-slot Target Shutter duration in seconds. Additive
    /// field — pre-PTIMER-25 snapshots decode unchanged with `nil`
    /// (target inactive). `nil` round-trips through the runtime as
    /// "no target set"; a positive finite value means the
    /// photographer has a target locked in for this slot.
    public let targetShutterSeconds: TimeInterval?

    public init(
        slotIDRaw: String,
        selectedPresetFilmID: String?,
        selectedProfileID: String?,
        baseShutterSeconds: Double?,
        ndStop: Int?,
        ndStopThirds: Int? = nil,
        ndStopsExact: Double? = nil,
        exposureScaleMode: String? = nil,
        customDisplayName: String? = nil,
        targetShutterSeconds: TimeInterval? = nil
    ) {
        self.slotIDRaw = slotIDRaw
        self.selectedPresetFilmID = selectedPresetFilmID
        self.selectedProfileID = selectedProfileID
        self.baseShutterSeconds = baseShutterSeconds
        self.ndStop = ndStop
        self.ndStopThirds = ndStopThirds
        self.ndStopsExact = ndStopsExact
        self.exposureScaleMode = exposureScaleMode
        self.customDisplayName = customDisplayName
        self.targetShutterSeconds = targetShutterSeconds
    }
}

extension PersistentCameraSlotCalculatorSnapshot {
    /// Reconstructs the persisted ND value as an `NDStep`. Prefers the
    /// exact-stops field, but only when it matches a supported
    /// commercial preset (PTIMER-209) — an unsupported value is ignored
    /// and falls through to the fractional-safe `ndStopThirds`, then the
    /// legacy whole-stop `ndStop`. A near-match is normalized to the
    /// canonical preset value rather than restored as a drifting double.
    public var restoredNDStep: NDStep? {
        if let exact = ndStopsExact,
           let canonical = ExposureScale.commercialNDPresetStop(matching: exact) {
            return NDStep(stops: canonical)
        }
        if let thirds = ndStopThirds {
            return NDStep.fromThirdStopCount(thirds)
        }
        if let ndStop {
            return NDStep(stops: Double(ndStop))
        }
        return nil
    }

    /// Decodes the persisted scale mode, defaulting to the shipping
    /// `.oneThirdStop` scale when the field is absent or
    /// unrecognised. Mirrors
    /// `PersistentCalculatorContextSnapshot.restoredScaleMode`
    /// so callers do not have to learn two restore conventions.
    public var restoredScaleMode: ExposureScaleMode {
        guard let raw = exposureScaleMode,
              let mode = ExposureScaleMode(rawValue: raw) else {
            return .oneThirdStop
        }
        return mode
    }
}

/// Persistence boundary for the camera-slot session. Decoupled from
/// the legacy `ExposureCalculatorContextStoring` because
/// the new schema captures all four slots, not just the active one;
/// the legacy store is read once at first launch as a migration
/// source and otherwise ignored.
public protocol CameraSlotSessionPersistenceStoring {
    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot?
    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot)
    func clearSnapshot()
}

/// No-op store used by tests and any caller that wants to disable
/// persistence (e.g., the record-replay smoke test).
public struct NoOpCameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring {
    public init() {}
    public func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { nil }
    public func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) {}
    public func clearSnapshot() {}
}
