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
    /// `customDisplayNames` is loaded into the session model in
    /// bulk via `restoreCustomDisplayNames(_:)` so a relaunch does
    /// not have to re-derive labels from runtime defaults.
    struct RestoredSession {
        let activeSlotID: CameraSlotID
        let snapshotsBySlotID: [CameraSlotID: CameraSlotCalculatorSnapshot]
        let customDisplayNames: [CameraSlotID: String]
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
    ///
    /// `customDisplayNames` carries the photographer-supplied slot
    /// labels keyed by slot id. Slots with no entry persist no
    /// custom name (Optional field stays `nil`), so a session that
    /// never used the rename surface round-trips byte-for-byte with
    /// the pre-PTIMER-123 shape.
    func save(
        activeSlotID: CameraSlotID,
        activeSlotSnapshot: CameraSlotCalculatorSnapshot,
        inactiveSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot],
        customDisplayNames: [CameraSlotID: String] = [:]
    ) {
        var allSnapshots = inactiveSnapshots
        allSnapshots[activeSlotID] = activeSlotSnapshot

        // A slot the photographer renamed but never visited has no
        // calc snapshot in `inactiveSnapshots`. Without this fallback
        // the rename would silently drop on the next save — promote
        // those slots to a `.initial` calc snapshot so the persisted
        // entry can carry the custom name. Visited slots already
        // have a snapshot above and skip this branch.
        for slotID in customDisplayNames.keys where allSnapshots[slotID] == nil {
            allSnapshots[slotID] = .initial
        }

        let persistentSlots = allSnapshots
            .map { slotID, snapshot in
                persistentSnapshot(
                    for: slotID,
                    snapshot: snapshot,
                    customDisplayName: customDisplayNames[slotID]
                )
            }
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
        var customNames: [CameraSlotID: String] = [:]
        for entry in session.slots {
            guard let slotID = CameraSlotID(rawValue: entry.slotIDRaw) else {
                continue
            }
            resolved[slotID] = runtimeSnapshot(from: entry)
            if let raw = entry.customDisplayName {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    customNames[slotID] = trimmed
                }
            }
        }
        return RestoredSession(
            activeSlotID: activeSlotID,
            snapshotsBySlotID: resolved,
            customDisplayNames: customNames
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
        snapshot: CameraSlotCalculatorSnapshot,
        customDisplayName: String?
    ) -> PersistentCameraSlotCalculatorSnapshot {
        // Trim whitespace at write time so the on-disk shape matches
        // what `CameraSlotIdentity.displayName` would render. An
        // empty trimmed value persists as `nil` so the steady-state
        // "no custom name" snapshot stays byte-for-byte compatible
        // with pre-PTIMER-123 records.
        let trimmedCustomName: String? = {
            guard let raw = customDisplayName else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        return PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: slotID.rawValue,
            selectedPresetFilmID: snapshot.selectedPresetFilm?.id,
            selectedProfileID: snapshot.selectedProfileOverride?.id,
            baseShutterSeconds: snapshot.baseShutterSeconds,
            ndStop: snapshot.ndStep.wholeStops,
            ndStopThirds: snapshot.ndStep.isWholeStop ? nil : snapshot.ndStep.thirdStopCount,
            // Persist `nil` for the shipping `.oneThirdStop` so a
            // steady-state snapshot stays compact, mirroring the
            // legacy convention.
            exposureScaleMode: snapshot.scaleMode == .oneThirdStop ? nil : snapshot.scaleMode.rawValue,
            customDisplayName: trimmedCustomName
        )
    }
}
