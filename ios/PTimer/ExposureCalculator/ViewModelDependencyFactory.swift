import Foundation
import PTimerKit
import PTimerCore


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
            contextPersistenceStore: UserDefaultsCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: UserDefaultsCameraSlotSessionStore(),
            metadataPersistenceStore: UserDefaultsTimerMetadataStore(),
            lockScreenTargetExposer: ActivityKitLockScreenTimerTargetExposer(),
            customFilmLibrary: CustomFilmLibrary(
                store: UserDefaultsCustomFilmLibraryStore()
            )
        )
    }

    static func test() -> ViewModelDependencies {
        ViewModelDependencies(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            presetFilms: LaunchPresetFilmCatalog.films,
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: NoOpCameraSlotSessionPersistenceStore(),
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            lockScreenTargetExposer: NoOpLockScreenTimerTargetExposer(),
            customFilmLibrary: CustomFilmLibrary(
                store: NoOpCustomFilmLibraryStore()
            )
        )
    }
}
