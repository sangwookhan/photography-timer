import Combine
import Foundation

/// `FilmSelectionModel` owns the film-selection slice. The model owns:
/// - the preset film catalog (`presetFilms: [FilmIdentity]`)
/// - the calculator-context persistence store
/// - the active film identity slice (`selectedPresetFilm` +
///   `selectedProfileOverride`) exposed through `activeContext`
/// - the film selection / clearing operations (`selectEntry`,
///   `selectPresetFilm`, `clearSelectedPresetFilm`)
/// - the calculator-context persistence side effects
///   (`restoreContext`, `persistContext`, `clearPersistedContext`)
///
/// `ActiveExposureCalculatorContext` carries only the film slice; the
/// base shutter and ND stop persisted alongside the selection are
/// owned by `CalculatorModel`. The model takes closures so it can
/// pull the current calc inputs at persistence time without holding
/// a direct reference to the calculator model. This preserves the
/// persistence schema (`selectedPresetFilmID + baseShutterSeconds +
/// ndStop` saved as one snapshot) is preserved byte-for-byte.
@MainActor
final class FilmSelectionModel: ObservableObject {
    let presetFilms: [FilmIdentity]

    @Published private(set) var activeContext = ActiveExposureCalculatorContext()

    private let contextPersistenceStore: ExposureCalculatorContextStoring
    private let currentBaseShutterSeconds: () -> Double
    private let currentNDStep: () -> NDStep
    private let currentScaleMode: () -> ExposureScaleMode
    /// Closure providing the active camera-slot id at persistence
    /// time. Returns `nil` when the consumer has no camera-slot
    /// concept (older test setups). Stored alongside the calc inputs
    /// so a relaunch grafts the persisted context back onto the
    /// correct slot rather than overwriting Camera 1's state.
    private let currentActiveCameraSlotID: () -> CameraSlotID?
    /// Closure that surfaces the photographer's custom
    /// film library at restore time. `restoreContext()` uses it to
    /// resolve a persisted film id against both the preset catalog
    /// and the user-authored library so a relaunch can restore a
    /// custom film selection — previously the lookup only consulted
    /// `presetFilms` and dropped custom selections silently.
    private let currentCustomFilms: () -> [FilmIdentity]

    /// Result of restoring the persisted context. Either we have a
    /// valid restored snapshot (potentially with a missing film id, in
    /// which case the selection is dropped to nil and the caller writes
    /// back a clean snapshot), or there is nothing to restore.
    struct RestoredContext {
        let selectedPresetFilm: FilmIdentity?
        let baseShutterSeconds: Double?
        let ndStep: NDStep?
        let scaleMode: ExposureScaleMode
        /// Camera slot the persisted context belonged to at save
        /// time, or `nil` for older snapshots that predate slot
        /// awareness. The caller restores the session model's active
        /// slot to this id before applying the calc inputs so the
        /// values land on the right page.
        let activeCameraSlotID: CameraSlotID?
        /// True when the persisted snapshot referenced a film id that
        /// is no longer in the catalog. The caller treats this the
        /// same as "no film selected" and clears the persisted
        /// snapshot.
        let hadInvalidFilmReference: Bool
    }

    init(
        presetFilms: [FilmIdentity],
        contextPersistenceStore: ExposureCalculatorContextStoring,
        currentBaseShutterSeconds: @escaping () -> Double,
        currentNDStep: @escaping () -> NDStep,
        currentScaleMode: @escaping () -> ExposureScaleMode = { .oneThirdStop },
        currentActiveCameraSlotID: @escaping () -> CameraSlotID? = { nil },
        currentCustomFilms: @escaping () -> [FilmIdentity] = { [] }
    ) {
        self.presetFilms = presetFilms
        self.contextPersistenceStore = contextPersistenceStore
        self.currentBaseShutterSeconds = currentBaseShutterSeconds
        self.currentNDStep = currentNDStep
        self.currentScaleMode = currentScaleMode
        self.currentActiveCameraSlotID = currentActiveCameraSlotID
        self.currentCustomFilms = currentCustomFilms
    }

    // MARK: - Read accessors

    var availablePresetFilms: [FilmIdentity] { presetFilms }

    var selectedPresetFilm: FilmIdentity? { activeContext.selectedPresetFilm }

    var selectedProfileOverride: ReciprocityProfile? { activeContext.selectedProfileOverride }

    // MARK: - Selection mutations

    /// Selects an entry from the film picker: assigns both the film and
    /// profile override, then persists the combined snapshot.
    func selectEntry(_ entry: FilmSelectorEntry) {
        activeContext.selectedPresetFilm = entry.film
        activeContext.selectedProfileOverride = entry.profileOverride
        persistContext()
    }

    /// Selects a preset film without overriding the profile choice.
    func selectPresetFilm(_ film: FilmIdentity) {
        activeContext.selectedPresetFilm = film
        activeContext.selectedProfileOverride = nil
        persistContext()
    }

    /// Clears the active film selection.
    func clearSelectedPresetFilm() {
        activeContext.selectedPresetFilm = nil
        activeContext.selectedProfileOverride = nil
        persistContext()
    }

    /// Drops the active selection without persisting. The caller (the
    /// ViewModel's `resetFilmModeWorkingContext`) follows up with a
    /// `clearPersistedContext()` call once it has also reset the calc
    /// inputs to defaults — preserving the "reset → clear snapshot"
    /// ordering.
    func dropActiveSelectionWithoutPersisting() {
        activeContext.selectedPresetFilm = nil
        activeContext.selectedProfileOverride = nil
    }

    /// Replaces the active film selection without persisting. Used by
    /// camera-slot switching where the caller updates the calc-input
    /// state and the film selection together and wants a single
    /// persistence write at the end of the transition rather than a
    /// per-mutation write.
    func replaceActiveSelection(
        film: FilmIdentity?,
        profileOverride: ReciprocityProfile?
    ) {
        activeContext.selectedPresetFilm = film
        activeContext.selectedProfileOverride = profileOverride
    }

    // MARK: - Persistence

    /// Loads the persisted snapshot and resolves the film reference
    /// against the current catalog. The caller is responsible for
    /// applying `baseShutterSeconds` / `ndStep` to its calculation
    /// inputs (those live on `CalculatorModel`).
    func restoreContext() -> RestoredContext? {
        guard let snapshot = contextPersistenceStore.loadSnapshot() else {
            return nil
        }

        let restoredSlotID: CameraSlotID? = snapshot.activeCameraSlotIDRaw
            .flatMap { CameraSlotID(rawValue: $0) }

        if let selectedPresetFilmID = snapshot.selectedPresetFilmID {
            let resolved = presetFilms.first(where: { $0.id == selectedPresetFilmID })
                ?? currentCustomFilms().first(where: { $0.id == selectedPresetFilmID })
            guard let restoredFilm = resolved else {
                activeContext.selectedPresetFilm = nil
                contextPersistenceStore.clearSnapshot()
                return RestoredContext(
                    selectedPresetFilm: nil,
                    baseShutterSeconds: nil,
                    ndStep: nil,
                    scaleMode: snapshot.restoredScaleMode,
                    activeCameraSlotID: restoredSlotID,
                    hadInvalidFilmReference: true
                )
            }

            activeContext.selectedPresetFilm = restoredFilm
        } else {
            activeContext.selectedPresetFilm = nil
        }

        return RestoredContext(
            selectedPresetFilm: activeContext.selectedPresetFilm,
            baseShutterSeconds: snapshot.baseShutterSeconds,
            ndStep: snapshot.restoredNDStep,
            scaleMode: snapshot.restoredScaleMode,
            activeCameraSlotID: restoredSlotID,
            hadInvalidFilmReference: false
        )
    }

    /// Writes the combined `(selectedPresetFilmID + baseShutterSeconds
    /// + ndStep)` snapshot to the persistence store, pulling the calc
    /// inputs from the closures supplied at init time. Whole-stop ND
    /// values populate `ndStop` for byte-for-byte backward compat with
    /// pre-fractional snapshots; fractional values populate
    /// `ndStopThirds` instead so a `1/3` or `2/3` step survives a
    /// relaunch without being silently rounded to an integer.
    func persistContext() {
        let ndStep = currentNDStep()
        let scaleMode = currentScaleMode()
        contextPersistenceStore.saveSnapshot(
            PersistentCalculatorContextSnapshot(
                selectedPresetFilmID: activeContext.selectedPresetFilm?.id,
                baseShutterSeconds: currentBaseShutterSeconds(),
                ndStop: ndStep.wholeStops,
                ndStopThirds: ndStep.isWholeStop ? nil : ndStep.thirdStopCount,
                // Persist `nil` for the shipping one-third-stop default so
                // a steady-state snapshot stays compact. Only the reserved
                // full-stop scale (kept for tests / the future Settings
                // preference) writes the field. Restore defaults missing
                // values back to `.oneThirdStop` per the spec.
                exposureScaleMode: scaleMode == .oneThirdStop ? nil : scaleMode.rawValue,
                // Persist `nil` for the default `camera1` slot so
                // single-slot users (and PTIMER-79/PTIMER-80 era
                // snapshots that never set a slot id) round-trip
                // byte-for-byte. Only Camera 2-4 snapshots carry the
                // new field.
                activeCameraSlotIDRaw: {
                    guard let slotID = currentActiveCameraSlotID(),
                          slotID != .camera1 else {
                        return nil
                    }
                    return slotID.rawValue
                }()
            )
        )
    }

    /// Clears the persisted snapshot. Used by the ViewModel's
    /// `resetFilmModeWorkingContext` path.
    func clearPersistedContext() {
        contextPersistenceStore.clearSnapshot()
    }

    // MARK: - Display helpers

    /// Short authority label for the main Film row subtitle.
    /// Returns nil for unknown sources so only official, unofficial,
    /// and user-defined films carry a visible qualifier.
    nonisolated static func filmRowAuthorityLabel(for profile: ReciprocityProfile?) -> String? {
        filmRowAuthorityLabel(forAuthority: profile?.source.authority)
    }

    /// Authority-only variant so other surfaces (the Details subtitle)
    /// can produce the exact same wording without round-tripping
    /// through a synthesized `ReciprocityProfile`. Pure value
    /// transform — declared `nonisolated` so the non-MainActor
    /// presenter can read it without crossing the actor boundary.
    /// Uses a distinct argument label (`forAuthority:`) so a
    /// `nil`-literal call site is not ambiguous with the profile
    /// overload above.
    nonisolated static func filmRowAuthorityLabel(forAuthority authority: ReciprocityAuthority?) -> String? {
        switch authority {
        case .official: return "Official guidance"
        case .unofficial: return "Unofficial practical"
        case .userDefined: return "Custom"
        case .unknown, nil: return nil
        }
    }

    /// ISO secondary text for a preset film identity. The launch
    /// catalog stores ISO box speed as a structured field on
    /// `FilmIdentity`, so this is a pure value transform — no
    /// inference, no regex over names. Used by the film selector
    /// entry subtitle.
    static func filmRowISOText(for film: FilmIdentity) -> String {
        "ISO \(film.iso)"
    }
}
