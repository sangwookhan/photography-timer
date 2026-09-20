// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

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
    public let displaySettingStore: DisplaySettingStoring
    public let lockScreenTargetExposer: any LockScreenTimerTargetExposing
    public let customFilmLibrary: CustomFilmLibrary
    /// Filter inventory store (Filter Set contract). Defaults to the
    /// no-op store so existing call sites and tests stay unchanged.
    public let filterInventoryStore: FilterInventoryStoring

    public init(
        calculator: ExposureCalculator,
        timerManager: any TimerManaging,
        presetFilms: [FilmIdentity],
        contextPersistenceStore: ExposureCalculatorContextStoring,
        cameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring,
        metadataPersistenceStore: TimerMetadataPersistenceStoring,
        displaySettingStore: DisplaySettingStoring = NoOpDisplaySettingStore(),
        lockScreenTargetExposer: any LockScreenTimerTargetExposing,
        customFilmLibrary: CustomFilmLibrary,
        filterInventoryStore: FilterInventoryStoring = NoOpFilterInventoryStore()
    ) {
        self.calculator = calculator
        self.timerManager = timerManager
        self.presetFilms = presetFilms
        self.contextPersistenceStore = contextPersistenceStore
        self.cameraSlotSessionPersistenceStore = cameraSlotSessionPersistenceStore
        self.metadataPersistenceStore = metadataPersistenceStore
        self.displaySettingStore = displaySettingStore
        self.lockScreenTargetExposer = lockScreenTargetExposer
        self.customFilmLibrary = customFilmLibrary
        self.filterInventoryStore = filterInventoryStore
    }
}
