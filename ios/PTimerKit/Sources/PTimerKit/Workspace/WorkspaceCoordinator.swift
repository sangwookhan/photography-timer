// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

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
public final class WorkspaceCoordinator: ObservableObject {
    public let calculatorModel: CalculatorModel
    public let reciprocityModel: ReciprocityModel
    public let timerWorkspaceModel: TimerWorkspaceModel
    public let filmSelectionModel: FilmSelectionModel
    public let cameraSlotSessionModel: CameraSlotSessionModel
    public let targetShutterModel: TargetShutterModel
    public let customFilmLibrary: CustomFilmLibrary
    public let viewModel: ExposureCalculatorViewModel

    public init(dependencies: ViewModelDependencies) {
        let calculatorModel = CalculatorModel(calculator: dependencies.calculator)
        let reciprocityModel = ReciprocityModel()
        let timerWorkspaceModel = TimerWorkspaceModel(
            timerManager: dependencies.timerManager,
            metadataPersistenceStore: dependencies.metadataPersistenceStore,
            defaultName: { duration in
                "Timer - \(calculatorModel.calculator.formatShutter(duration))"
            }
        )
        // The slot session model is built before `FilmSelectionModel`
        // so the film-selection closure can read the active slot at
        // persistence time — that lets the persisted calculator
        // context capture which slot owns its values.
        let cameraSlotSessionModel = CameraSlotSessionModel()
        let customLibrary = dependencies.customFilmLibrary
        let filmSelectionModel = FilmSelectionModel(
            presetFilms: dependencies.presetFilms,
            contextPersistenceStore: dependencies.contextPersistenceStore,
            currentBaseShutterSeconds: { calculatorModel.baseShutterSeconds },
            currentNDStep: { calculatorModel.ndStep },
            currentScaleMode: { calculatorModel.scaleMode },
            currentActiveCameraSlotID: { cameraSlotSessionModel.activeSlotID },
            currentCustomFilms: { customLibrary.customFilms }
        )
        let targetShutterModel = TargetShutterModel()
        self.calculatorModel = calculatorModel
        self.reciprocityModel = reciprocityModel
        self.timerWorkspaceModel = timerWorkspaceModel
        self.filmSelectionModel = filmSelectionModel
        self.cameraSlotSessionModel = cameraSlotSessionModel
        self.targetShutterModel = targetShutterModel
        self.customFilmLibrary = dependencies.customFilmLibrary
        self.viewModel = ExposureCalculatorViewModel(
            dependencies: dependencies,
            calculatorModel: calculatorModel,
            reciprocityModel: reciprocityModel,
            timerWorkspaceModel: timerWorkspaceModel,
            filmSelectionModel: filmSelectionModel,
            cameraSlotSessionModel: cameraSlotSessionModel,
            targetShutterModel: targetShutterModel,
            customFilmLibrary: dependencies.customFilmLibrary
        )
    }
}
