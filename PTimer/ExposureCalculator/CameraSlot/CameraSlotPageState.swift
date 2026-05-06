import Foundation

/// Per-slot view-facing snapshot the workspace TabView consumes for
/// a single page. This first iteration carries only the slot
/// identity and active flag — every page renders the same live
/// calculator state, so the page does not need slot-specific input
/// values yet. Per-slot calc state lands in a follow-up commit and
/// extends this struct with the input fields each page binds to.
struct CameraSlotPageState {
    let slotID: CameraSlotID
    let cameraDisplayName: String
    let isActive: Bool
}
