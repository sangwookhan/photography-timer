import Foundation
import PTimerCore

public struct ActiveExposureCalculatorContext: Equatable {
    public var selectedPresetFilm: FilmIdentity?
    public var selectedProfileOverride: ReciprocityProfile?

    public init(
        selectedPresetFilm: FilmIdentity? = nil,
        selectedProfileOverride: ReciprocityProfile? = nil
    ) {
        self.selectedPresetFilm = selectedPresetFilm
        self.selectedProfileOverride = selectedProfileOverride
    }
}
