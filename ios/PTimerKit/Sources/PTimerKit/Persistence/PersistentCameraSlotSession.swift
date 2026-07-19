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
    /// ND filter wheel stack (PTIMER-199), one entry per wheel in
    /// display order. Additive Optional: pre-stack snapshots omit the
    /// key and restore through the legacy scalar triple above. The
    /// legacy scalar fields keep being written alongside this array —
    /// carrying the explicitly selected MAXIMUM wheel — so an older
    /// app build downgrades to a valid single filter instead of
    /// falling back to defaults.
    public let ndStack: [PersistentNDFilterWheelSnapshot]?

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
        targetShutterSeconds: TimeInterval? = nil,
        ndStack: [PersistentNDFilterWheelSnapshot]? = nil
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
        self.ndStack = ndStack
    }

    private enum CodingKeys: String, CodingKey {
        case slotIDRaw
        case selectedPresetFilmID
        case selectedProfileID
        case baseShutterSeconds
        case ndStop
        case ndStopThirds
        case ndStopsExact
        case exposureScaleMode
        case customDisplayName
        case targetShutterSeconds
        case ndStack
    }

    /// Custom decode ONLY for `ndStack` isolation (PTIMER-199 §7): a
    /// malformed stack array — wrong type, or a wheel entry of the
    /// wrong shape — must decode as if the key were ABSENT rather
    /// than failing the whole snapshot, so the rest of the slot
    /// (base shutter, film, scale, legacy ND scalar) still restores
    /// and the ND value falls back through the legacy scalar path.
    /// Every other field decodes strictly, as before.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slotIDRaw = try container.decode(String.self, forKey: .slotIDRaw)
        selectedPresetFilmID = try container.decodeIfPresent(String.self, forKey: .selectedPresetFilmID)
        selectedProfileID = try container.decodeIfPresent(String.self, forKey: .selectedProfileID)
        baseShutterSeconds = try container.decodeIfPresent(Double.self, forKey: .baseShutterSeconds)
        ndStop = try container.decodeIfPresent(Int.self, forKey: .ndStop)
        ndStopThirds = try container.decodeIfPresent(Int.self, forKey: .ndStopThirds)
        ndStopsExact = try container.decodeIfPresent(Double.self, forKey: .ndStopsExact)
        exposureScaleMode = try container.decodeIfPresent(String.self, forKey: .exposureScaleMode)
        customDisplayName = try container.decodeIfPresent(String.self, forKey: .customDisplayName)
        targetShutterSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .targetShutterSeconds)
        ndStack = (try? container.decodeIfPresent(
            [PersistentNDFilterWheelSnapshot].self,
            forKey: .ndStack
        )) ?? nil
    }
}

/// One ND filter wheel in its on-disk shape (PTIMER-199). Reuses the
/// lossless triple discipline of the legacy scalar fields: exactly
/// one of `ndStop` (whole), `ndStopThirds` (reserved third-stop), or
/// `ndStopsExact` (commercial preset) is populated per wheel.
public struct PersistentNDFilterWheelSnapshot: Codable, Equatable {
    public let ndStop: Int?
    public let ndStopThirds: Int?
    public let ndStopsExact: Double?

    public init(ndStop: Int?, ndStopThirds: Int? = nil, ndStopsExact: Double? = nil) {
        self.ndStop = ndStop
        self.ndStopThirds = ndStopThirds
        self.ndStopsExact = ndStopsExact
    }

    /// Serialises one runtime wheel value using the same field split
    /// as the legacy scalar: whole → `ndStop`, reserved third-stop →
    /// `ndStopThirds`, supported commercial preset → its canonical
    /// `ndStopsExact`.
    public init(step: NDStep) {
        self.init(
            ndStop: step.wholeStops,
            ndStopThirds: step.isWholeStop || !step.isThirdStop
                ? nil : step.thirdStopCount,
            ndStopsExact: ExposureScale.commercialNDPresetStop(matching: step.stops)
        )
    }

    /// Restores the wheel value. EXACTLY ONE of the triple's fields
    /// must be populated — a conflicting entry (e.g. `ndStop` AND
    /// `ndStopsExact` together) is structurally corrupted and
    /// resolves to `nil`, as do reserved third-stop values and empty
    /// triples: stack wheels are restricted to the shipping ladder
    /// envelope (whole stops + presets, per the task spec), and any
    /// unresolvable wheel invalidates the WHOLE stack at the
    /// validation layer (reject, never clamp).
    public var restoredNDStep: NDStep? {
        let populatedFieldCount = [
            ndStop != nil,
            ndStopThirds != nil,
            ndStopsExact != nil,
        ].filter { $0 }.count
        guard populatedFieldCount == 1 else {
            return nil
        }
        if let exact = ndStopsExact {
            guard let canonical = ExposureScale.commercialNDPresetStop(matching: exact) else {
                return nil
            }
            return NDStep(stops: canonical)
        }
        if ndStopThirds != nil {
            return nil
        }
        if let ndStop {
            return NDStep(stops: Double(ndStop))
        }
        return nil
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
