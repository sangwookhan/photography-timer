import Combine
import Foundation

/// `CameraSlotSessionModel` owns the camera-slot session state: which
/// slot is currently active, plus the calculator snapshot for every
/// slot the photographer is not currently active on. Inactive slot
/// snapshots stay here untouched so a slot switch can restore the
/// slot's exposure inputs and film selection without invoking any
/// reset behavior on the active calculator/film models.
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

    /// Identity for each slot, resolved by `CameraSlotID` so the
    /// switcher UI can render a stable display label without needing
    /// access to the snapshot dictionary.
    let identityProvider: (CameraSlotID) -> CameraSlotIdentity

    @Published private(set) var activeSlotID: CameraSlotID

    /// Snapshots for slots that are not currently active. The active
    /// slot's snapshot is intentionally absent — the live state on
    /// `CalculatorModel` + `FilmSelectionModel` is the source of
    /// truth for the active slot. Switching reads/writes this map.
    private var inactiveSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot]

    init(
        availableSlots: [CameraSlotID] = CameraSlotID.allOrdered,
        initialActiveSlotID: CameraSlotID = .camera1,
        initialSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot] = [:],
        identityProvider: @escaping (CameraSlotID) -> CameraSlotIdentity = { CameraSlotIdentity(id: $0) }
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
        self.identityProvider = identityProvider
        self.activeSlotID = initialActiveSlotID
        self.inactiveSnapshots = initialSnapshots.filter { $0.key != initialActiveSlotID }
    }

    /// Identity for the currently active slot.
    var activeSlot: CameraSlotIdentity {
        identityProvider(activeSlotID)
    }

    /// Identity for an arbitrary slot id.
    func identity(for slotID: CameraSlotID) -> CameraSlotIdentity {
        identityProvider(slotID)
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
    /// slot, and returns the snapshot the caller should load into
    /// the calculator/film models for the incoming slot.
    ///
    /// A no-op switch (target is already active, or target is not in
    /// `availableSlots`) returns nil so the caller can avoid
    /// redundant model writes.
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
}
