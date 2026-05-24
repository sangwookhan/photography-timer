import Combine
import Foundation

/// `CameraSlotSessionModel` owns the camera-slot session state: which
/// slot is currently active, and the calculator snapshot for every
/// slot the user has not currently active. Inactive slot snapshots
/// stay here untouched so a slot switch can restore the slot's
/// exposure inputs and film selection without invoking any reset
/// behavior on the active calculator/film models.
///
/// The model holds session state only. Snapshot capture / load is
/// orchestrated by the `ExposureCalculatorViewModel` facade so the
/// other feature models (`CalculatorModel`, `FilmSelectionModel`,
/// `ReciprocityModel`, `TimerWorkspaceModel`) keep owning their
/// respective state types and the cross-model import rule stays
/// intact.
@MainActor
final class CameraSlotSessionModel: ObservableObject {
    /// Order of slots exposed to the UI. The shipping configuration
    /// shows all four; the underlying domain enforces a minimum of
    /// two via precondition. Kept as a stored array (rather than
    /// `CameraSlotID.allOrdered` directly) so a future configuration
    /// step can shorten it without reshaping the model.
    let availableSlots: [CameraSlotID]

    @Published private(set) var activeSlotID: CameraSlotID

    /// Photographer-supplied display names keyed by slot id. Absent
    /// keys mean "use the canonical `Camera N` default"; entries are
    /// stored already-trimmed so the round-trip from `displayName`
    /// rendering matches the editing surface byte-for-byte.
    /// `@Published` so a rename or reset propagates through to the
    /// ViewModel facade and any view bound to the session model.
    @Published private(set) var customDisplayNames: [CameraSlotID: String]

    /// Snapshots for slots that are not currently active. The active
    /// slot's snapshot is intentionally absent — the live state on
    /// `CalculatorModel` + `FilmSelectionModel` is the source of
    /// truth for the active slot. Switching reads/writes this map.
    private var inactiveSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot]

    init(
        availableSlots: [CameraSlotID] = CameraSlotID.allOrdered,
        initialActiveSlotID: CameraSlotID = .camera1,
        initialSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot] = [:],
        initialCustomDisplayNames: [CameraSlotID: String] = [:]
    ) {
        // Camera-slot session shape invariants. The shipping
        // experience exposes Camera 1-4; the underlying domain caps
        // the count at 4 to avoid surfacing a slot that no
        // `CameraSlotID` case represents, and demands at least 2
        // because a single-slot session is the legacy single-camera
        // calculator (which does not need this model).
        precondition(
            availableSlots.count >= 2,
            "Camera slot session must expose at least two slots."
        )
        precondition(
            availableSlots.count <= CameraSlotID.allCases.count,
            "Camera slot session must expose at most \(CameraSlotID.allCases.count) slots."
        )
        precondition(
            Set(availableSlots).count == availableSlots.count,
            "Camera slot session must expose unique slot ids."
        )
        precondition(
            availableSlots.contains(initialActiveSlotID),
            "Initial active slot must be one of the available slots."
        )
        self.availableSlots = availableSlots
        self.activeSlotID = initialActiveSlotID
        self.inactiveSnapshots = initialSnapshots.filter { $0.key != initialActiveSlotID }
        self.customDisplayNames = Self.sanitizeCustomNames(
            initialCustomDisplayNames,
            availableSlots: availableSlots
        )
    }

    /// Identity for the currently active slot.
    var activeSlot: CameraSlotIdentity {
        identity(for: activeSlotID)
    }

    /// Identity for an arbitrary slot id. The session model is the
    /// single owner of `customDisplayName`; the returned identity
    /// merges the canonical default with any photographer-supplied
    /// custom name held in `customDisplayNames`.
    func identity(for slotID: CameraSlotID) -> CameraSlotIdentity {
        CameraSlotIdentity(
            id: slotID,
            customDisplayName: customDisplayNames[slotID]
        )
    }

    /// Sets the slot's photographer-supplied display name. Whitespace
    /// is trimmed; an empty / whitespace-only / nil value clears the
    /// custom entry (equivalent to `resetCustomDisplayName(for:)`).
    /// Mirrors the trimming rule on
    /// `CameraSlotIdentity.displayName` so the editing path round-
    /// trips with the rendering path.
    func setCustomDisplayName(_ name: String?, for slotID: CameraSlotID) {
        guard availableSlots.contains(slotID) else { return }
        let trimmed = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            customDisplayNames[slotID] = trimmed
        } else {
            customDisplayNames.removeValue(forKey: slotID)
        }
    }

    /// Clears the slot's custom display name so `identity(for:)`
    /// falls back to the canonical `Camera N` label.
    func resetCustomDisplayName(for slotID: CameraSlotID) {
        guard availableSlots.contains(slotID) else { return }
        customDisplayNames.removeValue(forKey: slotID)
    }

    /// Bulk-loads photographer-supplied display names at app-start
    /// restore time. Keys outside `availableSlots` are filtered, and
    /// each value is trimmed; an empty trimmed value drops the entry.
    /// Replaces any current map so a relaunch never carries forward a
    /// stale runtime entry that the persisted snapshot does not
    /// re-assert.
    func restoreCustomDisplayNames(_ names: [CameraSlotID: String]) {
        customDisplayNames = Self.sanitizeCustomNames(
            names,
            availableSlots: availableSlots
        )
    }

    private static func sanitizeCustomNames(
        _ names: [CameraSlotID: String],
        availableSlots: [CameraSlotID]
    ) -> [CameraSlotID: String] {
        let allowed = Set(availableSlots)
        var sanitized: [CameraSlotID: String] = [:]
        for (slotID, value) in names where allowed.contains(slotID) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sanitized[slotID] = trimmed
        }
        return sanitized
    }

    /// Returns the snapshot stored for an inactive slot. Returns nil
    /// for the currently active slot (the active state lives on the
    /// calculator/film models, not here) and for any slot id that is
    /// not in `availableSlots`.
    func snapshot(forInactiveSlot slotID: CameraSlotID) -> CameraSlotCalculatorSnapshot? {
        guard slotID != activeSlotID,
              availableSlots.contains(slotID) else {
            return nil
        }
        return inactiveSnapshots[slotID] ?? .initial
    }

    /// Atomic slot switch: stores `outgoingSnapshot` for the
    /// currently active slot, sets `targetSlotID` as the new active
    /// slot, and returns the snapshot the caller should load into the
    /// calculator/film models for the incoming slot.
    ///
    /// A no-op switch (target is already active) returns nil so the
    /// caller can avoid redundant model writes.
    @discardableResult
    func switchActiveSlot(
        to targetSlotID: CameraSlotID,
        capturing outgoingSnapshot: CameraSlotCalculatorSnapshot
    ) -> CameraSlotCalculatorSnapshot? {
        guard availableSlots.contains(targetSlotID) else {
            return nil
        }
        // Same-slot switch is a no-op: the caller's outgoing snapshot
        // is dropped because the slot's state already lives on the
        // active calc/film models. `selectCameraSlot` early-returns
        // before reaching here, so this path is reached only when a
        // caller deliberately invokes `switchActiveSlot` against the
        // currently active slot — defensive only.
        guard targetSlotID != activeSlotID else {
            return nil
        }

        // Store outgoing slot's snapshot before flipping `activeSlotID`
        // so a subscriber observing `$activeSlotID` reads a coherent
        // map: the previously-active slot now has a stored snapshot,
        // and the incoming slot's snapshot is removed (the calc/film
        // models become the live state for the incoming slot).
        inactiveSnapshots[activeSlotID] = outgoingSnapshot
        let incomingSnapshot = inactiveSnapshots.removeValue(forKey: targetSlotID) ?? .initial
        activeSlotID = targetSlotID
        return incomingSnapshot
    }

    /// Sets the active slot id at app-start restore time. Used when
    /// persistence captured the last active slot and the calculator
    /// context has been (or is about to be) loaded into the live
    /// calc/film models for that slot. Removes any stale snapshot for
    /// `slotID` because the live models are now the source of truth
    /// for it.
    ///
    /// No outgoing-snapshot capture happens here: the prior active
    /// slot at this point is the default placeholder (`camera1`) and
    /// no real state was set against it. Callers should invoke this
    /// before mutating the live calc/film models with the persisted
    /// context.
    func restoreActiveSlot(to slotID: CameraSlotID) {
        guard availableSlots.contains(slotID) else { return }
        inactiveSnapshots.removeValue(forKey: slotID)
        activeSlotID = slotID
    }

    /// Bulk-loads inactive-slot snapshots at app-start restore time.
    /// Callers (the ViewModel during persistence restore) build the
    /// dictionary from a `PersistentCameraSlotSessionSnapshot`, drop
    /// the entry for the active slot (its state lives on the live
    /// calc/film models), and pass the rest here.
    ///
    /// Slots not in `availableSlots` are silently filtered — keeps
    /// the model robust against a future schema mismatch where a
    /// persisted snapshot references a slot the runtime no longer
    /// exposes.
    func restoreInactiveSnapshots(_ snapshots: [CameraSlotID: CameraSlotCalculatorSnapshot]) {
        let filtered = snapshots
            .filter { availableSlots.contains($0.key) && $0.key != activeSlotID }
        inactiveSnapshots = filtered
    }

    /// Read access to the full inactive-snapshot dictionary. Used by
    /// the persistence layer to serialise the session shape; not by
    /// regular slot navigation paths (those go through
    /// `snapshot(forInactiveSlot:)` and `switchActiveSlot(...)`).
    func currentInactiveSnapshots() -> [CameraSlotID: CameraSlotCalculatorSnapshot] {
        inactiveSnapshots
    }

    /// Scrubs `filmID` from every inactive slot snapshot
    /// so a custom-film deletion does not leave the other slots
    /// dangling on a no-longer-existing reference. The active slot
    /// is not touched here — the ViewModel facade clears the active
    /// selection through `FilmSelectionModel` separately. Returns
    /// the set of slots whose snapshot was mutated so the caller
    /// can trigger persistence + UI republish only when something
    /// actually changed.
    @discardableResult
    func clearFilmReference(filmID: String) -> Set<CameraSlotID> {
        var touched: Set<CameraSlotID> = []
        for (slotID, snapshot) in inactiveSnapshots {
            guard snapshot.selectedPresetFilm?.id == filmID else {
                continue
            }
            var updated = snapshot
            updated.selectedPresetFilm = nil
            updated.selectedProfileOverride = nil
            inactiveSnapshots[slotID] = updated
            touched.insert(slotID)
        }
        // `inactiveSnapshots` is not `@Published` (page state reads
        // are pull-driven via `snapshot(forInactiveSlot:)`), so a
        // mutation in here would otherwise not trip the model's
        // objectWillChange. Send manually only when something
        // changed so non-deletion writes stay quiet.
        if !touched.isEmpty {
            objectWillChange.send()
        }
        return touched
    }
}
