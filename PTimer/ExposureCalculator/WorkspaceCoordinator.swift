import Foundation

/// Owns the lifetime of the `@Observable` models that, together, will
/// replace the `ExposureCalculatorViewModel` monolith. Constructed once
/// at app entry from a `ViewModelDependencies` bundle (A4 DI factory).
///
/// PR1+PR2+PR3+PR4 (`Docs/StructureImprovement/specs/B1-ViewModelDecomposition.md`):
/// holds `CalculatorModel`, `ReciprocityModel`, `TimerWorkspaceModel`,
/// `FilmSelectionModel`, and the legacy `ExposureCalculatorViewModel`,
/// which still serves as the public observable surface for views until
/// PR5 migrates bindings. PR6 removes the legacy ViewModel and adds
/// fitness lint rules F5/F8.
///
/// Spec §11 risk mitigation: coordinator stays under 100 lines and
/// holds **no business state** — wiring only.
@MainActor
final class WorkspaceCoordinator {
    let calculatorModel: CalculatorModel
    let reciprocityModel: ReciprocityModel
    let timerWorkspaceModel: TimerWorkspaceModel
    let filmSelectionModel: FilmSelectionModel
    let viewModel: ExposureCalculatorViewModel

    init(dependencies: ViewModelDependencies) {
        let calculatorModel = CalculatorModel(calculator: dependencies.calculator)
        let reciprocityModel = ReciprocityModel()
        let timerWorkspaceModel = TimerWorkspaceModel(
            timerManager: dependencies.timerManager,
            metadataPersistenceStore: dependencies.metadataPersistenceStore,
            defaultName: { duration in
                "Timer - \(calculatorModel.calculator.formatShutter(duration))"
            }
        )
        let filmSelectionModel = FilmSelectionModel(
            presetFilms: dependencies.presetFilms,
            contextPersistenceStore: dependencies.contextPersistenceStore,
            currentBaseShutterSeconds: { calculatorModel.baseShutterSeconds },
            currentNDStop: { calculatorModel.ndStop }
        )
        self.calculatorModel = calculatorModel
        self.reciprocityModel = reciprocityModel
        self.timerWorkspaceModel = timerWorkspaceModel
        self.filmSelectionModel = filmSelectionModel
        self.viewModel = ExposureCalculatorViewModel(
            dependencies: dependencies,
            calculatorModel: calculatorModel,
            reciprocityModel: reciprocityModel,
            timerWorkspaceModel: timerWorkspaceModel,
            filmSelectionModel: filmSelectionModel
        )
    }
}
