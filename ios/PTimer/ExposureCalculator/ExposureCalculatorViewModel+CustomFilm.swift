import Foundation

/// Custom-film glue split from the main facade so the
/// view-model file does not grow past its size budget when this
/// feature lands. The facade still owns the stored `customFilmLibrary`
/// + `@Published var customFilms` (Swift requires stored properties
/// to live on the type's primary declaration); the editor entry
/// point, the section-header label, and the picker-row builder
/// live here.
extension ExposureCalculatorViewModel {

    /// Pseudo-manufacturer label for the "Custom films" section in
    /// the picker. Distinct from any real manufacturer string so
    /// `filmSelectorSections`'s contiguous-manufacturer grouping
    /// naturally collects all custom entries into one section header
    /// that the user reads as "CUSTOM FILMS". Exposed so tests can
    /// assert against the canonical label without re-deriving the
    /// string.
    static let customFilmsSectionManufacturerLabel = "Custom films"

    /// Sentinel entry id for the explicit "New custom film" row that
    /// sits near the top of the selector (under the "No film" row).
    /// Routing taps through this id keeps the editor entry point
    /// out of the selection identity space — selecting the row
    /// opens the editor instead of mutating the active film slot.
    static let createCustomFilmEntryID = "create-custom-film"

    /// Persists a freshly authored custom film through the library
    /// model. The editor view is the only caller; validation already
    /// ran inside `CustomFilmEditorFormState.validate()` so the
    /// `film` argument is guaranteed to be `kind == .custom` with a
    /// single `.userDefined`-authority profile.
    ///
    /// When the upsert matches the currently selected film by id
    /// (Edit-save of the active selection), the active selection is
    /// refreshed to the updated identity so live calculations and
    /// the Details sheet read the new formula immediately. The
    /// selection itself is preserved by id; no slot reset occurs.
    func addCustomFilm(_ film: FilmIdentity) {
        customFilmLibrary.add(film)
        if selectedPresetFilm?.id == film.id {
            // Edit-save of the currently selected custom film:
            // replace the in-memory identity so downstream readers
            // (Details graph, badge text, live calculations) see
            // the new formula parameters without forcing the
            // photographer to re-tap the row. Custom films never
            // carry a profile override, so re-selecting via the
            // existing public path is safe.
            selectPresetFilm(film)
        }
    }

    /// Removes a custom film from the library and the picker. If the
    /// currently-active film matches the deleted id, the active
    /// selection is cleared so the calculator falls back to a
    /// digital workflow rather than dangling on a film that no
    /// longer exists. Inactive camera-slot snapshots referencing the
    /// same id are scrubbed too, so paging to another slot does not
    /// resurface the deleted film. Already-started timers keep their
    /// value-captured identity snapshot — the running/completed dock
    /// continues to render the original film name, profile
    /// qualifier, and (when applicable) the custom-profile summary
    /// line.
    func deleteCustomFilm(id: String) {
        if selectedPresetFilm?.id == id {
            clearSelectedPresetFilm()
        }
        let touchedInactiveSlots = clearCustomFilmFromInactiveSlots(id: id)
        customFilmLibrary.remove(id: id)
        if !touchedInactiveSlots.isEmpty {
            // Force a session-snapshot rewrite so the inactive-slot
            // scrub is durable; without this the cleared references
            // would silently come back on relaunch from the
            // session store.
            persistInactiveSlotCleanup()
        }
    }

    /// Selector rows representing the user's custom films, sorted
    /// alphabetically inside the "Custom films" pseudo-manufacturer
    /// so multiple entries scan predictably. Inserted between the
    /// "No film" sentinel and the manufacturer-grouped presets in
    /// `filmSelectorEntries`.
    func customFilmSelectorEntries() -> [FilmSelectorEntry] {
        let sorted = customFilms.sorted { lhs, rhs in
            lhs.canonicalStockName.localizedCaseInsensitiveCompare(rhs.canonicalStockName) == .orderedAscending
        }
        return sorted.map { film in
            FilmSelectorEntry(
                id: film.id,
                primaryText: film.canonicalStockName,
                secondaryText: FilmSelectionModel.filmRowISOText(for: film),
                manufacturer: Self.customFilmsSectionManufacturerLabel,
                film: film,
                supportState: FilmSelectorSupportPresenter.makeSupportState(
                    for: film,
                    profileOverride: nil
                )
            )
        }
    }

    /// Explicit, discoverable "New custom film" row rendered near
    /// the top of the selector (just under the "No film" sentinel).
    /// Tapping the row dispatches to the editor through
    /// `FilmSelectorEntry.isCreateCustomFilmAction == true`; it is
    /// not a selectable film and is never marked selected.
    func createCustomFilmSelectorEntry() -> FilmSelectorEntry {
        FilmSelectorEntry(
            id: Self.createCustomFilmEntryID,
            primaryText: "New custom film",
            secondaryText: nil,
            manufacturer: nil,
            film: nil,
            supportState: .none,
            isCreateCustomFilmAction: true
        )
    }
}
