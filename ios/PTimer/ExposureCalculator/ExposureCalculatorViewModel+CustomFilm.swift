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

    /// Pseudo-manufacturer label for the Quick Access section. Sits
    /// between "No film" and the manufacturer-grouped presets so the
    /// photographer's selected film plus their custom-authored films
    /// are reachable without scrolling past the alphabetised preset
    /// catalog.
    static let quickAccessSectionManufacturerLabel = "Quick access"

    /// Persists a freshly authored custom film through the library
    /// model. The editor view is the only caller; validation already
    /// ran inside `CustomFilmEditorFormState.validate()` so the
    /// `film` argument is guaranteed to be `kind == .custom` with a
    /// single `.userDefined`-authority profile.
    func addCustomFilm(_ film: FilmIdentity) {
        customFilmLibrary.add(film)
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

    /// Quick Access alias rows. Contains the currently selected
    /// film (preset or custom) plus every custom-authored film,
    /// sorted alphabetically. Each alias references the canonical
    /// entry id through `aliasOfOriginalID` so the selector view
    /// marks both the alias and the canonical row as selected for
    /// the same film. Returns `[]` when there is nothing to
    /// alias — the section is then omitted entirely.
    func quickAccessSelectorEntries(originals: [FilmSelectorEntry]) -> [FilmSelectorEntry] {
        var aliasFilmIDs: Set<String> = []
        var aliases: [FilmSelectorEntry] = []

        // Selected canonical row first, if any.
        if let selectedSelectorEntryID,
           let original = originals.first(where: { $0.id == selectedSelectorEntryID }) {
            aliases.append(quickAccessAlias(of: original))
            if let filmID = original.film?.id {
                aliasFilmIDs.insert(filmID)
            }
        }

        // Then every custom film, sorted alphabetically.
        let sortedCustomFilms = customFilms.sorted { lhs, rhs in
            lhs.canonicalStockName.localizedCaseInsensitiveCompare(rhs.canonicalStockName) == .orderedAscending
        }
        for film in sortedCustomFilms where !aliasFilmIDs.contains(film.id) {
            guard let original = originals.first(where: { $0.id == film.id }) else {
                continue
            }
            aliases.append(quickAccessAlias(of: original))
            aliasFilmIDs.insert(film.id)
        }
        return aliases
    }

    private func quickAccessAlias(of original: FilmSelectorEntry) -> FilmSelectorEntry {
        FilmSelectorEntry(
            id: "quick:\(original.id)",
            primaryText: original.primaryText,
            secondaryText: original.secondaryText,
            manufacturer: Self.quickAccessSectionManufacturerLabel,
            film: original.film,
            profileOverride: original.profileOverride,
            supportState: original.supportState,
            aliasOfOriginalID: original.id
        )
    }
}
