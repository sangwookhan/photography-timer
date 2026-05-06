import Foundation

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
struct PersistentCameraSlotSessionSnapshot: Codable, Equatable {
    /// Stable schema version. Bumped when fields are removed or
    /// semantics change; additive Optional fields do not require a
    /// version bump.
    let schemaVersion: Int
    /// `CameraSlotID.rawValue` for the slot that was active at save
    /// time. Stored as `String` so an unknown future raw value
    /// decodes without exploding — the load layer falls back to
    /// `.camera1` when the raw value cannot be resolved.
    let activeSlotIDRaw: String
    /// Persistent snapshots represent visited or captured slot
    /// states. Unvisited slots are not stored — they restore as
    /// `CameraSlotCalculatorSnapshot.initial` (fresh defaults). This
    /// keeps the on-disk shape compact and avoids serialising
    /// "untouched defaults" that the runtime can already produce.
    let slots: [PersistentCameraSlotCalculatorSnapshot]

    /// Schema version the current implementation writes. Bump when
    /// changing the on-disk shape in a way that is not Optional-add.
    static let currentSchemaVersion: Int = 1
}

/// Per-slot calculator snapshot in its on-disk shape. Stores raw
/// identifiers (film id, profile id) instead of the runtime
/// `FilmIdentity` / `ReciprocityProfile` value types so the on-disk
/// format does not have to track every Codable detail of the
/// reciprocity domain. The runtime side resolves the ids back to
/// objects through the preset catalog and falls back to safe
/// "No film" semantics when an id no longer exists.
struct PersistentCameraSlotCalculatorSnapshot: Codable, Equatable {
    let slotIDRaw: String
    let selectedPresetFilmID: String?
    let selectedProfileID: String?
    let baseShutterSeconds: Double?
    /// Whole-stop ND value, kept for byte-for-byte parity with the
    /// legacy `PersistentExposureCalculatorContextSnapshot.ndStop`.
    let ndStop: Int?
    /// Count of one-third-stop increments for a fractional ND value.
    /// Mirrors the legacy `ndStopThirds` field so a fractional snapshot
    /// survives a relaunch without truncation.
    let ndStopThirds: Int?
    /// Persisted exposure-scale mode `rawValue`. Optional so legacy
    /// snapshots default to the shipping `.oneThirdStop` scale.
    let exposureScaleMode: String?

    init(
        slotIDRaw: String,
        selectedPresetFilmID: String?,
        selectedProfileID: String?,
        baseShutterSeconds: Double?,
        ndStop: Int?,
        ndStopThirds: Int? = nil,
        exposureScaleMode: String? = nil
    ) {
        self.slotIDRaw = slotIDRaw
        self.selectedPresetFilmID = selectedPresetFilmID
        self.selectedProfileID = selectedProfileID
        self.baseShutterSeconds = baseShutterSeconds
        self.ndStop = ndStop
        self.ndStopThirds = ndStopThirds
        self.exposureScaleMode = exposureScaleMode
    }
}

extension PersistentCameraSlotCalculatorSnapshot {
    /// Reconstructs the persisted ND value as an `NDStep`, preferring
    /// the fractional-safe `ndStopThirds` field when present.
    var restoredNDStep: NDStep? {
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
    /// `PersistentExposureCalculatorContextSnapshot.restoredScaleMode`
    /// so callers do not have to learn two restore conventions.
    var restoredScaleMode: ExposureScaleMode {
        guard let raw = exposureScaleMode,
              let mode = ExposureScaleMode(rawValue: raw) else {
            return .oneThirdStop
        }
        return mode
    }
}

/// Persistence boundary for the camera-slot session. Decoupled from
/// the legacy `ExposureCalculatorContextPersistenceStoring` because
/// the new schema captures all four slots, not just the active one;
/// the legacy store is read once at first launch as a migration
/// source and otherwise ignored.
protocol CameraSlotSessionPersistenceStoring {
    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot?
    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot)
    func clearSnapshot()
}

/// No-op store used by tests and any caller that wants to disable
/// persistence (e.g., the record-replay smoke test).
struct NoOpCameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring {
    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { nil }
    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) {}
    func clearSnapshot() {}
}

/// `UserDefaults`-backed store. Writes JSON under a dedicated key so
/// the legacy single-context persistence and the new multi-slot
/// session never share a key — prevents accidental cross-decode and
/// lets the migration step inspect both stores side by side.
struct UserDefaultsCameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.camera-slot-session.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey),
              let snapshot = try? decoder.decode(
                PersistentCameraSlotSessionSnapshot.self,
                from: data
              ) else {
            return nil
        }

        // Reject snapshots written by a future schema we do not
        // understand — return nil so the caller can fall back to
        // legacy migration or fresh defaults rather than acting on
        // misinterpreted data.
        guard snapshot.schemaVersion == PersistentCameraSlotSessionSnapshot.currentSchemaVersion else {
            return nil
        }

        return snapshot
    }

    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
