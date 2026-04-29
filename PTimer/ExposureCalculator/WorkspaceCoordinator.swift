import Foundation

/// Owns the lifetime of the `@Observable` models that, together, will
/// replace the `ExposureCalculatorViewModel` monolith. Constructed once
/// at app entry from a `ViewModelDependencies` bundle (A4 DI factory).
///
/// PR1 skeleton (`Docs/StructureImprovement/specs/B1-ViewModelDecomposition.md`):
/// holds `CalculatorModel` and the legacy `ExposureCalculatorViewModel`,
/// which still serves as the public observable surface for views until
/// PR5 migrates bindings. PR2–PR4 expand to `ReciprocityModel`,
/// `TimerWorkspaceModel`, `FilmSelectionModel`. PR6 removes the
/// legacy ViewModel and adds fitness lint rules F5/F8.
///
/// Spec §11 risk mitigation: coordinator stays under 100 lines and
/// holds **no business state** — wiring only.
@MainActor
final class WorkspaceCoordinator {
    let calculatorModel: CalculatorModel
    let viewModel: ExposureCalculatorViewModel

    init(dependencies: ViewModelDependencies) {
        let calculatorModel = CalculatorModel(calculator: dependencies.calculator)
        self.calculatorModel = calculatorModel
        self.viewModel = ExposureCalculatorViewModel(
            dependencies: dependencies,
            calculatorModel: calculatorModel
        )
    }
}
