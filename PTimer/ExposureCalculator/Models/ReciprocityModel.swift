import Foundation
import Observation

/// `ReciprocityModel` carries the *reciprocity policy* responsibility
/// extracted from the legacy `ExposureCalculatorViewModel` monolith as
/// the second step of B1 (`Docs/StructureImprovement/specs/B1-ViewModelDecomposition.md`).
///
/// PR2 of 6 — pure facade. The model owns the two collaborators that
/// previously lived directly on the ViewModel:
/// - `ReciprocityCalculationPolicyEvaluator` (policy evaluation entry)
/// - `FilmModeDetailsPresenter` (A8 details display-state transform)
///
/// Per spec §3.1 row "ReciprocityModel" the model carries **no stored
/// business state**: it exposes evaluation entry points only. Cached
/// binding state stays on the ViewModel for now and migrates with PR4
/// (`FilmSelectionModel`), which owns the active film identity that
/// feeds the binding.
@MainActor
@Observable
final class ReciprocityModel {
    private let evaluator: ReciprocityCalculationPolicyEvaluator
    private let detailsPresenter: FilmModeDetailsPresenter

    init(
        evaluator: ReciprocityCalculationPolicyEvaluator = ReciprocityCalculationPolicyEvaluator(),
        detailsPresenter: FilmModeDetailsPresenter = FilmModeDetailsPresenter()
    ) {
        self.evaluator = evaluator
        self.detailsPresenter = detailsPresenter
    }

    /// Pure transform: given a reciprocity profile and the metered
    /// exposure (calculator output that drives reciprocity), produce
    /// the reciprocity policy result.
    func evaluate(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> ReciprocityResult {
        evaluator.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    /// Pure transform: given the full presenter input bundle, produce
    /// the details display state. Returns nil when the presenter
    /// declines to surface any sections (matches the pre-decomposition
    /// behavior).
    func makeDetailsDisplayState(
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsDisplayState? {
        detailsPresenter.makeDetailsDisplayState(input: input)
    }

    /// Pure transform: produce the reciprocity-state badge/info display
    /// state for a given binding state.
    func reciprocityStateDisplayState(
        for bindingState: FilmModeReciprocityBindingState
    ) -> FilmModeReciprocityStateDisplayState {
        detailsPresenter.reciprocityStateDisplayState(for: bindingState)
    }
}
