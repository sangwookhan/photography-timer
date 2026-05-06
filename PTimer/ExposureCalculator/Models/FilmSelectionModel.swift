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

    private let contextPersistenceStore: ExposureCalculatorContextPersistenceStoring
    private let currentBaseShutterSeconds: () -> Double
    private let currentNDStep: () -> NDStep
    private let currentScaleMode: () -> ExposureScaleMode

    /// Result of restoring the persisted context. Either we have a
    /// valid restored snapshot (potentially with a missing film id, in
    /// which case the selection is dropped to nil and the caller writes
    /// back a clean snapshot), or there is nothing to restore.
    struct RestoredContext {
        let selectedPresetFilm: FilmIdentity?
        let baseShutterSeconds: Double?
        let ndStep: NDStep?
        let scaleMode: ExposureScaleMode
        /// True when the persisted snapshot referenced a film id that
        /// is no longer in the catalog. The caller treats this the
        /// same as "no film selected" and clears the persisted
        /// snapshot.
        let hadInvalidFilmReference: Bool
    }

    init(
        presetFilms: [FilmIdentity],
        contextPersistenceStore: ExposureCalculatorContextPersistenceStoring,
        currentBaseShutterSeconds: @escaping () -> Double,
        currentNDStep: @escaping () -> NDStep,
        currentScaleMode: @escaping () -> ExposureScaleMode = { .oneThirdStop }
    ) {
        self.presetFilms = presetFilms
        self.contextPersistenceStore = contextPersistenceStore
        self.currentBaseShutterSeconds = currentBaseShutterSeconds
        self.currentNDStep = currentNDStep
        self.currentScaleMode = currentScaleMode
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

        if let selectedPresetFilmID = snapshot.selectedPresetFilmID {
            guard let restoredFilm = presetFilms.first(where: { $0.id == selectedPresetFilmID }) else {
                activeContext.selectedPresetFilm = nil
                contextPersistenceStore.clearSnapshot()
                return RestoredContext(
                    selectedPresetFilm: nil,
                    baseShutterSeconds: nil,
                    ndStep: nil,
                    scaleMode: snapshot.restoredScaleMode,
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
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: activeContext.selectedPresetFilm?.id,
                baseShutterSeconds: currentBaseShutterSeconds(),
                ndStop: ndStep.wholeStops,
                ndStopThirds: ndStep.isWholeStop ? nil : ndStep.thirdStopCount,
                // Persist `nil` for the shipping one-third-stop default so
                // a steady-state snapshot stays compact. Only the reserved
                // full-stop scale (kept for tests / the future Settings
                // preference) writes the field. Restore defaults missing
                // values back to `.oneThirdStop` per the spec.
                exposureScaleMode: scaleMode == .oneThirdStop ? nil : scaleMode.rawValue
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
    /// Returns nil for userDefined/unknown so only official/unofficial
    /// films carry a visible qualifier.
    static func filmRowAuthorityLabel(for profile: ReciprocityProfile?) -> String? {
        switch profile?.source.authority {
        case .official: return "Official guidance"
        case .unofficial: return "Unofficial practical"
        case .userDefined, .unknown, nil: return nil
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
