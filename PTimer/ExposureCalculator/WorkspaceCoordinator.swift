import Foundation

/// Owns the lifetime of the `@Observable` models that, together, will
/// replace the `ExposureCalculatorViewModel` monolith. Constructed once
/// at app entry from a `ViewModelDependencies` bundle (A4 DI factory).
///
/// PR1+PR2+PR3+PR4+PR5 (`Docs/StructureImprovement/specs/B1-ViewModelDecomposition.md`):
/// holds `CalculatorModel`, `ReciprocityModel`, `TimerWorkspaceModel`,
/// `FilmSelectionModel`, and the legacy `ExposureCalculatorViewModel`,
/// which still serves as the public observable surface for views until
/// PR6 migrates bindings. PR6 removes the legacy ViewModel and adds
/// fitness lint rules F5/F8.
///
/// PR5 of 6 — `WorkspaceCoordinator` becomes the screen's owned
/// reference (`@StateObject` on `ExposureCalculatorScreen`). It holds
/// **no business state** of its own, so the `ObservableObject`
/// conformance carries no `@Published` properties: SwiftUI re-renders
/// only when one of the child observable models (or the legacy
/// ViewModel) changes, where each view observes the surface it cares
/// about. PR6 will flip child views to observe the appropriate model
/// directly via these public references and delete the ViewModel.
///
/// Spec §11 risk mitigation: coordinator stays under 100 lines and
/// holds **no business state** — wiring only.
@MainActor
final class WorkspaceCoordinator: ObservableObject {
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
