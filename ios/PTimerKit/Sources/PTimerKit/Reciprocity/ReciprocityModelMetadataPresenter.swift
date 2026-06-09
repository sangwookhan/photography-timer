import Foundation
import PTimerCore

/// Pure presenter for the "Reciprocity model" metadata section in
/// Reciprocity Details (PTIMER-159).
///
/// Surfaces the active profile's identity and basis — Film,
/// Profile / Model, Authority, Source basis, Calculation method —
/// derived from the profile's provenance (`source`) and its
/// `effectiveModelBasis`. Presentation-only: it reads catalog
/// vocabulary and never the calculation path, so it cannot change a
/// corrected exposure. Rendered for every film so the absence of a
/// quantified prediction reads as "nothing special here" rather than
/// missing information.
public struct ReciprocityModelMetadataPresenter {
    public init() {}

    public static let sectionTitle = "Reciprocity model"

    /// Compact 2-row summary (PTIMER-159): Source + Calculation. The
    /// film name is the sheet header and the authority is the subtitle,
    /// so they are not repeated here — this keeps Details readable
    /// rather than a large per-film metadata table.
    public func metadataSection(
        film: FilmIdentity,
        profile: ReciprocityProfile
    ) -> FilmModeDetailsSectionState {
        let basis = profile.effectiveModelBasis
        return FilmModeDetailsSectionState(
            title: Self.sectionTitle,
            rows: [
                row("Source", sourceBasisLabel(for: basis.sourceModel)),
                row("Calculation", calculationMethodLabel(for: basis)),
            ]
        )
    }

    private func row(_ title: String, _ value: String) -> FilmModeDetailsRowState {
        FilmModeDetailsRowState(title: title, value: value)
    }

    private func sourceBasisLabel(for sourceModel: ReciprocitySourceModel) -> String {
        switch sourceModel {
        case .manufacturerFormula: return "Manufacturer formula"
        case .manufacturerTable: return "Manufacturer table"
        case .manufacturerRangeGuidance: return "Manufacturer range guidance"
        case .manufacturerLimitedGuidance: return "Manufacturer limited guidance"
        case .practicalCommunityGuidance: return "Practical / community guidance"
        case .userDefined: return "Custom (user-defined)"
        case .unknown: return "Not specified"
        }
    }

    /// A table-origin source converted to a fitted formula is
    /// app-derived; a guarded manufacturer *formula* is a faithful
    /// guard of published math. The distinction lets Fomapan 100
    /// ("App-derived guarded formula") read differently from HP5 Plus
    /// ("Guarded formula") without per-film hardcoding.
    private func calculationMethodLabel(for basis: ReciprocityProfileModelBasis) -> String {
        switch basis.calculationModel {
        case .guardedFormula:
            return basis.sourceModel == .manufacturerTable
                ? "App-derived guarded formula"
                : "Guarded formula"
        case .tableLogLogInterpolation:
            return "Log-log table interpolation"
        case .limitedGuidance:
            return "Limited guidance — no quantified prediction"
        case .unsupported:
            return "Unsupported above no-correction threshold"
        case .tableLookup:
            // Rejected at catalog load (PTIMER-163); kept for an
            // exhaustive switch so a future lookup strategy surfaces here.
            return "Table lookup"
        }
    }
}
