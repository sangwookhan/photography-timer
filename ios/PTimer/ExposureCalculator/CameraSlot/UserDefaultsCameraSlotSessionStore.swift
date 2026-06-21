// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore
import PTimerKit

/// `UserDefaults`-backed store. Writes JSON under a dedicated key so
/// the legacy single-context persistence and the new multi-slot
/// session never share a key — prevents accidental cross-decode and
/// lets the migration step inspect both stores side by side.
public struct UserDefaultsCameraSlotSessionStore: CameraSlotSessionPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.camera-slot-session.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
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
}
