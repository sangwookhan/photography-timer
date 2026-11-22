// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class ExposureCalculatorViewModelTests: XCTestCase {

    @MainActor
    func testTimerDurationDoesNotUseForbiddenCharacters() throws {
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

        let duration = viewModel.formatTimeDisplay(timer.duration)
        let forbiddenCharacters = CharacterSet(charactersIn: "/()")

        XCTAssertNil(duration.primary.rangeOfCharacter(from: forbiddenCharacters))
        XCTAssertNil(duration.secondary.rangeOfCharacter(from: forbiddenCharacters))
    }
}
