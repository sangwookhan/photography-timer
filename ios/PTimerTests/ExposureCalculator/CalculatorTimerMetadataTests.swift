import XCTest
import PTimerCore
@testable import PTimer

final class CalculatorTimerMetadataTests: XCTestCase {
    @MainActor
    func testStartTimerPublishesCapturedMetadataOnFirstRuntimeEmission() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        viewModel.scaleMode = .fullStop
        var nonEmptyEmissions: [[RunningTimerItem]] = []

        let cancellable = viewModel.$timers.sink { timers in
            guard !timers.isEmpty else {
                return
            }

            nonEmptyEmissions.append(timers)
        }
        defer { cancellable.cancel() }

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        XCTAssertEqual(nonEmptyEmissions.count, 1)
        XCTAssertEqual(nonEmptyEmissions.first?.first?.name, "6 stops - 2s")
        XCTAssertEqual(nonEmptyEmissions.first?.first?.basisSummary, "Base 1/30s · 6 stops")
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
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        XCTAssertEqual(timerManager.timers.count, 1)
        XCTAssertEqual(viewModel.timers.count, 1)
        XCTAssertEqual(viewModel.runningTimerCount, 1)
        XCTAssertEqual(viewModel.timers[0].name, "6 stops - 2s")
        XCTAssertEqual(viewModel.timers[0].status, TimerStatus.running)
        XCTAssertEqual(viewModel.timers[0].remainingTime, 2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.formatTimeDisplay(viewModel.timers[0].remainingTime), TimeDisplay(primary: "2s", secondary: "2s"))
        XCTAssertEqual(viewModel.timers[0].basisSummary, "Base 1/30s · 6 stops")
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
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.remainingTime, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.basisSummary, "Base 1/30s · 6 stops")
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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
    func testClearCompletedTimersPreservesActiveMetadataAndRemovesCompletedMetadataBeforeNewTimer() throws {
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
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        viewModel.baseShutter = 1
        viewModel.ndStop = 3
        viewModel.startTimer()

        XCTAssertEqual(viewModel.timers.count, 2)
        XCTAssertEqual(viewModel.timers.map(\.name), ["3 stops - 8s", "6 stops - 2s"])
        XCTAssertEqual(
            viewModel.timers.map(\.basisSummary),
            ["Base 1s · 3 stops", "Base 1/30s · 6 stops"]
        )

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        let completedTimer = try XCTUnwrap(viewModel.timers.first { $0.status == .completed })
        let activeTimer = try XCTUnwrap(viewModel.timers.first { $0.status == .running })

        XCTAssertEqual(completedTimer.name, "6 stops - 2s")
        XCTAssertEqual(completedTimer.basisSummary, "Base 1/30s · 6 stops")
        XCTAssertEqual(activeTimer.name, "3 stops - 8s")
        XCTAssertEqual(activeTimer.basisSummary, "Base 1s · 3 stops")

        viewModel.clearCompletedTimers()

        XCTAssertEqual(viewModel.timers.count, 1)
        let survivingTimer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(survivingTimer.status, .running)
        XCTAssertEqual(survivingTimer.name, "3 stops - 8s")
        XCTAssertEqual(survivingTimer.basisSummary, "Base 1s · 3 stops")

        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 4
        viewModel.startTimer()

        XCTAssertEqual(viewModel.timers.count, 2)
        XCTAssertEqual(viewModel.timers.map(\.name), ["4 stops - 1s", "3 stops - 8s"])
        XCTAssertEqual(
            viewModel.timers.map(\.basisSummary),
            ["Base 1/15s · 4 stops", "Base 1s · 3 stops"]
        )
    }

    @MainActor
    func testPauseTimerUpdatesViewModelState() throws {
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
        viewModel.scaleMode = .fullStop

        viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(4)
        viewModel.pauseTimer(id: id)

        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.paused)
        let remainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(remainingTime, 6, accuracy: 0.0001)
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
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let initialTimer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(initialTimer.name, "6 stops - 2s")
        XCTAssertEqual(initialTimer.basisSummary, "Base 1/30s · 6 stops")

        viewModel.baseShutter = 1
        viewModel.ndStop = 3

        let timerAfterInputChange = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timerAfterInputChange.name, "6 stops - 2s")
        XCTAssertEqual(timerAfterInputChange.basisSummary, "Base 1/30s · 6 stops")
    }
}
