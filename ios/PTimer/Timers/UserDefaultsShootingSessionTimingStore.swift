// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

#if DEBUG
import Foundation
import PTimerKit

struct UserDefaultsShootingSessionTimingStore: ShootingSessionTimingStoring {
    private let key = "ptimer.debug.short-session-intervals"
    func loadShortenedIntervals() -> Bool { UserDefaults.standard.bool(forKey: key) }
    func saveShortenedIntervals(_ enabled: Bool) { UserDefaults.standard.set(enabled, forKey: key) }
}
#endif
