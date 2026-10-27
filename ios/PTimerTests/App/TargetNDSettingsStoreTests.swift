// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

@MainActor
final class TargetNDSettingsStoreTests: XCTestCase {
    func testSettingsRoundTripWithoutTouchingCameraOrTimerData() throws {
        let suite = "target-nd-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1, 2, 3]), forKey: "camera-sentinel")
        defaults.set(Data([4, 5, 6]), forKey: "timer-sentinel")
        let store = UserDefaultsTargetNDSettingsStore(userDefaults: defaults, snapshotKey: "suggestions")
        XCTAssertNil(store.loadSettings())
        let model = TargetNDSettingsModel(store: store)
        model.settings.isEnabled = false
        model.settings.positive = .extended
        let restored = TargetNDSettingsModel(store: UserDefaultsTargetNDSettingsStore(userDefaults: defaults, snapshotKey: "suggestions"))
        XCTAssertEqual(restored.settings, model.settings)
        XCTAssertEqual(defaults.data(forKey: "camera-sentinel"), Data([1, 2, 3]))
        XCTAssertEqual(defaults.data(forKey: "timer-sentinel"), Data([4, 5, 6]))
        defaults.set(Data("invalid".utf8), forKey: "suggestions")
        XCTAssertEqual(TargetNDSettingsModel(store: store).settings, TargetNDSettings())
    }
}
