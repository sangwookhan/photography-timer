import Foundation

struct ViewModelDependencies {
    let calculator: ExposureCalculator
    let timerManager: TimerManager
    let presetFilms: [FilmIdentity]
    /// Legacy single-context store. Read once at first launch as a
    /// migration source (see
    /// `CameraSlotSessionPersistenceController.loadOrMigrate`); the
    /// active-slot writer in `FilmSelectionModel.persistContext` keeps
    /// using it so older app versions reading the legacy key still
    /// see a sensible single-camera context.
    let contextPersistenceStore: ExposureCalculatorContextPersistenceStoring
    /// New multi-slot session store. Source of truth for camera-slot
    /// state across launches.
    let cameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring
    let metadataPersistenceStore: TimerMetadataPersistenceStoring
    let lockScreenTargetExposer: LockScreenTimerTargetExposing
}

@MainActor
enum ViewModelDependencyFactory {
    static func production() -> ViewModelDependencies {
        ViewModelDependencies(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                completionAlertService: ForegroundTimerCompletionAlertService(
                    feedbackPlayer: SystemTimerCompletionFeedbackPlayer()
                ),
                completionNotificationScheduler: UserNotificationTimerCompletionScheduler(),
                persistenceStore: UserDefaultsTimerPersistenceStore()
            ),
            presetFilms: LaunchPresetFilmCatalog.films,
            contextPersistenceStore: UserDefaultsExposureCalculatorContextPersistenceStore(),
            cameraSlotSessionPersistenceStore: UserDefaultsCameraSlotSessionPersistenceStore(),
            metadataPersistenceStore: UserDefaultsTimerMetadataPersistenceStore(),
            lockScreenTargetExposer: ActivityKitLockScreenTimerTargetExposer()
        )
    }

    static func test() -> ViewModelDependencies {
        ViewModelDependencies(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            presetFilms: LaunchPresetFilmCatalog.films,
            contextPersistenceStore: NoOpExposureCalculatorContextPersistenceStore(),
            cameraSlotSessionPersistenceStore: NoOpCameraSlotSessionPersistenceStore(),
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            lockScreenTargetExposer: NoOpLockScreenTimerTargetExposer()
        )
    }
}
