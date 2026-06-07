import Foundation
import PTimerCore

/// Per-slot snapshot the workspace TabView consumes for a single
/// page. Combines the slot identity, the calculator inputs (live for
/// the active slot, stored snapshot for inactive slots), and the
/// derived display state the page needs to render its calculator
/// surface without reaching back into the ViewModel for slot-specific
/// branching.
///
/// The active page reads its bindings live (so the user's wheel
/// drags propagate immediately into `CalculatorModel`); inactive
/// pages render the same layout but bind to constants drawn from
/// this state, and `.allowsHitTesting(false)` keeps the photographer
/// from accidentally driving an inactive slot's pickers while
/// swiping past it.
struct CameraSlotPageState {
    let slotID: CameraSlotID
    let cameraDisplayName: String
    let baseShutter: Double
    let ndStep: NDStep
    let scaleMode: ExposureScaleMode
    let selectedFilm: FilmIdentity?
    let selectedProfileOverride: ReciprocityProfile?
    let filmSelectionDisplayState: FilmSelectionDisplayState
    let isFilmWorkflowActive: Bool
    let isActive: Bool
    /// Per-slot Target Shutter duration in seconds. `nil` when the
    /// photographer has not set a target for this slot. The active
    /// slot reads this through the live `TargetShutterModel`; inactive
    /// slots read the value stored on their snapshot. Surfacing it on
    /// the page state lets each TabView page render the correct
    /// per-slot target while the photographer is paging through
    /// without having to fan out per-slot facade lookups in views.
    let targetShutterSeconds: TimeInterval?

    /// Selector-row id used to drive the film picker's `selected`
    /// highlight. Mirrors `ExposureCalculatorViewModel
    /// .selectedSelectorEntryID` but resolved per slot so an
    /// inactive page lights up its slot's chosen film row, not the
    /// active slot's.
    var selectedSelectorEntryID: String? {
        guard let selectedFilm else { return nil }
        return selectedProfileOverride?.id ?? selectedFilm.id
    }
}
