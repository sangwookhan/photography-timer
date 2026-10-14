// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore
import PTimerKit

/// In-memory camera-slot session store with both the legacy snapshot
/// and the managed camera list, so tests can seed a legacy payload,
/// seed or reject a managed payload, and inspect what a launch wrote.
final class InMemoryCameraListSessionStore: CameraSlotSessionPersistenceStoring {
    var legacy: PersistentCameraSlotSessionSnapshot?
    var managed: ManagedCameraListLoadResult = .absent
    private(set) var managedSaveCount = 0
    private(set) var legacyWriteCount = 0

    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { legacy }

    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) {
        legacyWriteCount += 1
        legacy = snapshot
    }

    func clearSnapshot() {
        legacyWriteCount += 1
        legacy = nil
    }

    func loadManagedList() -> ManagedCameraListLoadResult { managed }

    func saveManagedList(_ snapshot: PersistentManagedCameraListSnapshot) {
        managedSaveCount += 1
        managed = .loaded(snapshot)
    }

    var persistedManaged: PersistentManagedCameraListSnapshot? {
        guard case let .loaded(snapshot) = managed else { return nil }
        return snapshot
    }
}

final class InMemoryCameraListMetadataStore: TimerMetadataPersistenceStoring {
    private(set) var snapshot: PersistentTimerMetadataCollection?
    func loadSnapshot() -> PersistentTimerMetadataCollection? { snapshot }
    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection) { self.snapshot = snapshot }
    func clearSnapshot() { snapshot = nil }
}

final class InMemoryCameraListTimerStore: TimerPersistenceStoring {
    private(set) var snapshot: PersistentTimerCollectionSnapshot?
    func loadSnapshot() -> PersistentTimerCollectionSnapshot? { snapshot }
    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) { self.snapshot = snapshot }
    func clearSnapshot() { snapshot = nil }
}
