import Foundation

struct ActiveExposureCalculatorContext: Equatable {
    var selectedPresetFilm: FilmIdentity?

    init(
        selectedPresetFilm: FilmIdentity? = nil
    ) {
        self.selectedPresetFilm = selectedPresetFilm
    }
}

struct FilmSelectorEntry: Equatable, Identifiable {
    let id: String
    let title: String
    let film: FilmIdentity?
}

struct FilmModeReciprocityBindingState: Equatable {
    let film: FilmIdentity
    let profile: ReciprocityProfile
    let policyResult: ReciprocityCalculationPolicyResult
    let presentation: ReciprocityConfidencePresentation
}

enum FilmModeCorrectedExposureDisplayKind: Equatable {
    case quantified
    case advisory
    case unsupported
    case noFilmSelected
}

struct FilmModeCorrectedExposureDisplayState: Equatable {
    let kind: FilmModeCorrectedExposureDisplayKind
    let correctedExposureSeconds: TimeInterval?
    let primaryText: String
    let secondaryText: String
    let usesNumericExposure: Bool
}

struct FilmModeExposureResultState: Equatable {
    let adjustedShutterSeconds: TimeInterval
    let correctedExposure: FilmModeCorrectedExposureDisplayState

    var hasQuantifiedCorrectedExposure: Bool {
        correctedExposure.usesNumericExposure
    }
}
