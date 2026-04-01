import XCTest
@testable import PTimer

final class ExposureCalculatorViewModelTests: XCTestCase {
    @MainActor
    func testCanStartTimerDependsOnValidCalculationInputs() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        XCTAssertTrue(viewModel.canStartTimer)
    }

    @MainActor
    func testFormatTimerClockUsesLeadingZeroMinutesAndSeconds() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimerClock(0), "00:00")
        XCTAssertEqual(viewModel.formatTimerClock(5), "00:05")
        XCTAssertEqual(viewModel.formatTimerClock(59), "00:59")
        XCTAssertEqual(viewModel.formatTimerClock(60), "01:00")
        XCTAssertEqual(viewModel.formatTimerClock(65), "01:05")
        XCTAssertEqual(viewModel.formatTimerClock(3599), "59:59")
    }

    @MainActor
    func testFormatTimerClockClampsSubsecondAndNegativeValuesToZero() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimerClock(0.9), "00:00")
        XCTAssertEqual(viewModel.formatTimerClock(-3), "00:00")
    }

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

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        XCTAssertEqual(timerManager.timers.count, 1)
        XCTAssertEqual(viewModel.timers.count, 1)
        XCTAssertEqual(viewModel.runningTimerCount, 1)
        XCTAssertEqual(viewModel.timers[0].name, "6 stop - 2s")
        XCTAssertEqual(viewModel.timers[0].status, TimerStatus.running)
        XCTAssertEqual(viewModel.timers[0].remainingTime, 2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timers[0].basisSummary, "Base 1/30s · 6 stop")
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

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
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
        XCTAssertEqual(viewModel.formatTimerClock(remainingTime), "00:00")
    }

    @MainActor
    func testExistingTimerMetadataDoesNotChangeAfterInputUpdates() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let initialTimer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(initialTimer.name, "6 stop - 2s")
        XCTAssertEqual(initialTimer.basisSummary, "Base 1/30s · 6 stop")

        viewModel.baseShutter = 1
        viewModel.ndStop = 3

        let timerAfterInputChange = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timerAfterInputChange.name, "6 stop - 2s")
        XCTAssertEqual(timerAfterInputChange.basisSummary, "Base 1/30s · 6 stop")
    }

    @MainActor
    func testNDStopSelectionUpdatesCalculationImmediately() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        guard case .success(let nd64Result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result for 6-stop ND")
        }

        XCTAssertEqual(nd64Result.resultShutterSeconds, 2, accuracy: 0.0001)

        viewModel.ndStop = 10

        guard case .success(let nd1000Result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result for 10-stop ND")
        }

        XCTAssertEqual(nd1000Result.resultShutterSeconds, 30, accuracy: 0.0001)
    }
}
