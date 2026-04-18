import Foundation

enum ExposureCalculatorMode: Int, CaseIterable, Equatable, Hashable {
    case digital
    case film
}

struct ActiveExposureCalculatorContext: Equatable {
    var mode: ExposureCalculatorMode
    var selectedPresetFilm: FilmIdentity?

    init(
        mode: ExposureCalculatorMode = .digital,
        selectedPresetFilm: FilmIdentity? = nil
    ) {
        self.mode = mode
        self.selectedPresetFilm = selectedPresetFilm
    }
}

enum FilmModeSelectionState: Equatable {
    case hidden
    case noFilmSelected
    case selectedPreset(FilmIdentity)
}

struct FilmModeReciprocityBindingState: Equatable {
    let film: FilmIdentity
    let profile: ReciprocityProfile
    let policyResult: ReciprocityCalculationPolicyResult
    let presentation: ReciprocityConfidencePresentation
}
