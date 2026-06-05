import Foundation

/// Short authority label for the Film row / Details subtitle.
///
/// Pure value transform extracted from `FilmSelectionModel` (PTIMER-174)
/// so the presentation layer can read it without depending on the
/// app-side `@MainActor` model. Returns nil for unknown sources so only
/// official, unofficial, and user-defined films carry a visible
/// qualifier.
public enum FilmRowAuthorityLabel {

    public static func label(for profile: ReciprocityProfile?) -> String? {
        // App-derived alternate models (e.g. the Fomapan 100 app
        // formula) are fitted by the app from official source data, so
        // they must not read as official manufacturer guidance on the
        // film-row / camera-slot subtitle. They name themselves
        // ("App-derived formula") instead. Only the official table
        // model keeps the "Official guidance" label.
        if let profile, AlternateReciprocityModels.isAppDerivedModel(id: profile.id) {
            return profile.name
        }
        return label(forAuthority: profile?.source.authority)
    }

    public static func label(forAuthority authority: ReciprocityAuthority?) -> String? {
        switch authority {
        case .official: return "Official guidance"
        case .unofficial: return "Unofficial practical"
        case .userDefined: return "Custom"
        case .unknown, nil: return nil
        }
    }
}
