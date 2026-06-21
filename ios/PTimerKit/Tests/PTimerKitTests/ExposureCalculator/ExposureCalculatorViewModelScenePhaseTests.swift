// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class CalculatorViewModelScenePhaseTests: XCTestCase {
    @MainActor
    func testReconcileTimersAfterAppBecomesActivePublishesUpdatedTimerStateWithoutUserInteraction() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = RuntimeBackedTimerManaging(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        var nonEmptyEmissions: [[RunningTimerItem]] = []

        let cancellable = viewModel.$timers.sink { timers in
            guard !timers.isEmpty else {
                return
            }

            nonEmptyEmissions.append(timers)
        }
        defer { cancellable.cancel() }

        viewModel.startTimer(from: 10)

        currentDate = startDate.addingTimeInterval(4)
        viewModel.reconcileTimersAfterAppBecomesActive()

        XCTAssertEqual(nonEmptyEmissions.count, 2)
        XCTAssertEqual(nonEmptyEmissions[0].first?.status, .running)
        XCTAssertEqual(try XCTUnwrap(nonEmptyEmissions[0].first).remainingTime, 10, accuracy: 0.0001)
        XCTAssertEqual(nonEmptyEmissions[1].first?.status, .running)
        XCTAssertEqual(try XCTUnwrap(nonEmptyEmissions[1].first).remainingTime, 6, accuracy: 0.0001)
    }

    @MainActor
    func testReconcileTimersAfterAppBecomesActiveUpdatesCompletedDisplayState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = RuntimeBackedTimerManaging(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 2)

        currentDate = startDate.addingTimeInterval(4)
        viewModel.reconcileTimersAfterAppBecomesActive()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.remainingTime, 0, accuracy: 0.0001)
    }
}
