// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

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
public struct CameraSlotSessionPersistenceController {
    public let sessionStore: CameraSlotSessionPersistenceStoring
    public let presetFilms: [FilmIdentity]
    /// Closure that surfaces the photographer's custom
    /// film library at session restore time. `runtimeSnapshot(from:)`
    /// resolves persisted film ids against the preset catalog first
    /// (cheaper, immutable) and falls back to this closure so a
    /// custom film selected before relaunch is restored on the right
    /// slot. Default `{ [] }` preserves the legacy
    /// empty-list behavior for callers that pre-date custom films.
    public let currentCustomFilms: () -> [FilmIdentity]

    public init(
        sessionStore: CameraSlotSessionPersistenceStoring,
        presetFilms: [FilmIdentity],
        currentCustomFilms: @escaping () -> [FilmIdentity] = { [] }
    ) {
        self.sessionStore = sessionStore
        self.presetFilms = presetFilms
        self.currentCustomFilms = currentCustomFilms
    }

    /// Restored session ready to apply to the runtime. The active
    /// slot's snapshot is included in `inactiveSnapshots` even though
    /// it logically lives on the live calc/film models — the caller
    /// pulls it out and applies it to those models, then loads the
    /// remaining entries via
    /// `CameraSlotSessionModel.restoreInactiveSnapshots(_:)`.
    /// `customDisplayNames` is loaded into the session model in
    /// bulk via `restoreCustomDisplayNames(_:)` so a relaunch does
    /// not have to re-derive labels from runtime defaults.
    public struct RestoredSession {
        public let activeSlotID: CameraSlotID
        public let snapshotsBySlotID: [CameraSlotID: CameraSlotCalculatorSnapshot]
        public let customDisplayNames: [CameraSlotID: String]
        public init(activeSlotID: CameraSlotID, snapshotsBySlotID: [CameraSlotID: CameraSlotCalculatorSnapshot], customDisplayNames: [CameraSlotID: String]) {
            self.activeSlotID = activeSlotID
            self.snapshotsBySlotID = snapshotsBySlotID
            self.customDisplayNames = customDisplayNames
        }
    }

    /// Loads the new session snapshot, or `nil` when none exists.
    /// First-launch-after-upgrade migration is the caller's
    /// responsibility (it falls back to the legacy restore path,
    /// which sanitises bad values; subsequent `save(...)` calls
    /// from this controller capture the migrated state).
    public func loadSession() -> RestoredSession? {
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
    public func save(
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

    public func clear() {
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
        let film: FilmIdentity? = entry.selectedPresetFilmID.flatMap { id in
            // Preset catalog first (immutable, cheap), then the
            // user-authored custom library. A persisted id that
            // matches neither resolves to "No film", same as the
            // legacy behavior — the slot stays usable instead of
            // dangling on a deleted film reference.
            if let preset = presetFilms.first(where: { $0.id == id }) {
                return preset
            }
            return currentCustomFilms().first { $0.id == id }
        }

        let profile: ReciprocityProfile? = {
            guard let film,
                  let profileID = entry.selectedProfileID else {
                return nil
            }
            // Preset profiles live on the FilmIdentity; use them as
            // the catalog. Unknown profile id ⇒ drop the override.
            // PTIMER-158: a persisted community/practical (unofficial)
            // override is now hidden, so normalize it back to the film's
            // primary official profile by dropping it here.
            if let preset = film.profiles.first(where: { $0.id == profileID }) {
                return preset.source.authority == .unofficial ? nil : preset
            }
            // Alternate models (unofficial practical, app-derived
            // formula) live outside `film.profiles`; reach into the
            // registry to reconstruct a persisted override by id — but
            // only for still-visible (non-unofficial) models.
            if let alternate = AlternateReciprocityModels.profile(withID: profileID),
               alternate.source.authority != .unofficial {
                return alternate
            }
            return nil
        }()

        return CameraSlotCalculatorSnapshot(
            baseShutterSeconds: entry.baseShutterSeconds ?? CalculatorDefaults.baseShutterSeconds,
            ndStep: entry.restoredNDStep ?? CalculatorDefaults.ndStep,
            scaleMode: entry.restoredScaleMode,
            selectedPresetFilm: film,
            selectedProfileOverride: profile,
            targetShutterSeconds: sanitizedTargetShutterSeconds(entry.targetShutterSeconds)
        )
    }

    /// Re-sanitises a persisted target value at decode time. Anything
    /// non-finite or non-positive is treated as "no target" so a
    /// corrupted snapshot can never resurface as an invalid timer
    /// duration; the same rule lives on `TargetShutterModel.setTarget`.
    private func sanitizedTargetShutterSeconds(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        return value
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
            customDisplayName: trimmedCustomName,
            targetShutterSeconds: snapshot.targetShutterSeconds
        )
    }
}
