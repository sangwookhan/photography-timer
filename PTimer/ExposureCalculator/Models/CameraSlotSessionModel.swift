import Combine
import Foundation

/// `CameraSlotSessionModel` owns the camera-slot session state: which
/// slot is currently active, plus invariants on the available slot
/// set. This first iteration tracks the active slot id only — per-slot
/// calculator-state preservation lands as a follow-up commit and adds
/// an inactive-snapshots map to this model.
///
/// The model holds session state only. Slot navigation goes through
/// `setActiveSlot(_:)`; the view-model facade wires the slot picker
/// UI through that path so the active-slot transition is single-
/// rooted.
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
    /// access to per-slot snapshot state.
    let identityProvider: (CameraSlotID) -> CameraSlotIdentity

    @Published private(set) var activeSlotID: CameraSlotID

    init(
        availableSlots: [CameraSlotID] = CameraSlotID.allOrdered,
        initialActiveSlotID: CameraSlotID = .camera1,
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
    }

    /// Identity for the currently active slot.
    var activeSlot: CameraSlotIdentity {
        identityProvider(activeSlotID)
    }

    /// Identity for an arbitrary slot id.
    func identity(for slotID: CameraSlotID) -> CameraSlotIdentity {
        identityProvider(slotID)
    }

    /// Sets the active slot id without preserving any prior slot's
    /// state. This first iteration treats slot navigation as a pure
    /// id flip — per-slot calc state preservation lands in the next
    /// commit and replaces this method with a capture/load pair.
    func setActiveSlot(_ slotID: CameraSlotID) {
        guard availableSlots.contains(slotID),
              slotID != activeSlotID else {
            return
        }
        activeSlotID = slotID
    }
}
