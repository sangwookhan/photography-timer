import Foundation

/// Bridges the runtime camera-slot session and the on-disk
/// `PersistentCameraSlotSessionSnapshot` format. Owns the
/// serialise/deserialise logic so the ViewModel stays a thin facade
/// and the camera-slot persistence rules live in one testable place.
///
/// First-launch-after-upgrade migration is handled implicitly: when
/// no session snapshot exists, `loadSession()` returns nil and the
/// ViewModel falls back to the legacy single-context restore path
/// (which already sanitises out-of-range stored values). That same
/// path then calls `save(...)` on this controller, persisting the
/// migrated state under the new schema. From the second launch on,
/// the session snapshot is the source of truth and the legacy store
/// is ignored.
struct CameraSlotSessionPersistenceController {
    let sessionStore: CameraSlotSessionPersistenceStoring
    let presetFilms: [FilmIdentity]

    /// Restored session ready to apply to the runtime. The active
    /// slot's snapshot is included in `inactiveSnapshots` even though
    /// it logically lives on the live calc/film models — the caller
    /// pulls it out and applies it to those models, then loads the
    /// remaining entries via
    /// `CameraSlotSessionModel.restoreInactiveSnapshots(_:)`.
    struct RestoredSession {
        let activeSlotID: CameraSlotID
        let snapshotsBySlotID: [CameraSlotID: CameraSlotCalculatorSnapshot]
    }

    /// Loads the new session snapshot, or `nil` when none exists.
    /// First-launch-after-upgrade migration is the caller's
    /// responsibility (it falls back to the legacy restore path,
    /// which sanitises bad values; subsequent `save(...)` calls
    /// from this controller capture the migrated state).
    func loadSession() -> RestoredSession? {
        guard let session = sessionStore.loadSnapshot() else {
            return nil
        }
        return restoredSession(from: session)
    }

    /// Persists the current runtime session. Always writes the new
    /// schema; the legacy store stays read-only after first launch
    /// (its writer in `FilmSelectionModel` continues for the active
    /// slot, but session restore now ignores it).
    func save(
        activeSlotID: CameraSlotID,
        activeSlotSnapshot: CameraSlotCalculatorSnapshot,
        inactiveSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot]
    ) {
        var allSnapshots = inactiveSnapshots
        allSnapshots[activeSlotID] = activeSlotSnapshot

        let persistentSlots = allSnapshots
            .map { slotID, snapshot in persistentSnapshot(for: slotID, snapshot: snapshot) }
            .sorted { $0.slotIDRaw < $1.slotIDRaw }

        sessionStore.saveSnapshot(
            PersistentCameraSlotSessionSnapshot(
                schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
                activeSlotIDRaw: activeSlotID.rawValue,
                slots: persistentSlots
            )
        )
    }

    func clear() {
        sessionStore.clearSnapshot()
    }

    // MARK: - Restore helpers

    private func restoredSession(
        from session: PersistentCameraSlotSessionSnapshot
    ) -> RestoredSession {
        let activeSlotID = CameraSlotID(rawValue: session.activeSlotIDRaw) ?? .camera1
        var resolved: [CameraSlotID: CameraSlotCalculatorSnapshot] = [:]
        for entry in session.slots {
            guard let slotID = CameraSlotID(rawValue: entry.slotIDRaw) else {
                continue
            }
            resolved[slotID] = runtimeSnapshot(from: entry)
        }
        return RestoredSession(
            activeSlotID: activeSlotID,
            snapshotsBySlotID: resolved
        )
    }

    // MARK: - Persistent ↔ runtime conversion

    /// Resolves a persistent slot snapshot back into the runtime
    /// `CameraSlotCalculatorSnapshot`. Invalid film/profile ids are
    /// silently dropped — a slot whose persisted film no longer
    /// exists in the catalog restores as "No film" rather than
    /// crashing or mislabelling state.
    private func runtimeSnapshot(
        from entry: PersistentCameraSlotCalculatorSnapshot
    ) -> CameraSlotCalculatorSnapshot {
        let film: FilmIdentity? = entry.selectedPresetFilmID
            .flatMap { id in presetFilms.first { $0.id == id } }

        let profile: ReciprocityProfile? = {
            guard let film,
                  let profileID = entry.selectedProfileID else {
                return nil
            }
            // Preset profiles live on the FilmIdentity; use them as
            // the catalog. Unknown profile id ⇒ drop the override.
            if let preset = film.profiles.first(where: { $0.id == profileID }) {
                return preset
            }
            // The Unofficial-practical override surface lives outside
            // `film.profiles`; reach into the catalog for those.
            if let unofficial = UnofficialPracticalProfiles.profile(forFilmID: film.id),
               unofficial.id == profileID {
                return unofficial
            }
            return nil
        }()

        return CameraSlotCalculatorSnapshot(
            baseShutterSeconds: entry.baseShutterSeconds ?? CalculatorDefaults.baseShutterSeconds,
            ndStep: entry.restoredNDStep ?? CalculatorDefaults.ndStep,
            scaleMode: entry.restoredScaleMode,
            selectedPresetFilm: film,
            selectedProfileOverride: profile
        )
    }

    private func persistentSnapshot(
        for slotID: CameraSlotID,
        snapshot: CameraSlotCalculatorSnapshot
    ) -> PersistentCameraSlotCalculatorSnapshot {
        PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: slotID.rawValue,
            selectedPresetFilmID: snapshot.selectedPresetFilm?.id,
            selectedProfileID: snapshot.selectedProfileOverride?.id,
            baseShutterSeconds: snapshot.baseShutterSeconds,
            ndStop: snapshot.ndStep.wholeStops,
            ndStopThirds: snapshot.ndStep.isWholeStop ? nil : snapshot.ndStep.thirdStopCount,
            // Persist `nil` for the shipping `.oneThirdStop` so a
            // steady-state snapshot stays compact, mirroring the
            // legacy convention.
            exposureScaleMode: snapshot.scaleMode == .oneThirdStop ? nil : snapshot.scaleMode.rawValue
        )
    }
}
