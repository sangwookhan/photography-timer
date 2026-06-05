import Foundation
import PTimerKit

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
    let contextPersistenceStore: ExposureCalculatorContextStoring
    /// New multi-slot session store. Source of truth for camera-slot
    /// state across launches.
    let cameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring
    let metadataPersistenceStore: TimerMetadataPersistenceStoring
    let lockScreenTargetExposer: LockScreenTimerTargetExposing
    /// Photographer-authored custom film library. In
    /// Increment 1 this is purely in-memory; Increment 2 swaps in a
    /// persisted backing through a `*Storing` collaborator without
    /// changing the model's observation surface.
    let customFilmLibrary: CustomFilmLibrary
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
