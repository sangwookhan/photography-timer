// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

@MainActor
final class TargetNDSettingsTests: XCTestCase {
    private final class Store: TargetNDSettingsStoring {
        var saved: PersistentTargetNDSettings?
        func loadSettings() -> PersistentTargetNDSettings? { saved }
        func saveSettings(_ settings: PersistentTargetNDSettings) { saved = settings }
    }

    func testDefaultOnIndependentMediumChoicesSurviveReconstruction() throws {
        let store = Store()
        let model = TargetNDSettingsModel(store: store)
        XCTAssertTrue(model.settings.isEnabled)
        XCTAssertEqual(model.settings.positive, .standard)
        model.settings.isEnabled = false
        model.settings.negative = .extended
        model.settings.digital = .extended
        XCTAssertEqual(model.settings.positive, .standard)
        let bytes = try JSONEncoder().encode(XCTUnwrap(store.saved))
        store.saved = try JSONDecoder().decode(PersistentTargetNDSettings.self, from: bytes)
        XCTAssertEqual(TargetNDSettingsModel(store: store).settings, model.settings)
    }

    func testLegacyMissingAndUnknownFieldsUsePerFieldDefaults() throws {
        let empty = try JSONDecoder().decode(PersistentTargetNDSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.restored, TargetNDSettings())
        let mixed = try JSONDecoder().decode(PersistentTargetNDSettings.self, from: Data(#"{"isEnabled":false,"negativeRaw":"extended","positiveRaw":"future"}"#.utf8))
        XCTAssertFalse(mixed.restored.isEnabled)
        XCTAssertEqual(mixed.restored.negative, .extended)
        XCTAssertEqual(mixed.restored.positive, .standard)
        XCTAssertEqual(mixed.restored.digital, .standard)
    }
}
