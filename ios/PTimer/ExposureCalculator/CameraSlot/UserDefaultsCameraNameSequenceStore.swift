// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit

/// `UserDefaults`-backed automatic camera-name sequence, under its own
/// key so it is independent of the managed camera list payload.
public struct UserDefaultsCameraNameSequenceStore: CameraNameSequenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.camera-name-sequence.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    public func load() -> CameraNameSequenceLoadResult {
        guard let object = userDefaults.object(forKey: snapshotKey) else {
            return .absent
        }
        guard let data = object as? Data,
              let snapshot = try? decoder.decode(PersistentCameraNameSequenceSnapshot.self, from: data),
              snapshot.schemaVersion == PersistentCameraNameSequenceSnapshot.currentSchemaVersion,
              snapshot.nextNumber >= 1 else {
            return .unusable
        }
        return .value(snapshot.nextNumber)
    }

    @discardableResult
    public func save(nextNumber: Int) -> Bool {
        guard nextNumber >= 1,
              let data = try? encoder.encode(PersistentCameraNameSequenceSnapshot(nextNumber: nextNumber)) else {
            return false
        }
        userDefaults.set(data, forKey: snapshotKey)
        return true
    }
}
