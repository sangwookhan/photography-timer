import XCTest
@testable import PTimer
import PTimerCore
import PTimerKit

final class CalculatorTimerDisplaySemanticsTests: XCTestCase {
    @MainActor
    func testPausedTimerRemainingTimeStaysStableInViewModel() throws {
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

        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)

        let pausedRemainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.paused)
        XCTAssertEqual(pausedRemainingTime, 5, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(12)
        timerManager.tick(now: currentDate)

        let stableRemainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.paused)
        XCTAssertEqual(stableRemainingTime, 5, accuracy: 0.0001)
    }

    @MainActor
    func testPausedTimerDisplaySemanticsPreservePauseMetadataAndRemainResumable() throws {
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
        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .paused)
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
        viewModel.scaleMode = .fullStop

        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)

        XCTAssertEqual(viewModel.timers.first?.status, .paused)
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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
            "Completed \(viewModel.formatDateTime(try XCTUnwrap(timer.completedAt))) · just now"
        )
    }

    @MainActor
    func testRunningTimerPrimaryIsRemainingSecondaryIsExactSeconds() throws {
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

        viewModel.startTimer(from: 90)
        currentDate = startDate.addingTimeInterval(8)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let display = viewModel.formatTimeDisplay(timer.remainingTime)
        XCTAssertEqual(display.primary, "01:22")
        XCTAssertEqual(display.secondary, "82s")
    }

    @MainActor
    func testCompletedTimerDisplaysOriginalDurationNotZero() throws {
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

        viewModel.startTimer(from: 90)

        currentDate = startDate.addingTimeInterval(120)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let display = viewModel.formatTimeDisplay(timer.duration)
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(display.primary, "01:30")
        XCTAssertNotEqual(display.primary, "0s")
    }

    @MainActor
    func testRunningTimerIncludesEndDateWithFullDateFormat() throws {
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

        viewModel.startTimer(from: 120)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let context = try XCTUnwrap(viewModel.timerTimeContext(for: timer))
        XCTAssertEqual(context, "Ends \(viewModel.formatDateTime(try XCTUnwrap(timer.endDate)))")
    }

    @MainActor
    func testPausedTimerIncludesPausedDateWithFullDateFormat() throws {
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

        viewModel.startTimer(from: 120)
        let id = try XCTUnwrap(viewModel.timers.first?.id)
        currentDate = startDate.addingTimeInterval(10)
        viewModel.pauseTimer(id: id)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Paused \(viewModel.formatDateTime(try XCTUnwrap(timer.pausedAt)))"
        )
    }

    @MainActor
    func testCompletedTimerIncludesCompletedDateWithFullDateFormat() throws {
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

        viewModel.startTimer(from: 2)
        currentDate = startDate.addingTimeInterval(5)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Completed \(viewModel.formatDateTime(try XCTUnwrap(timer.completedAt))) · just now"
        )
    }

    @MainActor
    func testTimerDisplayDoesNotDuplicateInformation() throws {
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
        viewModel.ndStop = 10
        viewModel.startTimer()

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let primary = viewModel.formatTimeDisplay(timer.remainingTime)
        let targetContext = try XCTUnwrap(viewModel.timerTargetContext(for: timer))
        let timeContext = try XCTUnwrap(viewModel.timerTimeContext(for: timer))

        XCTAssertFalse(targetContext.contains("Ends "))
        XCTAssertFalse(timeContext.contains(timer.basisSummary))
        XCTAssertFalse(targetContext.contains("Base "))
        XCTAssertFalse(targetContext.contains("ND "))
        XCTAssertFalse(timeContext.contains(primary.primary))
        XCTAssertFalse(timeContext.contains(primary.secondary))
    }

    @MainActor
    func testBasisSummaryRemainsStableAcrossStateChanges() throws {
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
        let id = try XCTUnwrap(viewModel.timers.first?.id)
        let originalSummary = viewModel.timers.first?.basisSummary

        currentDate = startDate.addingTimeInterval(1)
        viewModel.pauseTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.basisSummary, originalSummary)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.resumeTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.basisSummary, originalSummary)
    }

    @MainActor
    func testTimerStateTransitionDoesNotCorruptDisplayModel() throws {
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

        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        var timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.remainingTime).primary, "8s")

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)
        timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .paused)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.remainingTime).primary, "5s")

        currentDate = startDate.addingTimeInterval(5)
        viewModel.resumeTimer(id: id)
        timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.remainingTime).primary, "5s")

        currentDate = startDate.addingTimeInterval(11)
        timerManager.tick(now: currentDate)
        timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.duration).primary, "8s")
    }
}
