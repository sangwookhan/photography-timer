// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class ExposureCalculatorViewModelTests: XCTestCase {

    @MainActor
    func testDisplayDoesNotUseForbiddenCharacters() throws {
        let startDate = Date(timeIntervalSince1970: 100)

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: RuntimeBackedTimerManaging(
                tickInterval: 60,
                dateProvider: { startDate }
            )
        )
        viewModel.scaleMode = .fullStop

        viewModel.startTimer(from: 128)

        let timer = try XCTUnwrap(viewModel.timers.first)

        let primary = viewModel.formatTimeDisplay(timer.duration).primary
        let secondary = viewModel.formatTimeDisplay(timer.duration).secondary
        let context = viewModel.timerTimeContext(for: timer) ?? ""

        let allText = primary + secondary + context

        XCTAssertFalse(allText.contains("/"))
        XCTAssertFalse(allText.contains("("))
        XCTAssertFalse(allText.contains(")"))
    }
}
