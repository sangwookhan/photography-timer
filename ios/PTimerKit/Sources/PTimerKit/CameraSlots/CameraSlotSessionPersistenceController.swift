// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Bridges the runtime managed camera list and its on-disk formats.
/// Owns the serialise/deserialise logic so the ViewModel stays a thin
/// facade and the camera-list persistence rules live in one testable
/// place.
///
/// Sources, in precedence order (CAMERA-PERSIST-006):
/// 1. A readable managed payload always wins; missing fields take their
///    documented defaults and the normalized list is persisted.
/// 2. Content that was read but cannot be decoded is replaced by one
///    atomic write of fresh camera state with new identities. No
///    absent-payload interval exists, so legacy data is never used.
/// 3. A storage read that supplies no content performs no delete or
///    write: the session stays read-only and initialization retries on
///    the next launch.
/// 4. With no managed payload, the legacy camera-slot session snapshot
///    (or, failing that, the legacy single-context snapshot, handled
///    by the ViewModel) migrates into the managed list. The legacy
///    stores are never modified or removed by migration, so a retry
///    after an interruption repeats the same idempotent migration.
public struct CameraSlotSessionPersistenceController {
    /// Holds the managed camera list and, read-only, the legacy
    /// camera-slot session snapshot that migrates into it.
    public let sessionStore: CameraSlotSessionPersistenceStoring
    public let presetFilms: [FilmIdentity]
    /// Closure that surfaces the photographer's custom
    /// film library at session restore time. `runtimeSnapshot(from:)`
    /// resolves persisted film ids against the preset catalog first
    /// (cheaper, immutable) and falls back to this closure so a
    /// custom film selected before relaunch is restored on the right
    /// camera. Default `{ [] }` preserves the legacy
    /// empty-list behavior for callers that pre-date custom films.
    public let currentCustomFilms: () -> [FilmIdentity]
    /// Live filter inventory at restore time (Filter Set contract).
    /// Persisted Filter Set / item references resolve against it; an
    /// unresolved reference is skipped safely rather than fabricated.
    public let currentFilterInventory: () -> FilterInventory

    /// The dedicated automatic-name sequence store (CAMERA-PERSIST-001).
    public let sequenceStore: CameraNameSequenceStoring

    /// Shared by copies of this struct.
    private let state = SessionState()

    public init(
        sessionStore: CameraSlotSessionPersistenceStoring,
        sequenceStore: CameraNameSequenceStoring = InMemoryCameraNameSequenceStore(),
        presetFilms: [FilmIdentity],
        currentCustomFilms: @escaping () -> [FilmIdentity] = { [] },
        currentFilterInventory: @escaping () -> FilterInventory = { .empty }
    ) {
        self.sessionStore = sessionStore
        self.sequenceStore = sequenceStore
        self.presetFilms = presetFilms
        self.currentCustomFilms = currentCustomFilms
        self.currentFilterInventory = currentFilterInventory
    }

    private final class SessionState {
        /// Fresh install, legacy migration, or corrupt-content
        /// replacement: the sequence is written (at least 5) before the
        /// first managed-list payload is committed.
        var needsSequenceInitialization = false
        /// Set when the storage read failed: nothing is written this
        /// session.
        var isReadOnly = false
    }

    /// Whether camera state may be written this session. `false` after
    /// a failed storage read (CAMERA-PERSIST-004).
    public var isWritable: Bool {
        !state.isReadOnly
    }

    /// The first automatic number after the four legacy cameras.
    public static let initialSequenceValue = 5

    /// Restored legacy session, ready to migrate. The active slot's
    /// snapshot is included in `snapshotsBySlotID`.
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

    /// Restored managed list. `snapshotsBySlotID` includes the active
    /// camera's snapshot.
    public struct RestoredManagedList {
        public let cameras: [CameraListEntry]
        public let activeSlotID: CameraSlotID?
        public let issuedIDs: Set<CameraSlotID>
        public let snapshotsBySlotID: [CameraSlotID: CameraSlotCalculatorSnapshot]
        public init(cameras: [CameraListEntry], activeSlotID: CameraSlotID?, issuedIDs: Set<CameraSlotID>, snapshotsBySlotID: [CameraSlotID: CameraSlotCalculatorSnapshot]) {
            self.cameras = cameras
            self.activeSlotID = activeSlotID
            self.issuedIDs = issuedIDs
            self.snapshotsBySlotID = snapshotsBySlotID
        }
    }

    public enum ManagedRestore {
        /// No managed payload: the caller may migrate legacy data.
        case absent
        case restored(RestoredManagedList)
        /// The storage read failed: no editable camera state exists
        /// this session and nothing is written.
        case readFailed
    }

    /// Loads the managed payload (CAMERA-PERSIST-001/004/006).
    public func loadManagedList() -> ManagedRestore {
        switch sessionStore.loadManagedList() {
        case .absent:
            // Fresh install or legacy migration: the sequence is
            // initialized before the first managed payload is written.
            state.needsSequenceInitialization = true
            return .absent
        case .readFailed:
            state.isReadOnly = true
            return .readFailed
        case .undecodable:
            // One atomic write replaces the unreadable content, so no
            // absent-payload interval lets stale legacy data migrate.
            state.needsSequenceInitialization = true
            let fresh = Self.replacementList()
            persist(fresh)
            return .restored(fresh)
        case let .loaded(snapshot):
            return .restored(normalizedList(from: snapshot))
        }
    }

    /// Four default cameras with newly generated identities, shown in
    /// order, the first active (CAMERA-PERSIST-004).
    private static func replacementList() -> RestoredManagedList {
        let ids = (0..<4).map { _ in CameraSlotID.generate() }
        return RestoredManagedList(
            cameras: ids.enumerated().map { index, id in
                CameraListEntry(id: id, name: CameraNaming.defaultName(number: index + 1))
            },
            activeSlotID: ids[0],
            issuedIDs: Set(ids),
            snapshotsBySlotID: Dictionary(uniqueKeysWithValues: ids.map { ($0, .initial) })
        )
    }

    /// Applies the per-record defaults and duplicate-identity handling,
    /// and persists the result when anything changed.
    private func normalizedList(from snapshot: PersistentManagedCameraListSnapshot) -> RestoredManagedList {
        var normalized = snapshot.isNormalized
        var cameras: [CameraListEntry] = []
        var snapshots: [CameraSlotID: CameraSlotCalculatorSnapshot] = [:]
        var usedIDs = Set<CameraSlotID>()
        for entry in snapshot.cameras {
            var id = CameraSlotID(rawValue: entry.idRaw)
            if id == nil || usedIDs.contains(id!) {
                // The first occurrence keeps an identity; later ones get
                // a new opaque identity.
                id = CameraSlotID.generate()
                normalized = true
            }
            guard let id else { continue }
            usedIDs.insert(id)
            let name = CameraNaming.trimmedName(entry.name) ?? {
                normalized = true
                return String(localized: "Camera")
            }()
            cameras.append(CameraListEntry(id: id, name: name, isDisplayed: entry.isDisplayed))
            snapshots[id] = entry.calculator.map(runtimeSnapshot(from:)) ?? .initial
        }
        let storedActive = snapshot.activeCameraIDRaw.flatMap { CameraSlotID(rawValue: $0) }
        let active: CameraSlotID?
        if let storedActive, cameras.contains(where: { $0.id == storedActive && $0.isDisplayed }) {
            active = storedActive
        } else {
            active = cameras.first(where: \.isDisplayed)?.id
        }
        if active?.rawValue != snapshot.activeCameraIDRaw {
            normalized = true
        }
        let restored = RestoredManagedList(
            cameras: cameras,
            activeSlotID: active,
            issuedIDs: Set(snapshot.issuedIDRaws.compactMap { CameraSlotID(rawValue: $0) }).union(usedIDs),
            snapshotsBySlotID: snapshots
        )
        if normalized {
            persist(restored)
        }
        return restored
    }

    private func persist(_ list: RestoredManagedList) {
        save(
            cameras: list.cameras,
            activeSlotID: list.activeSlotID,
            issuedIDs: list.issuedIDs,
            activeSlotSnapshot: nil,
            inactiveSnapshots: list.snapshotsBySlotID
        )
    }

    /// Loads the legacy camera-slot session snapshot, or `nil` when
    /// none exists. Migration source only; never written again.
    public func loadSession() -> RestoredSession? {
        guard let session = sessionStore.loadSnapshot() else {
            return nil
        }
        return restoredSession(from: session)
    }

    /// CAMERA-PERSIST-002/003: the four legacy cameras migrate in their
    /// existing order with their identities, names, and calculator
    /// state, all shown in the pager. An unnamed slot freezes its
    /// resolved `Camera N` string.
    public func migratedList(from session: RestoredSession) -> RestoredManagedList {
        let cameras = CameraSlotID.legacyOrdered.enumerated().map { index, id in
            CameraListEntry(
                id: id,
                name: session.customDisplayNames[id] ?? CameraNaming.defaultName(number: index + 1)
            )
        }
        return RestoredManagedList(
            cameras: cameras,
            activeSlotID: CameraSlotID.legacyOrdered.contains(session.activeSlotID)
                ? session.activeSlotID : .camera1,
            issuedIDs: Set(CameraSlotID.legacyOrdered),
            snapshotsBySlotID: session.snapshotsBySlotID
        )
    }

    /// Reserves the next automatic number durably before the camera is
    /// committed (CAMERA-003, PERSIST-CAMERA-SEQUENCE-002). A missing
    /// or unreadable sequence uses the normal allocation at 5
    /// (CAMERA-PERSIST-007), so a display number may repeat after that
    /// fallback while camera identities never do. A failed or
    /// interrupted creation may leave a gap. Returns `nil` when the
    /// session is read-only or the reservation could not be written.
    public func reserveNextCameraNumber() -> Int? {
        guard isWritable else { return nil }
        let number = Self.usableSequenceValue(sequenceStore.load()) ?? Self.initialSequenceValue
        guard sequenceStore.save(nextNumber: number + 1) else {
            return nil
        }
        return number
    }

    /// A stored next number the allocator can issue: at least 5 and
    /// small enough to advance. Anything else (below the first automatic
    /// number, or one that would overflow when advanced) cannot be a value
    /// this app stored, and is treated like a missing one.
    private static func usableSequenceValue(_ result: CameraNameSequenceLoadResult) -> Int? {
        guard case let .value(stored) = result,
              stored >= initialSequenceValue,
              stored < Int.max else {
            return nil
        }
        return stored
    }

    /// Writes the initial sequence value before the first managed payload
    /// (fresh install, legacy migration, corrupt-content replacement).
    /// Advance-only: a readable value of at least 5 is never lowered or
    /// replaced. Returns whether the managed payload may now be written.
    private func ensureSequenceInitialized() -> Bool {
        guard state.needsSequenceInitialization else { return true }
        if case let .value(stored) = sequenceStore.load(), stored >= Self.initialSequenceValue {
            state.needsSequenceInitialization = false
            return true
        }
        guard sequenceStore.save(nextNumber: Self.initialSequenceValue) else { return false }
        state.needsSequenceInitialization = false
        return true
    }

    /// Persists the whole managed list in one write, so list entries,
    /// order, pager inclusion, active camera, and calculator states
    /// land together (CAMERA-PERSIST-005). Skipped for the whole
    /// session after a failed storage read.
    public func save(
        cameras: [CameraListEntry],
        activeSlotID: CameraSlotID?,
        issuedIDs: Set<CameraSlotID>,
        activeSlotSnapshot: CameraSlotCalculatorSnapshot?,
        inactiveSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot]
    ) {
        guard isWritable else { return }
        // Sequence before payload (CAMERA-PERSIST-001/002): without it the
        // managed list is not committed, so a retry stays consistent.
        guard ensureSequenceInitialized() else { return }
        var allSnapshots = inactiveSnapshots
        if let activeSlotID, let activeSlotSnapshot {
            allSnapshots[activeSlotID] = activeSlotSnapshot
        }
        let persistentCameras = cameras.map { camera in
            PersistentManagedCamera(
                idRaw: camera.id.rawValue,
                name: camera.name,
                isDisplayed: camera.isDisplayed,
                calculator: persistentSnapshot(
                    for: camera.id,
                    snapshot: allSnapshots[camera.id] ?? .initial,
                    customDisplayName: nil
                )
            )
        }
        sessionStore.saveManagedList(
            PersistentManagedCameraListSnapshot(
                issuedIDRaws: issuedIDs.map(\.rawValue).sorted(),
                activeCameraIDRaw: activeSlotID?.rawValue,
                cameras: persistentCameras
            )
        )
    }

    // MARK: - Restore helpers

    private func restoredSession(
        from session: PersistentCameraSlotSessionSnapshot
    ) -> RestoredSession {
        let activeSlotID = CameraSlotID(rawValue: session.activeSlotIDRaw) ?? .camera1
        var resolved: [CameraSlotID: CameraSlotCalculatorSnapshot] = [:]
        var customNames: [CameraSlotID: String] = [:]
        for entry in session.slots {
            guard let slotID = CameraSlotID(rawValue: entry.slotIDRaw),
                  CameraSlotID.legacyOrdered.contains(slotID) else {
                continue
            }
            resolved[slotID] = runtimeSnapshot(from: entry)
            if let trimmed = CameraNaming.trimmedName(entry.customDisplayName) {
                customNames[slotID] = trimmed
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

        let inventory = currentFilterInventory()
        // A slot stored before it had any selection starts with a fresh
        // camera's (FILTER-CAMERA-001); an emptied selection is stored as
        // an empty list.
        let storedCandidates = entry.candidateFilterSetIDs.map { $0.map(FilterSetID.init(rawValue:)) }
            ?? CalculatorDefaults.candidateFilterSetIDs
        let stack = restoredFilterStack(from: entry, selectedFilterSetIDs: storedCandidates, inventory: inventory)
        return CameraSlotCalculatorSnapshot(
            baseShutterSeconds: entry.baseShutterSeconds ?? CalculatorDefaults.baseShutterSeconds,
            filterStack: stack,
            candidateFilterSetIDs: inventory.normalizedCandidateFilterSetIDs(
                storedCandidates,
                referencedBy: stack.wheels,
                auxiliaryFilters: stack.auxiliaryFilters
            ),
            lastFilterSource: restoredLastFilterSource(from: entry, inventory: inventory),
            scaleMode: entry.restoredScaleMode,
            selectedPresetFilm: film,
            selectedProfileOverride: profile,
            targetShutterSeconds: sanitizedTargetShutterSeconds(entry.targetShutterSeconds)
        )
    }

    /// Restores the Filter Stack (Filter Set contract): the ND wheels
    /// plus the mounted auxiliary filters. A present `filterStack` that
    /// validates wins; otherwise the Standard-only `ndStack` / legacy
    /// scalar path applies unchanged.
    private func restoredFilterStack(
        from entry: PersistentCameraSlotCalculatorSnapshot,
        selectedFilterSetIDs: [FilterSetID],
        inventory: FilterInventory
    ) -> FilterStack {
        if let persisted = entry.filterStack,
           let stack = Self.validatedFilterStack(
               persisted,
               auxiliaryFilters: entry.auxiliaryFilters ?? [],
               selectedFilterSetIDs: selectedFilterSetIDs,
               inventory: inventory
           ) {
            return stack
        }
        return FilterStack(standardSteps: restoredNDFilterSteps(from: entry))
    }

    /// Validates persisted wheels and auxiliary filters BEFORE any
    /// `FilterStack` construction. Whole-stack rejection (`nil`) for
    /// structural corruption: wheel count outside 1–4, a Standard
    /// wheel that does not resolve to a ladder value, a corrupted
    /// auxiliary entry, more wheels than the limit that applies with
    /// auxiliary filters, or a resolved total over the 30-stop cap.
    /// Filter Set references are normalized individually instead — an
    /// unknown set drops its wheel, an unknown item becomes Empty, an
    /// unresolvable auxiliary filter is unmounted — so the stack still
    /// ends in a valid state. A legacy wheel that mounted a CPL or GND
    /// row migrates into an auxiliary filter with the same item,
    /// choice, and mode (FILTER-PERSIST-002); a stack that held only
    /// such rows receives one Standard 0 wheel.
    static func validatedFilterStack(
        _ wheels: [PersistentFilterWheelSnapshot],
        auxiliaryFilters: [PersistentAuxiliaryFilterSnapshot] = [],
        selectedFilterSetIDs: [FilterSetID],
        inventory: FilterInventory
    ) -> FilterStack? {
        guard (1...FilterStack.maximumWheelCount).contains(wheels.count) else {
            return nil
        }
        var restored: [FilterWheel] = []
        for wheel in wheels {
            guard let restoredWheel = wheel.restoredWheel else {
                return nil
            }
            if let step = restoredWheel.standardStep {
                guard step.stops >= 0,
                      step.stops <= Double(ExposureScale.maximumWholeNDStops)
                          + ExposureCalculator.stabilityEpsilon else {
                    return nil
                }
            }
            restored.append(restoredWheel)
        }
        var mounts: [MountedAuxiliaryFilter] = []
        for entry in auxiliaryFilters {
            guard let mount = entry.restoredMount else {
                return nil
            }
            mounts.append(mount)
        }
        let migrated = FilterStack.migratingLegacyWheels(restored)
        // The inventory and this snapshot are saved separately, so the
        // inventory may hold an edit the snapshot has not seen: an item
        // moved to another Set or a kind corrected. It is applied the way
        // the live reconciliation applies it (FILTER-ITEM-005/009) before
        // the references are normalized; if that no longer fits the
        // limits, the references normalize as they are.
        let reassigned = FilterStack.reassigningRoles(
            wheels: migrated.wheels,
            auxiliaryFilters: mounts + migrated.auxiliaryFilters,
            selectedFilterSetIDs: selectedFilterSetIDs,
            inventory: inventory
        )
        if let stack = normalizedStack(wheels: reassigned.wheels, auxiliaryFilters: reassigned.auxiliaryFilters, inventory: inventory) {
            return stack
        }
        return normalizedStack(wheels: migrated.wheels, auxiliaryFilters: mounts + migrated.auxiliaryFilters, inventory: inventory)
    }

    private static func normalizedStack(
        wheels: [FilterWheel],
        auxiliaryFilters: [MountedAuxiliaryFilter],
        inventory: FilterInventory
    ) -> FilterStack? {
        guard let normalized = FilterStack.normalizedWheels(wheels, inventory: inventory) else {
            return nil
        }
        let auxiliary = FilterStack.normalizedAuxiliaryFilters(auxiliaryFilters, inventory: inventory)
        return FilterStack.validated(wheels: normalized, auxiliaryFilters: auxiliary, inventory: inventory)
    }

    /// Restores the slot's last Filter Source; a missing kind, an
    /// unknown kind, or a Filter Set that no longer exists falls back
    /// to Standard.
    private func restoredLastFilterSource(
        from entry: PersistentCameraSlotCalculatorSnapshot,
        inventory: FilterInventory
    ) -> FilterSource {
        guard entry.lastFilterSourceKind == PersistentFilterWheelSnapshot.filterSetSourceKind,
              let rawID = entry.lastFilterSetID,
              inventory.filterSet(withID: FilterSetID(rawValue: rawID)) != nil else {
            return .standard
        }
        return .filterSet(FilterSetID(rawValue: rawID))
    }

    /// Restores the ND wheel stack (PTIMER-199 §7). A present, VALID
    /// `ndStack` wins; any violation — wheel count outside 1–4, a
    /// wheel that does not resolve to a ladder value, or a sum over
    /// the 30-stop cap — drops the WHOLE stack (no partial recovery,
    /// which would silently change the saved combination's sum) and
    /// falls back to the legacy scalar, then to the default. An
    /// absent or malformed-at-decode stack takes the same fallback.
    private func restoredNDFilterSteps(
        from entry: PersistentCameraSlotCalculatorSnapshot
    ) -> [NDStep] {
        if let stack = entry.ndStack,
           let validated = Self.validatedStackSteps(stack) {
            return validated
        }
        return [entry.restoredNDStep ?? CalculatorDefaults.ndStep]
    }

    /// Validates raw persisted wheels BEFORE any `NDFilterStack`
    /// construction, per the domain type's contract (its initializer
    /// treats violations as programmer errors; persisted data must
    /// be screened here, rejected rather than clamped).
    static func validatedStackSteps(
        _ wheels: [PersistentNDFilterWheelSnapshot]
    ) -> [NDStep]? {
        guard (1...NDFilterStack.maximumWheelCount).contains(wheels.count) else {
            return nil
        }
        var steps: [NDStep] = []
        for wheel in wheels {
            guard let step = wheel.restoredNDStep,
                  step.stops >= 0,
                  step.stops <= Double(ExposureScale.maximumWholeNDStops)
                      + ExposureCalculator.stabilityEpsilon else {
                return nil
            }
            steps.append(step)
        }
        guard NDFilterStack.isWithinTotalLimit(steps) else {
            return nil
        }
        return steps
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

        // Legacy scalar fields carry the EXPLICITLY SELECTED MAXIMUM
        // wheel (max over entries, never positional stack[0]) so an
        // older app build restoring this snapshot degrades to a valid
        // single filter: the effective sum could be off-ladder (e.g.
        // 13.2) and legacy validation would reject it to defaults.
        // Only STANDARD wheels can be represented in the pre-Filter-Set
        // fields: the scalar carries the maximum Standard wheel and
        // `ndStack` the Standard wheels (one 0-stop wheel when the
        // stack holds none), so an older build degrades to a valid
        // Standard stack. The mixed stack itself goes to `filterStack`.
        let standardSteps = snapshot.filterWheels.compactMap(\.standardStep)
        let downgradeSteps = standardSteps.isEmpty ? [CalculatorDefaults.ndStep] : standardSteps
        let legacyScalarStep = downgradeSteps
            .max(by: { $0.stops < $1.stops }) ?? CalculatorDefaults.ndStep

        return PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: slotID.rawValue,
            selectedPresetFilmID: snapshot.selectedPresetFilm?.id,
            selectedProfileID: snapshot.selectedProfileOverride?.id,
            baseShutterSeconds: snapshot.baseShutterSeconds,
            ndStop: legacyScalarStep.wholeStops,
            // Whole → `ndStop`; third-stop fractional → `ndStopThirds`;
            // a supported commercial preset (PTIMER-209) → its canonical
            // `ndStopsExact`. Exactly one is populated, so pre-PTIMER-209
            // whole/third-stop snapshots stay identical, and an
            // unsupported off-grid value persists none of the three and
            // restores to the default rather than as a drifting value.
            ndStopThirds: legacyScalarStep.isWholeStop || !legacyScalarStep.isThirdStop
                ? nil : legacyScalarStep.thirdStopCount,
            ndStopsExact: ExposureScale.commercialNDPresetStop(matching: legacyScalarStep.stops),
            // Persist `nil` for the shipping `.oneThirdStop` so a
            // steady-state snapshot stays compact, mirroring the
            // legacy convention.
            exposureScaleMode: snapshot.scaleMode == .oneThirdStop ? nil : snapshot.scaleMode.rawValue,
            customDisplayName: trimmedCustomName,
            targetShutterSeconds: snapshot.targetShutterSeconds,
            // The stack itself is ALWAYS written, single wheel
            // included, so the array is the forward-facing source of
            // truth from the first save (PTIMER-199 §7).
            ndStack: downgradeSteps.map(PersistentNDFilterWheelSnapshot.init(step:)),
            filterStack: snapshot.filterWheels.map(PersistentFilterWheelSnapshot.init(wheel:)),
            lastFilterSourceKind: snapshot.lastFilterSource == .standard
                ? PersistentFilterWheelSnapshot.standardSourceKind
                : PersistentFilterWheelSnapshot.filterSetSourceKind,
            lastFilterSetID: snapshot.lastFilterSource.filterSetID?.rawValue,
            // Auxiliary filters are additive: written whenever present,
            // omitted otherwise so a slot that never used them keeps the
            // pre-auxiliary shape. Candidates are always written, an
            // empty list included, so an explicit empty selection is
            // kept as it is.
            auxiliaryFilters: snapshot.auxiliaryFilters.isEmpty ? nil : persistentAuxiliaryFilters(snapshot.auxiliaryFilters),
            candidateFilterSetIDs: snapshot.candidateFilterSetIDs.map(\.rawValue)
        )
    }

    /// The mounted auxiliary filters with each item's kind read from
    /// the live inventory; a mount whose item vanished between the
    /// snapshot and the save is dropped (restore would unmount it
    /// anyway).
    private func persistentAuxiliaryFilters(_ mounts: [MountedAuxiliaryFilter]) -> [PersistentAuxiliaryFilterSnapshot] {
        let inventory = currentFilterInventory()
        return mounts.compactMap { mount in
            guard let kind = inventory.item(withID: mount.itemID)?.item.behavior.kind else {
                return nil
            }
            return PersistentAuxiliaryFilterSnapshot(mount: mount, kind: kind)
        }
    }
}
