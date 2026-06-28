// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore
import PTimerKit

struct UserDefaultsDisplaySettingStore: DisplaySettingStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.display-settings.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSettings() -> PersistentDisplaySettings? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentDisplaySettings.self, from: data)
    }

    func saveSettings(_ settings: PersistentDisplaySettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSettings() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
