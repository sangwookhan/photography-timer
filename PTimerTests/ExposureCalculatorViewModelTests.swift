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

        XCTAssertEqual(viewModel.formatTimerClock(0), "0s")
        XCTAssertEqual(viewModel.formatTimerClock(5), "5s")
        XCTAssertEqual(viewModel.formatTimerClock(59), "59s")
        XCTAssertEqual(viewModel.formatTimerClock(60), "01:00")
        XCTAssertEqual(viewModel.formatTimerClock(65), "01:05")
        XCTAssertEqual(viewModel.formatTimerClock(3599), "59:59")
        XCTAssertEqual(viewModel.formatTimerClock(3600), "01:00:00")
        XCTAssertEqual(viewModel.formatTimerClock(90_000), "1d 01:00:00")
        XCTAssertEqual(viewModel.formatTimerClock(2_592_000), "1mo 00:00:00")
        XCTAssertEqual(viewModel.formatTimerClock(31_536_000), "1y 00:00:00")
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

        XCTAssertEqual(viewModel.formatTimerClock(0.9), "0.9s")
        XCTAssertEqual(viewModel.formatTimerClock(-3), "0s")
    }

    @MainActor
    func testFormatTimeDisplayAlwaysShowsRawSecondsAndClock() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimeDisplay(0), TimeDisplay(primary: "0s", secondary: "0s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(-3), TimeDisplay(primary: "0s", secondary: "0s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(5), TimeDisplay(primary: "5s", secondary: "5s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(128), TimeDisplay(primary: "02:08", secondary: "128s"))
    }

    @MainActor
    func testFormatTimeDisplayBoundaryCases() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimeDisplay(0), TimeDisplay(primary: "0s", secondary: "0s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(0.033), TimeDisplay(primary: "0.033s", secondary: "0.033s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(0.125), TimeDisplay(primary: "0.125s", secondary: "0.125s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(0.9), TimeDisplay(primary: "0.9s", secondary: "0.9s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(1), TimeDisplay(primary: "1s", secondary: "1s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(5), TimeDisplay(primary: "5s", secondary: "5s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(21.158), TimeDisplay(primary: "21.2s", secondary: "21.2s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(59.9), TimeDisplay(primary: "59.9s", secondary: "59.9s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(60), TimeDisplay(primary: "01:00", secondary: "60s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(61), TimeDisplay(primary: "01:01", secondary: "61s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(3599), TimeDisplay(primary: "59:59", secondary: "3599s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(3600), TimeDisplay(primary: "01:00:00", secondary: "3600s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(86_399), TimeDisplay(primary: "23:59:59", secondary: "86399s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(86_400), TimeDisplay(primary: "1d 00:00:00", secondary: "86400s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(2_592_000), TimeDisplay(primary: "1mo 00:00:00", secondary: "2592000s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(31_536_000), TimeDisplay(primary: "1y 00:00:00", secondary: "31536000s"))
    }

    @MainActor
    func testFormatTimeDisplayPrecisionPolicy() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimeDisplay(128.25), TimeDisplay(primary: "02:08", secondary: "128.2s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(12.345), TimeDisplay(primary: "12.3s", secondary: "12.3s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(0.033), TimeDisplay(primary: "0.033s", secondary: "0.033s"))
    }

    @MainActor
    func testFormatDateTimeAndTimerContextSemanticsIncludeDate() {
        let currentDate = Date(timeIntervalSince1970: 100)
        let endDate = Date(timeIntervalSince1970: 9_060)
        let pausedDate = Date(timeIntervalSince1970: 8_940)
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { currentDate }
            )
        )

        let running = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Timer 1",
            basisSummary: "Base 1/30s · 6 stop",
            duration: 120,
            startDate: Date(timeIntervalSince1970: 8_940),
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: currentDate
        )

        let stopped = RunningTimerItem(
            id: UUID(),
            order: 2,
            name: "Timer 2",
            basisSummary: "Base 1/30s · 6 stop",
            duration: 120,
            startDate: Date(timeIntervalSince1970: 8_820),
            endDate: nil,
            pausedRemainingTime: 45,
            pausedAt: pausedDate,
            status: .stopped,
            referenceDate: currentDate
        )

        let completed = RunningTimerItem(
            id: UUID(),
            order: 3,
            name: "Timer 3",
            basisSummary: "Base 1/30s · 6 stop",
            duration: 120,
            startDate: Date(timeIntervalSince1970: 8_700),
            endDate: pausedDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: currentDate
        )

        XCTAssertEqual(viewModel.timerTimeContext(for: running), "Ends \(viewModel.formatDateTime(endDate))")
        XCTAssertEqual(viewModel.timerTimeContext(for: stopped), "Paused \(viewModel.formatDateTime(pausedDate))")
        XCTAssertEqual(viewModel.timerTimeContext(for: completed), "Completed \(viewModel.formatDateTime(pausedDate))")
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
        XCTAssertEqual(viewModel.formatTimeDisplay(viewModel.timers[0].remainingTime), TimeDisplay(primary: "2s", secondary: "2s"))
        XCTAssertEqual(viewModel.timers[0].basisSummary, "Base 1/30s · 6 stop")
    }

    @MainActor
    func testRunningTimerDisplaySemanticsPreserveTargetAndContext() throws {
        let currentDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.remainingTime, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.basisSummary, "Base 1/30s · 6 stop")
        XCTAssertEqual(viewModel.timerTargetContext(for: timer), "2s · 2s")
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Ends \(viewModel.formatDateTime(try XCTUnwrap(timer.endDate)))"
        )
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
    func testStoppedTimerDisplaySemanticsPreservePauseMetadataAndRemainResumable() throws {
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

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.stopTimer(id: id)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .stopped)
        XCTAssertEqual(timer.remainingTime, 5, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 8, accuracy: 0.0001)
        XCTAssertEqual(timer.pausedAt, currentDate)
        XCTAssertEqual(viewModel.timerTargetContext(for: timer), "8s · 8s")
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Paused \(viewModel.formatDateTime(try XCTUnwrap(timer.pausedAt)))"
        )

        currentDate = startDate.addingTimeInterval(6)
        viewModel.resumeTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.status, .running)
    }

    @MainActor
    func testResumeTimerUpdatesViewModelState() throws {
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

        XCTAssertEqual(viewModel.timers.first?.status, .stopped)
        XCTAssertEqual(try XCTUnwrap(viewModel.timers.first?.remainingTime), 5, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(6)
        viewModel.resumeTimer(id: id)

        XCTAssertEqual(viewModel.timers.first?.status, .running)
        XCTAssertEqual(try XCTUnwrap(viewModel.timers.first?.remainingTime), 5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timers.count, 1)
        XCTAssertEqual(viewModel.timers.first?.basisSummary, "Manual timer")
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
        XCTAssertEqual(viewModel.formatTimeDisplay(remainingTime), TimeDisplay(primary: "0s", secondary: "0s"))
    }

    @MainActor
    func testCompletedTimerDisplaySemanticsPreserveOriginalDurationAndCompletionMetadata() throws {
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

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.remainingTime, 0, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.completedAt, startDate.addingTimeInterval(2))
        XCTAssertNil(viewModel.timerTargetContext(for: timer))
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Completed \(viewModel.formatDateTime(try XCTUnwrap(timer.completedAt)))"
        )
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
