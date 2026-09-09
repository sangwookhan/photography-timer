// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import PTimerCore
import PTimerKit

/// Production store for the filter inventory (Filter Set contract).
/// Encodes the snapshot to JSON under a dedicated UserDefaults key,
/// separate from the camera-slot session so the inventory can be
/// cleared or migrated independently.
///
/// Decode is per-record and version-gated through
/// `PersistentFilterInventorySnapshot.decode(from:)`: a payload
/// written by a newer schema degrades only the affected Filter Set.
/// On any decode failure the raw payload is copied to a sibling
/// quarantine key and a signal is logged, mirroring the custom-film
/// library store. `clearSnapshot()` clears the live collection only.
struct UserDefaultsFilterInventoryStore: FilterInventoryStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let quarantineKey: String
    private let encoder = JSONEncoder()
    private static let log = Logger(subsystem: "com.sangwook.ptimer", category: "persistence")

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.filter-inventory.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
        self.quarantineKey = snapshotKey + ".quarantine"
    }

    func loadSnapshot() -> PersistentFilterInventorySnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }
        let result = PersistentFilterInventorySnapshot.decode(from: data)
        if result.indicatesFailure {
            userDefaults.set(data, forKey: quarantineKey)
            Self.log.error(
                """
                Filter inventory decode degraded: outcome=\(result.outcome.rawValue, privacy: .public) \
                dropped=\(result.droppedRecordCount, privacy: .public); raw payload quarantined.
                """
            )
        }
        return result.snapshot
    }

    func saveSnapshot(_ snapshot: PersistentFilterInventorySnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
