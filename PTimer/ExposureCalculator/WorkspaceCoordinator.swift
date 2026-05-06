import Foundation

/// Composition root for the four `@Observable` models that share calc
/// state, reciprocity collaborators, timer state, and film selection.
/// Constructed once at app entry from a `ViewModelDependencies` bundle
/// (see `ViewModelDependencyFactory.production()`); the screen owns
/// it as `@StateObject` so its lifetime matches the workspace.
///
/// The coordinator holds no business state of its own — wiring only.
/// SwiftUI re-renders are driven by whichever child observable surface
/// the consuming view binds to (the four child models or the
/// `ExposureCalculatorViewModel` facade). The `ObservableObject`
/// conformance carries no `@Published` properties; it exists solely
/// so the screen can use `@StateObject` for lifetime ownership.
@MainActor
final class WorkspaceCoordinator: ObservableObject {
    let calculatorModel: CalculatorModel
    let reciprocityModel: ReciprocityModel
    let timerWorkspaceModel: TimerWorkspaceModel
    let filmSelectionModel: FilmSelectionModel
    let cameraSlotSessionModel: CameraSlotSessionModel
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
            currentNDStep: { calculatorModel.ndStep },
            currentScaleMode: { calculatorModel.scaleMode }
        )
        let cameraSlotSessionModel = CameraSlotSessionModel()
        self.calculatorModel = calculatorModel
        self.reciprocityModel = reciprocityModel
        self.timerWorkspaceModel = timerWorkspaceModel
        self.filmSelectionModel = filmSelectionModel
        self.cameraSlotSessionModel = cameraSlotSessionModel
        self.viewModel = ExposureCalculatorViewModel(
            dependencies: dependencies,
            calculatorModel: calculatorModel,
            reciprocityModel: reciprocityModel,
            timerWorkspaceModel: timerWorkspaceModel,
            filmSelectionModel: filmSelectionModel,
            cameraSlotSessionModel: cameraSlotSessionModel
        )
    }
}
