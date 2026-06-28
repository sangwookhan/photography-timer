// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// The ND notation mode is an app-global display preference: it
/// defaults to `.stops`, persists on change, and restores on launch.
/// These assertions are the persistence contract for PTIMER-187.
final class NDNotationSettingPersistenceTests: XCTestCase {
    private final class SpyDisplaySettingStore: DisplaySettingStoring {
        var loadReturn: PersistentDisplaySettings?
        private(set) var saved: PersistentDisplaySettings?

        init(loadReturn: PersistentDisplaySettings? = nil) {
            self.loadReturn = loadReturn
        }

        func loadSettings() -> PersistentDisplaySettings? { loadReturn }
        func saveSettings(_ settings: PersistentDisplaySettings) { saved = settings }
        func clearSettings() { saved = nil }
    }

    @MainActor
    func testDefaultIsStopsWhenNoStoredValue() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            displaySettingStore: SpyDisplaySettingStore()
        )

        XCTAssertEqual(viewModel.ndNotationMode, .stops)
    }

    @MainActor
    func testChangingModePersists() {
        let store = SpyDisplaySettingStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            displaySettingStore: store
        )

        viewModel.ndNotationMode = .filterFactor

        XCTAssertEqual(store.saved?.restoredNDNotationMode, .filterFactor)
    }

    @MainActor
    func testRestoresPersistedModeOnLaunch() {
        let store = SpyDisplaySettingStore(
            loadReturn: PersistentDisplaySettings(ndNotationMode: .opticalDensity)
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            displaySettingStore: store
        )

        XCTAssertEqual(viewModel.ndNotationMode, .opticalDensity)
    }

    func testAbsentRawValueRestoresStops() throws {
        // Forward-compat: an absent/unknown raw value decodes to the
        // shipping default rather than failing.
        let settings = PersistentDisplaySettings(ndNotationMode: .filterFactor)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PersistentDisplaySettings.self, from: data)
        XCTAssertEqual(decoded.restoredNDNotationMode, .filterFactor)

        let empty = try JSONDecoder().decode(
            PersistentDisplaySettings.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(empty.restoredNDNotationMode, .stops)
    }
}
