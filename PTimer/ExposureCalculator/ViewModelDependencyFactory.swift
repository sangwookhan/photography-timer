import Foundation

struct ViewModelDependencies {
    let calculator: ExposureCalculator
    let timerManager: TimerManager
    let presetFilms: [FilmIdentity]
    let contextPersistenceStore: ExposureCalculatorContextPersistenceStoring
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
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            lockScreenTargetExposer: NoOpLockScreenTimerTargetExposer()
        )
    }
}
