import Foundation
import PTimerCore

struct ActiveExposureCalculatorContext: Equatable {
    var selectedPresetFilm: FilmIdentity?
    var selectedProfileOverride: ReciprocityProfile?

    init(
        selectedPresetFilm: FilmIdentity? = nil,
        selectedProfileOverride: ReciprocityProfile? = nil
    ) {
        self.selectedPresetFilm = selectedPresetFilm
        self.selectedProfileOverride = selectedProfileOverride
    }
}
