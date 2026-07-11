// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import PTimerCore
import PTimerKit

/// Production store. Encodes the snapshot to JSON and writes it
/// under a dedicated UserDefaults key, kept separate from the
/// preset catalog and camera-slot session keys so the custom
/// library can be cleared (or migrated) independently.
///
/// PTIMER-215: decode is per-record and version-gated. A payload
/// written by a newer schema degrades only the affected film; the
/// surviving films still load. When a decode fails (a dropped record,
/// a version mismatch, or a malformed root) the original raw payload
/// is copied to a sibling quarantine key so it survives the next save,
/// and a signal is logged. Storage keys are unchanged; the quarantine
/// key is additive.
struct UserDefaultsCustomFilmLibraryStore: CustomFilmLibraryStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let quarantineKey: String
    private let encoder = JSONEncoder()
    private static let log = Logger(subsystem: "com.sangwook.ptimer", category: "persistence")

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.exposure-calculator.custom-films.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
        self.quarantineKey = snapshotKey + ".quarantine"
    }

    func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        let result = PersistentCustomFilmLibrarySnapshot.decode(from: data)
        if result.indicatesFailure {
            // Preserve the raw payload before any subsequent save can
            // overwrite the main key, then surface a signal. Latest failed
            // payload wins; a good load never clears the quarantine.
            userDefaults.set(data, forKey: quarantineKey)
            Self.log.error(
                """
                Custom film library decode degraded: outcome=\(result.outcome.rawValue, privacy: .public) \
                dropped=\(result.droppedRecordCount, privacy: .public); raw payload quarantined.
                """
            )
        }
        return result.snapshot
    }

    func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        // Explicit reset clears the quarantine too; a normal save never does.
        userDefaults.removeObject(forKey: snapshotKey)
        userDefaults.removeObject(forKey: quarantineKey)
    }
}
