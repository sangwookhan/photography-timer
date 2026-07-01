// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Residual app-hosted context-persistence coverage: the one test that
/// exercises the concrete app-target `UserDefaultsTimerMetadataStore`
/// (against an isolated `UserDefaults(suiteName:)`). The 14
/// store-agnostic context/restore tests moved off-simulator to
/// `CalculatorContextPersistenceTests` in PTimerKitTests.
@MainActor
final class ContextPersistenceUserDefaultsTests: XCTestCase {

    func testRelaunchWithCorruptedMetadataSnapshotKeepsTimerRestoreIndependent() throws {
        let suiteName = "ExposureCalculatorViewModelTests.corrupted.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let timerStore = InMemoryTimerPersistenceStore()
        let timerID = UUID()
        timerStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(
                timers: [
                    TimerState(
                        id: timerID,
                        duration: 10,
                        startDate: Date(timeIntervalSince1970: 100),
                        endDate: Date(timeIntervalSince1970: 110),
                        pausedRemainingTime: nil,
                        pausedAt: nil,
                        status: .running
                    ),
                ]
            )
        )
        userDefaults.set(Data("corrupted-metadata".utf8), forKey: "ptimer.timer-metadata.snapshot")

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 104) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: UserDefaultsTimerMetadataStore(userDefaults: userDefaults)
        )
        XCTAssertEqual(viewModel.timers.map(\.id), [timerID])
        XCTAssertEqual(viewModel.timers.map(\.status), [.running])
        XCTAssertEqual(viewModel.timers.map(\.name), [String(localized: "Timer - \("10s")")])
        XCTAssertEqual(viewModel.timers.map(\.basisSummary), [String(localized: "Manual timer")])
    }
}
