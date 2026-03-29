import XCTest
@testable import PTimer

final class ExposureCalculatorViewModelTests: XCTestCase {
    @MainActor
    func testStartTimerCreatesDisplayItemThroughManager() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutterInput = "1/30"
        viewModel.ndInput = "ND64"
        viewModel.startTimer()

        XCTAssertEqual(timerManager.timers.count, 1)
        XCTAssertEqual(viewModel.timers.count, 1)
        XCTAssertEqual(viewModel.runningTimerCount, 1)
        XCTAssertEqual(viewModel.timers[0].name, "ND64 - 2.1s")
        XCTAssertEqual(viewModel.timers[0].status, TimerStatus.running)
        XCTAssertEqual(viewModel.timers[0].remainingTime, 2.1333333333, accuracy: 0.0001)
    }

    @MainActor
    func testStartTimerFromDomainAPIUsesProvidedResult() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 30)

        XCTAssertEqual(timerManager.timers.count, 1)
        XCTAssertEqual(viewModel.timers.first?.name, "Timer - 30s")
        XCTAssertEqual(viewModel.runningTimerCount, 1)
    }

    @MainActor
    func testClearCompletedTimersRemovesCompletedDisplayItems() {
        let startDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutterInput = "1"
        viewModel.ndInput = "1"
        viewModel.startTimer()

        timerManager.tick(now: startDate.addingTimeInterval(1))
        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.completed)

        viewModel.clearCompletedTimers()

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertTrue(timerManager.timers.isEmpty)
    }

    @MainActor
    func testStopTimerUpdatesViewModelState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(4)
        viewModel.stopTimer(id: id)

        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.stopped)
        let remainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(remainingTime, 6, accuracy: 0.0001)
    }

    @MainActor
    func testStoppedTimerRemainingTimeStaysStableInViewModel() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.stopTimer(id: id)

        let stoppedRemainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.stopped)
        XCTAssertEqual(stoppedRemainingTime, 5, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(12)
        timerManager.tick(now: currentDate)

        let stableRemainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.stopped)
        XCTAssertEqual(stableRemainingTime, 5, accuracy: 0.0001)
    }

    @MainActor
    func testCompletedTimerShowsZeroRemainingTimeInViewModel() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 2)

        currentDate = startDate.addingTimeInterval(4)
        timerManager.tick(now: currentDate)

        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.completed)
        let remainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(remainingTime, 0, accuracy: 0.0001)
    }
}
