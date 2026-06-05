import Foundation
import PTimerKit

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
    /// catalog-less profile sources whose authority is `.unknown`.
    case none

    /// Official profile that publishes a quantified reciprocity
    /// prediction (formula rule). The selector row shows a compact
    /// graph-style icon.
    case officialQuantifiedPrediction

    /// Official profile whose long-exposure section is qualitative
    /// only — published guidance exists but is not quantified. The
    /// selector row shows an info-style icon distinct from the
    /// quantified-prediction one.
    case officialLimitedGuidance

    /// Official profile that publishes neither a quantified
    /// prediction nor limited guidance for long exposures. The row
    /// shows a disabled / prohibited-style icon so the user can spot
    /// the lack of support before selecting.
    case noQuantifiedPrediction

    /// Unofficial practical approximation. The selector row carries
    /// a visible "Unofficial" text badge — the unofficial state must
    /// never collapse into an icon or color alone.
    case unofficialPractical

    /// Photographer-authored custom profile. Renders a
    /// visible "Custom" text badge so a user-defined entry can never
    /// be mistaken for an official manufacturer row at a glance —
    /// shape, not color, carries the meaning, matching the
    /// `.unofficialPractical` treatment.
    case userDefinedFormulaPrediction

    /// SF Symbol rendered alongside official-profile rows. `nil`
    /// for the unofficial / custom badge cases (rendered as text)
    /// and for `.none`.
    var iconSystemName: String? {
        switch self {
        case .officialQuantifiedPrediction:
            return "chart.line.uptrend.xyaxis"
        case .officialLimitedGuidance:
            return "info.circle"
        case .noQuantifiedPrediction:
            return "nosign"
        case .unofficialPractical, .userDefinedFormulaPrediction, .none:
            return nil
        }
    }

    /// Visible text badge rendered inside the row for the
    /// unofficial and custom cases. `nil` for every other state.
    /// Both badges are textual so a row cannot be misread as
    /// official from icon shape or color alone.
    var unofficialBadgeText: String? {
        switch self {
        case .unofficialPractical:
            return "Unofficial"
        case .userDefinedFormulaPrediction:
            return "Custom"
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
        case .userDefinedFormulaPrediction:
            return "Custom user-defined profile"
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
/// authority always produces `.unofficialPractical`; a `.userDefined`
/// authority with a formula rule produces
/// `.userDefinedFormulaPrediction`. For
/// `.official` authorities, the rule set decides between quantified
/// prediction, limited guidance, and no quantified prediction.
/// `.unknown` collapses to `.none`.
enum FilmSelectorSupportPresenter {
    /// Classifies a film / profile-override pair for the selector
    /// row. When a `profileOverride` is supplied (the unofficial
    /// practical row variant), the override's authority drives the
    /// classification — the film's official primary profile does
    /// not leak through. When no override is supplied, the film's
    /// first profile (the launch catalog's official primary, or the
    /// single user-defined profile on a custom film) is inspected.
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
            if hasFormulaRule(profile) || hasTableInterpolationRule(profile) {
                return .officialQuantifiedPrediction
            }
            if hasLimitedGuidanceRule(profile) {
                return .officialLimitedGuidance
            }
            return .noQuantifiedPrediction
        case .userDefined:
            return .userDefinedFormulaPrediction
        case .unknown:
            return .none
        }
    }

    private static func hasFormulaRule(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains { rule in
            if case .formula = rule { return true }
            return false
        }
    }

    private static func hasLimitedGuidanceRule(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains { rule in
            if case .limitedGuidance = rule { return true }
            return false
        }
    }

    private static func hasTableInterpolationRule(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains { rule in
            if case .tableInterpolation = rule { return true }
            return false
        }
    }
}
