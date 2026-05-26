import Foundation

struct FilmSelectorEntry: Equatable, Identifiable {
    let id: String
    let primaryText: String
    let secondaryText: String?
    let manufacturer: String?
    let film: FilmIdentity?
    let profileOverride: ReciprocityProfile?
    /// Selector-facing support state. Drives the row's compact
    /// indicator (icon or "Unofficial" badge) and the accessibility
    /// label fragment.
    let supportState: FilmSelectorSupportDisplayState
    /// When this row is a Quick Access alias
    /// of a canonical row (the row also appears in a manufacturer
    /// or Custom Films section), this carries the original entry's
    /// id. The selector view uses it to mark alias rows as selected
    /// when the canonical row is selected, so the photographer
    /// sees a consistent highlight without alias rows fighting
    /// each other for the active marker.
    let aliasOfOriginalID: String?

    /// Canonical `FilmIdentity.id` for
    /// the custom film backing this row, or `nil` when the row is
    /// not a custom film. Quick Access alias rows store
    /// `"quick:<originalID>"` in `id`, so edit / delete actions
    /// must read this helper to address the custom library
    /// correctly — passing `id` directly would route through the
    /// alias prefix and miss the actual film.
    var canonicalCustomFilmID: String? {
        guard let film, film.kind == .custom else { return nil }
        return film.id
    }

    init(
        id: String,
        primaryText: String,
        secondaryText: String? = nil,
        manufacturer: String? = nil,
        film: FilmIdentity? = nil,
        profileOverride: ReciprocityProfile? = nil,
        supportState: FilmSelectorSupportDisplayState = .none,
        aliasOfOriginalID: String? = nil
    ) {
        self.id = id
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.manufacturer = manufacturer
        self.film = film
        self.profileOverride = profileOverride
        self.supportState = supportState
        self.aliasOfOriginalID = aliasOfOriginalID
    }
}

struct FilmSelectionDisplayState: Equatable {
    let primaryText: String
    let secondaryText: String?
}

/// One manufacturer-grouped section of the film selector overlay.
///
/// The view renders each section as a grouped card so the user can scan
/// by manufacturer. The leading "No film" sentinel becomes its own
/// section with `manufacturer == nil` and is rendered as a plain headerless
/// row outside of any card. Future fold/unfold UX can be added without
/// changing the section data shape — the model already partitions
/// entries the way a grouped list expects them.
struct FilmSelectorSection: Equatable, Identifiable {
    /// Stable identity used by SwiftUI's `ForEach`. `"no-film"` for the
    /// sentinel section, otherwise the manufacturer label.
    let id: String
    /// `nil` for the "No film" sentinel section; otherwise the
    /// manufacturer label rendered as the group card header.
    let manufacturer: String?
    let entries: [FilmSelectorEntry]
}

struct FilmModeReciprocityBindingState: Equatable {
    let film: FilmIdentity
    let profile: ReciprocityProfile
    let policyResult: ReciprocityResult
    let presentation: ReciprocityConfidencePresentation
}
