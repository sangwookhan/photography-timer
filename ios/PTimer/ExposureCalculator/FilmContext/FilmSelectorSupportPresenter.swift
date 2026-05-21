import Foundation

/// Selector-facing reciprocity prediction support state for one film
/// selector row. Pure value transform produced by
/// `FilmSelectorSupportPresenter` — view models compute it once and
/// the row view renders the icon / badge plus an accessibility label
/// without re-classifying the underlying reciprocity rules.
///
/// The four meaningful cases differ both by shape (icon vs. text
/// badge) and by accessibility wording so a row's support state is
/// readable independent of color.
enum FilmSelectorSupportDisplayState: Equatable {
    /// No indicator. Used by the "No film" sentinel row and by
    /// catalog-less profile sources (`.userDefined` / `.unknown`).
    case none

    /// Official profile that publishes a quantified reciprocity
    /// prediction (formula or table rule). The selector row shows a
    /// compact graph-style icon.
    case officialQuantifiedPrediction

    /// Official profile whose long-exposure section is advisory-only
    /// — published guidance exists but is not quantified. The
    /// selector row shows an info-style icon distinct from the
    /// quantified-prediction one.
    case officialLimitedGuidance

    /// Official profile that publishes neither a quantified
    /// prediction nor advisory guidance for long exposures. The row
    /// shows a disabled / prohibited-style icon so the user can spot
    /// the lack of support before selecting.
    case noQuantifiedPrediction

    /// Unofficial practical approximation. The selector row carries
    /// a visible "Unofficial" text badge — the unofficial state must
    /// never collapse into an icon or color alone.
    case unofficialPractical

    /// SF Symbol rendered alongside official-profile rows. `nil`
    /// for the unofficial badge case (rendered as text) and for
    /// `.none`.
    var iconSystemName: String? {
        switch self {
        case .officialQuantifiedPrediction:
            return "chart.line.uptrend.xyaxis"
        case .officialLimitedGuidance:
            return "info.circle"
        case .noQuantifiedPrediction:
            return "nosign"
        case .unofficialPractical, .none:
            return nil
        }
    }

    /// Visible text shown inside the row for the unofficial badge.
    /// `nil` for every other state. Only the unofficial case carries
    /// a textual badge so a row cannot be misread as official from
    /// icon shape alone.
    var unofficialBadgeText: String? {
        switch self {
        case .unofficialPractical:
            return "Unofficial"
        case .none,
             .officialQuantifiedPrediction,
             .officialLimitedGuidance,
             .noQuantifiedPrediction:
            return nil
        }
    }

    /// Accessibility label fragment appended to the selector row's
    /// composed VoiceOver label so users hear the full meaning of
    /// the indicator instead of a generic icon description. `nil`
    /// for `.none` (no indicator → nothing to announce).
    var accessibilityLabel: String? {
        switch self {
        case .none:
            return nil
        case .officialQuantifiedPrediction:
            return "Official quantified prediction available"
        case .officialLimitedGuidance:
            return "Official limited guidance only"
        case .noQuantifiedPrediction:
            return "No quantified prediction available"
        case .unofficialPractical:
            return "Unofficial practical estimate"
        }
    }
}

/// Pure value transform from a film + optional profile-override pair
/// into a selector-facing support display state. Reused by the
/// calculator view model when building `FilmSelectorEntry` instances
/// so the SwiftUI row can render the indicator without inspecting
/// reciprocity rules at view time.
///
/// Authority maps drive the top-level branch: an `.unofficial`
/// authority on the active profile always produces
/// `.unofficialPractical`, regardless of the film's other profiles.
/// For `.official` authorities, the rule set decides between
/// quantified prediction, limited guidance, and no quantified
/// prediction. `.userDefined` and `.unknown` collapse to `.none`
/// because the launch preset catalog never produces them and a
/// future custom-profile UI will introduce its own indicator
/// vocabulary.
enum FilmSelectorSupportPresenter {
    /// Classifies a film / profile-override pair for the selector
    /// row. When a `profileOverride` is supplied (the unofficial
    /// practical row variant), the override's authority drives the
    /// classification — the film's official primary profile does
    /// not leak through. When no override is supplied, the film's
    /// first profile (the launch catalog's official primary) is
    /// inspected.
    static func makeSupportState(
        for film: FilmIdentity?,
        profileOverride: ReciprocityProfile? = nil
    ) -> FilmSelectorSupportDisplayState {
        guard let film else { return .none }
        guard let profile = profileOverride ?? film.profiles.first else {
            return .noQuantifiedPrediction
        }

        switch profile.source.authority {
        case .unofficial:
            return .unofficialPractical
        case .official:
            if hasFormulaOrTableRule(profile) {
                return .officialQuantifiedPrediction
            }
            if hasAdvisoryRule(profile) {
                return .officialLimitedGuidance
            }
            return .noQuantifiedPrediction
        case .userDefined, .unknown:
            return .none
        }
    }

    private static func hasFormulaOrTableRule(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains { rule in
            switch rule {
            case .formula, .table:
                return true
            case .threshold, .advisory:
                return false
            }
        }
    }

    private static func hasAdvisoryRule(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains { rule in
            if case .advisory = rule {
                return true
            }
            return false
        }
    }
}
