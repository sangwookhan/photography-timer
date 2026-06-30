// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit
import PTimerCore

@MainActor
enum ViewModelDependencyFactory {
    static func production() -> ViewModelDependencies {
        // One audio coordinator shared by the completion feedback (loud alarm)
        // and the timer manager (background-audio keep-alive), so both speak to a
        // single AVAudioSession (PTIMER-73).
        let timerAudio = AVAudioTimerAlarmPlayer()
        return ViewModelDependencies(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                completionAlertService: ForegroundTimerCompletionAlertService(
                    feedbackPlayer: SystemTimerCompletionFeedbackPlayer(alarmPlayer: timerAudio)
                ),
                completionNotificationScheduler: UserNotificationTimerCompletionScheduler(),
                persistenceStore: UserDefaultsTimerPersistenceStore(),
                backgroundAudioKeepAlive: timerAudio
            ),
            presetFilms: LaunchPresetFilmCatalogV2.films,
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
            presetFilms: LaunchPresetFilmCatalogV2.films,
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
