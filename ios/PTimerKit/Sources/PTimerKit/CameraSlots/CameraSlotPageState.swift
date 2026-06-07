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
public struct CameraSlotPageState {
    public let slotID: CameraSlotID
    public let cameraDisplayName: String
    public let baseShutter: Double
    public let ndStep: NDStep
    public let scaleMode: ExposureScaleMode
    public let selectedFilm: FilmIdentity?
    public let selectedProfileOverride: ReciprocityProfile?
    public let filmSelectionDisplayState: FilmSelectionDisplayState
    public let isFilmWorkflowActive: Bool
    public let isActive: Bool
    /// Per-slot Target Shutter duration in seconds. `nil` when the
    /// photographer has not set a target for this slot. The active
    /// slot reads this through the live `TargetShutterModel`; inactive
    /// slots read the value stored on their snapshot. Surfacing it on
    /// the page state lets each TabView page render the correct
    /// per-slot target while the photographer is paging through
    /// without having to fan out per-slot facade lookups in views.
    public let targetShutterSeconds: TimeInterval?

    /// Selector-row id used to drive the film picker's `selected`
    /// highlight. Mirrors `ExposureCalculatorViewModel
    /// .selectedSelectorEntryID` but resolved per slot so an
    /// inactive page lights up its slot's chosen film row, not the
    /// active slot's.
    public var selectedSelectorEntryID: String? {
        guard let selectedFilm else { return nil }
        return selectedProfileOverride?.id ?? selectedFilm.id
    }
    public init(slotID: CameraSlotID, cameraDisplayName: String, baseShutter: Double, ndStep: NDStep, scaleMode: ExposureScaleMode, selectedFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, filmSelectionDisplayState: FilmSelectionDisplayState, isFilmWorkflowActive: Bool, isActive: Bool, targetShutterSeconds: TimeInterval?) {
        self.slotID = slotID
        self.cameraDisplayName = cameraDisplayName
        self.baseShutter = baseShutter
        self.ndStep = ndStep
        self.scaleMode = scaleMode
        self.selectedFilm = selectedFilm
        self.selectedProfileOverride = selectedProfileOverride
        self.filmSelectionDisplayState = filmSelectionDisplayState
        self.isFilmWorkflowActive = isFilmWorkflowActive
        self.isActive = isActive
        self.targetShutterSeconds = targetShutterSeconds
    }
}
