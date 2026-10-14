// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore
import PTimerKit

/// `UserDefaults`-backed store. Writes JSON under dedicated keys so
/// the legacy single-context persistence, the legacy multi-slot
/// session snapshot, and the managed camera list never share a key —
/// prevents accidental cross-decode and lets the migration step
/// inspect the stores side by side.
public struct UserDefaultsCameraSlotSessionStore: CameraSlotSessionPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let managedKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.camera-slot-session.snapshot",
        managedKey: String = "ptimer.managed-camera-list.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
        self.managedKey = managedKey
    }

    public func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey),
              let snapshot = try? decoder.decode(
                PersistentCameraSlotSessionSnapshot.self,
                from: data
              ) else {
            return nil
        }

        // Reject snapshots written by a future schema we do not
        // understand — return nil so the caller can fall back to
        // legacy migration or fresh defaults rather than acting on
        // misinterpreted data.
        guard snapshot.schemaVersion == PersistentCameraSlotSessionSnapshot.currentSchemaVersion else {
            return nil
        }

        return snapshot
    }

    public func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        userDefaults.set(data, forKey: snapshotKey)
    }

    public func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }

    /// The managed camera list under its own key. A value that is
    /// missing, cannot be decoded, or carries an unknown schema version
    /// reads as absent, like the legacy snapshot above.
    public func loadManagedList() -> ManagedCameraListLoadResult {
        guard let data = userDefaults.data(forKey: managedKey),
              let snapshot = try? decoder.decode(
                PersistentManagedCameraListSnapshot.self,
                from: data
              ),
              snapshot.schemaVersion == PersistentManagedCameraListSnapshot.currentSchemaVersion else {
            return .absent
        }
        return .loaded(snapshot)
    }

    public func saveManagedList(_ snapshot: PersistentManagedCameraListSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        userDefaults.set(data, forKey: managedKey)
    }
}
