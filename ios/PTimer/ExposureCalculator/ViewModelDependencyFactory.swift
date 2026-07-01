// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit
import PTimerCore

@MainActor
enum ViewModelDependencyFactory {
    static func production() -> ViewModelDependencies {
        // The shared audio coordinator: the completion feedback (foreground
        // alarm) and the UI (observing soundingTimerID to offer stop-alarm) use
        // one instance and one AVAudioSession (PTIMER-73).
        let timerAudio = AVAudioTimerAlarmPlayer.shared
        return ViewModelDependencies(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                completionAlertService: ForegroundTimerCompletionAlertService(
                    feedbackPlayer: SystemTimerCompletionFeedbackPlayer(alarmPlayer: timerAudio)
                ),
                completionNotificationScheduler: UserNotificationTimerCompletionScheduler(),
                persistenceStore: UserDefaultsTimerPersistenceStore()
            ),
            presetFilms: LaunchPresetFilmCatalogV2.userSelectableFilms,
            contextPersistenceStore: UserDefaultsCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: UserDefaultsCameraSlotSessionStore(),
            metadataPersistenceStore: UserDefaultsTimerMetadataStore(),
            displaySettingStore: UserDefaultsDisplaySettingStore(),
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
            presetFilms: LaunchPresetFilmCatalogV2.userSelectableFilms,
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
