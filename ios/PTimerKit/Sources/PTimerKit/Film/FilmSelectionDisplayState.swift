// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public struct FilmSelectorEntry: Equatable, Identifiable {
    public let id: String
    public let primaryText: String
    public let secondaryText: String?
    public let manufacturer: String?
    public let film: FilmIdentity?
    public let profileOverride: ReciprocityProfile?
    /// Selector-facing support state. Drives the row's compact
    /// indicator (icon or "Unofficial" badge) and the accessibility
    /// label fragment.
    public let supportState: FilmSelectorSupportDisplayState
    /// `true` when the row is the explicit "New custom film" action
    /// rendered near the top of the selector. The view routes a tap
    /// on this row to the editor instead of through
    /// `selectEntry(_:)`; it is never marked selected.
    public let isCreateCustomFilmAction: Bool

    /// Canonical `FilmIdentity.id` for the custom film backing
    /// this row, or `nil` when the row is not a custom film.
    /// Edit/delete actions read this helper to address the custom
    /// library when the row id differs from the film id.
    public var canonicalCustomFilmID: String? {
        guard let film, film.kind == .custom else { return nil }
        return film.id
    }

    public init(
        id: String,
        primaryText: String,
        secondaryText: String? = nil,
        manufacturer: String? = nil,
        film: FilmIdentity? = nil,
        profileOverride: ReciprocityProfile? = nil,
        supportState: FilmSelectorSupportDisplayState = .none,
        isCreateCustomFilmAction: Bool = false
    ) {
        self.id = id
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.manufacturer = manufacturer
        self.film = film
        self.profileOverride = profileOverride
        self.supportState = supportState
        self.isCreateCustomFilmAction = isCreateCustomFilmAction
    }
}

public struct FilmSelectionDisplayState: Equatable {
    public let primaryText: String
    public let secondaryText: String?
    public init(primaryText: String, secondaryText: String?) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }
}

/// One manufacturer-grouped section of the film selector overlay.
///
/// The view renders each section as a grouped card so the user can scan
/// by manufacturer. The leading "No film" sentinel becomes its own
/// section with `manufacturer == nil` and is rendered as a plain headerless
/// row outside of any card. Future fold/unfold UX can be added without
/// changing the section data shape — the model already partitions
/// entries the way a grouped list expects them.
public struct FilmSelectorSection: Equatable, Identifiable {
    /// Stable identity used by SwiftUI's `ForEach`. `"no-film"` for the
    /// sentinel section, otherwise the manufacturer label.
    public let id: String
    /// `nil` for the "No film" sentinel section; otherwise the
    /// manufacturer label rendered as the group card header.
    public let manufacturer: String?
    public let entries: [FilmSelectorEntry]
    public init(id: String, manufacturer: String?, entries: [FilmSelectorEntry]) {
        self.id = id
        self.manufacturer = manufacturer
        self.entries = entries
    }
}

public struct FilmModeReciprocityBindingState: Equatable {
    public let film: FilmIdentity
    public let profile: ReciprocityProfile
    public let policyResult: ReciprocityResult
    public let presentation: ReciprocityConfidencePresentation
    public init(film: FilmIdentity, profile: ReciprocityProfile, policyResult: ReciprocityResult, presentation: ReciprocityConfidencePresentation) {
        self.film = film
        self.profile = profile
        self.policyResult = policyResult
        self.presentation = presentation
    }
}
