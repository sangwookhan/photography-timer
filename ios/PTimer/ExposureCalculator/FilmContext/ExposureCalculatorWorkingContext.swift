import Foundation
import PTimerKit

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
