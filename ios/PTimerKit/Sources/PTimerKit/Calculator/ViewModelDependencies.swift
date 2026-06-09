import Foundation
import PTimerCore

/// Dependency bundle for the exposure-calculator view-model graph. The app's
/// ViewModelDependencyFactory builds this with concrete OS-backed collaborators;
/// the models depend only on the protocol/abstraction types here.
public struct ViewModelDependencies {
    public let calculator: ExposureCalculator
    public let timerManager: any TimerManaging
    public let presetFilms: [FilmIdentity]
    public let contextPersistenceStore: ExposureCalculatorContextStoring
    public let cameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring
    public let metadataPersistenceStore: TimerMetadataPersistenceStoring
    public let lockScreenTargetExposer: any LockScreenTimerTargetExposing
    public let customFilmLibrary: CustomFilmLibrary

    public init(
        calculator: ExposureCalculator,
        timerManager: any TimerManaging,
        presetFilms: [FilmIdentity],
        contextPersistenceStore: ExposureCalculatorContextStoring,
        cameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring,
        metadataPersistenceStore: TimerMetadataPersistenceStoring,
        lockScreenTargetExposer: any LockScreenTimerTargetExposing,
        customFilmLibrary: CustomFilmLibrary
    ) {
        self.calculator = calculator
        self.timerManager = timerManager
        self.presetFilms = presetFilms
        self.contextPersistenceStore = contextPersistenceStore
        self.cameraSlotSessionPersistenceStore = cameraSlotSessionPersistenceStore
        self.metadataPersistenceStore = metadataPersistenceStore
        self.lockScreenTargetExposer = lockScreenTargetExposer
        self.customFilmLibrary = customFilmLibrary
    }
}
