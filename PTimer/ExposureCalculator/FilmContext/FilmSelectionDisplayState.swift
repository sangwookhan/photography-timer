import Foundation

struct FilmSelectorEntry: Equatable, Identifiable {
    let id: String
    let primaryText: String
    let secondaryText: String?
    let film: FilmIdentity?
    let profileOverride: ReciprocityProfile?

    init(
        id: String,
        primaryText: String,
        secondaryText: String? = nil,
        film: FilmIdentity? = nil,
        profileOverride: ReciprocityProfile? = nil
    ) {
        self.id = id
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.film = film
        self.profileOverride = profileOverride
    }
}

struct FilmSelectionDisplayState: Equatable {
    let primaryText: String
    let secondaryText: String?
}

struct FilmModeReciprocityBindingState: Equatable {
    let film: FilmIdentity
    let profile: ReciprocityProfile
    let policyResult: ReciprocityResult
    let presentation: ReciprocityConfidencePresentation
}
