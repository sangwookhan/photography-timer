// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit

struct UserDefaultsTargetNDSettingsStore: TargetNDSettingsStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String

    init(userDefaults: UserDefaults = .standard, snapshotKey: String = "ptimer.target-nd-settings.snapshot") {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSettings() -> PersistentTargetNDSettings? {
        guard let data = userDefaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(PersistentTargetNDSettings.self, from: data)
    }

    func saveSettings(_ settings: PersistentTargetNDSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: snapshotKey)
    }
}
