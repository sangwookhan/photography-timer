// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import PTimerCore
import PTimerKit

/// PTIMER-215: decode is per-record and version-gated (see
/// `PersistentTimerMetadataCollection.decode(from:)`). On a decode failure the
/// raw payload is copied to a sibling `.quarantine` key before any save can
/// overwrite it, and a signal is logged. Storage key is unchanged.
struct UserDefaultsTimerMetadataStore: TimerMetadataPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let quarantineKey: String
    private let encoder = JSONEncoder()
    private static let log = Logger(subsystem: "com.sangwook.ptimer", category: "persistence")

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.timer-metadata.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
        self.quarantineKey = snapshotKey + ".quarantine"
    }

    func loadSnapshot() -> PersistentTimerMetadataCollection? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        let result = PersistentTimerMetadataCollection.decode(from: data)
        if result.indicatesFailure {
            userDefaults.set(data, forKey: quarantineKey)
            Self.log.error(
                """
                Timer metadata decode degraded: outcome=\(result.outcome.rawValue, privacy: .public) \
                dropped=\(result.droppedRecordCount, privacy: .public); raw payload quarantined.
                """
            )
        }
        return result.snapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        // Clears the live collection only. The workspace calls this whenever
        // the metadata set empties (a normal remove-to-empty), so it must not
        // destroy the quarantine; the quarantine is replaced only by a later
        // failed load.
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
