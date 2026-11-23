// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import PTimerKit
import PTimerCore

@MainActor
enum ViewModelDependencyFactory {
    static func production() -> ViewModelDependencies {
        // The shared audio coordinator: the completion feedback (foreground
        // alarm) and the UI (observing soundingTimerID to offer stop-alarm) use
        // one instance and one AVAudioSession (PTIMER-73).
        let timerAudio = AVAudioTimerAlarmPlayer.shared
        let records = makeTimerRecords()
        #if DEBUG
        let sessionTiming: ShootingSessionTimingStoring = UserDefaultsShootingSessionTimingStore()
        #else
        let sessionTiming: ShootingSessionTimingStoring = NoOpShootingSessionTimingStore()
        #endif
        return ViewModelDependencies(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                completionAlertService: ForegroundTimerCompletionAlertService(
                    feedbackPlayer: SystemTimerCompletionFeedbackPlayer(alarmPlayer: timerAudio)
                ),
                completionNotificationScheduler: UserNotificationTimerCompletionScheduler(),
                persistenceStore: TimerRecordRuntimeStore(repository: records)
            ),
            presetFilms: LaunchPresetFilmCatalogV2.userSelectableFilms,
            contextPersistenceStore: UserDefaultsCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: UserDefaultsCameraSlotSessionStore(),
            cameraNameSequenceStore: UserDefaultsCameraNameSequenceStore(),
            metadataPersistenceStore: TimerRecordMetadataStore(repository: records),
            displaySettingStore: UserDefaultsDisplaySettingStore(),
            lockScreenTargetExposer: ActivityKitLockScreenTimerTargetExposer(),
            customFilmLibrary: CustomFilmLibrary(
                store: UserDefaultsCustomFilmLibraryStore()
            ),
            filterInventoryStore: UserDefaultsFilterInventoryStore(),
            initialFilterInventory: .samples(),
            shootingSessionStore: records,
            shootingSessionTimingStore: sessionTiming
        )
    }

    private static func makeTimerRecords() -> TimerRecordRepository {
        let directory = URL.applicationSupportDirectory.appending(path: "PTimer", directoryHint: .isDirectory)
        let url = directory.appending(path: "timer-records.json")
        let needsMigration = !FileManager.default.fileExists(atPath: url.path)
        return TimerRecordRepository(
            read: {
                do { return try Data(contentsOf: url) } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
            },
            write: { data in
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                    // Retire the migration source only after the complete archive
                    // is retained, so later absence cannot replay stale History.
                    UserDefaultsTimerPersistenceStore().clearSnapshot()
                    UserDefaultsTimerMetadataStore().clearSnapshot()
                    return .saved
                } catch { return .uncertain }
            },
            quarantine: { data in
                try? data.write(to: directory.appending(path: "timer-records.quarantine.json"), options: .atomic)
                Logger(subsystem: "com.sangwook.ptimer", category: "persistence")
                    .error("Timer record archive recovery required; original data quarantined.")
            },
            legacyTimers: needsMigration ? UserDefaultsTimerPersistenceStore().loadSnapshot() : nil,
            legacyMetadata: needsMigration ? UserDefaultsTimerMetadataStore().loadSnapshot() : nil
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
