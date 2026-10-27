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
    /// The dedicated automatic camera-name sequence store. Defaults to an
    /// in-memory store so existing call sites and tests stay unchanged.
    public let cameraNameSequenceStore: CameraNameSequenceStoring
    public let metadataPersistenceStore: TimerMetadataPersistenceStoring
    public let targetNDSettingsStore: TargetNDSettingsStoring
    public let displaySettingStore: DisplaySettingStoring
    public let lockScreenTargetExposer: any LockScreenTimerTargetExposing
    public let customFilmLibrary: CustomFilmLibrary
    /// Filter inventory store (Filter Set contract). Defaults to the
    /// no-op store so existing call sites and tests stay unchanged.
    public let filterInventoryStore: FilterInventoryStoring
    /// Inventory a fresh installation starts with, used only when the
    /// store holds nothing yet (FILTER-SET-008). Empty by default.
    public let initialFilterInventory: FilterInventory

    public init(
        calculator: ExposureCalculator,
        timerManager: any TimerManaging,
        presetFilms: [FilmIdentity],
        contextPersistenceStore: ExposureCalculatorContextStoring,
        cameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring,
        cameraNameSequenceStore: CameraNameSequenceStoring = InMemoryCameraNameSequenceStore(),
        metadataPersistenceStore: TimerMetadataPersistenceStoring,
        displaySettingStore: DisplaySettingStoring = NoOpDisplaySettingStore(),
        lockScreenTargetExposer: any LockScreenTimerTargetExposing,
        customFilmLibrary: CustomFilmLibrary,
        filterInventoryStore: FilterInventoryStoring = NoOpFilterInventoryStore(),
        initialFilterInventory: FilterInventory = .empty,
        targetNDSettingsStore: TargetNDSettingsStoring = NoOpTargetNDSettingsStore()
    ) {
        self.calculator = calculator
        self.timerManager = timerManager
        self.presetFilms = presetFilms
        self.contextPersistenceStore = contextPersistenceStore
        self.cameraSlotSessionPersistenceStore = cameraSlotSessionPersistenceStore
        self.cameraNameSequenceStore = cameraNameSequenceStore
        self.metadataPersistenceStore = metadataPersistenceStore
        self.displaySettingStore = displaySettingStore
        self.targetNDSettingsStore = targetNDSettingsStore
        self.lockScreenTargetExposer = lockScreenTargetExposer
        self.customFilmLibrary = customFilmLibrary
        self.filterInventoryStore = filterInventoryStore
        self.initialFilterInventory = initialFilterInventory
    }
}
