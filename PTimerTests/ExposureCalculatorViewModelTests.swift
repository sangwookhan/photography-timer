import Combine
import XCTest
import SwiftUI
import UIKit
@testable import PTimer

final class ExposureCalculatorViewModelTests: XCTestCase {
    func testDockCompactTimeFormatterUsesTopLevelUnitsForLongDurations() {
        XCTAssertEqual(
            DockCompactTimeFormatter.format((3 * 3_600) + (20 * 60)),
            DockCompactTimeDisplay(primaryText: "3h", secondaryText: "20m", accessibilityText: "3h 20m")
        )
        XCTAssertEqual(
            DockCompactTimeFormatter.format((2 * 86_400) + (3 * 3_600)),
            DockCompactTimeDisplay(primaryText: "2d", secondaryText: "3h", accessibilityText: "2d 3h")
        )
        XCTAssertEqual(
            DockCompactTimeFormatter.format((3 * 30 * 86_400) + (12 * 86_400)),
            DockCompactTimeDisplay(primaryText: "3mo", secondaryText: "12d", accessibilityText: "3mo 12d")
        )
        XCTAssertEqual(
            DockCompactTimeFormatter.format((2 * 365 * 86_400) + (23 * 86_400)),
            DockCompactTimeDisplay(primaryText: "2y", secondaryText: "", accessibilityText: "2y")
        )
    }

    func testDockCompactTimeFormatterUsesMinuteSecondBreakdownWithinHour() {
        XCTAssertEqual(
            DockCompactTimeFormatter.format((12 * 60) + 30),
            DockCompactTimeDisplay(primaryText: "12m", secondaryText: "30s", accessibilityText: "12m 30s")
        )
        XCTAssertEqual(
            DockCompactTimeFormatter.format(45),
            DockCompactTimeDisplay(primaryText: "45s", secondaryText: "", accessibilityText: "45s")
        )
    }

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
        XCTAssertEqual(viewModel.formatTimeDisplay(21.158), TimeDisplay(primary: "21.158s", secondary: "21.158s"))
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

        XCTAssertEqual(viewModel.formatTimeDisplay(128.25), TimeDisplay(primary: "02:08.250", secondary: "128.25s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(12.345), TimeDisplay(primary: "12.345s", secondary: "12.345s"))
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
            basisSummary: "Base 1/30s · 6 stops",
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
            basisSummary: "Base 1/30s · 6 stops",
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
            basisSummary: "Base 1/30s · 6 stops",
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

        viewModel.startTimer(from: 120)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let context = try XCTUnwrap(viewModel.timerTimeContext(for: timer))
        XCTAssertEqual(context, "Ends \(viewModel.formatDateTime(try XCTUnwrap(timer.endDate)))")
    }

    @MainActor
    func testStoppedTimerIncludesPausedDateWithFullDateFormat() throws {
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

        viewModel.startTimer(from: 120)
        let id = try XCTUnwrap(viewModel.timers.first?.id)
        currentDate = startDate.addingTimeInterval(10)
        viewModel.stopTimer(id: id)

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

        viewModel.startTimer(from: 2)
        currentDate = startDate.addingTimeInterval(5)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Completed \(viewModel.formatDateTime(try XCTUnwrap(timer.completedAt)))"
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
    func testTimerDisplayHandlesLargeDurationsInReadableFormat() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(
            viewModel.formatTimeDisplay(2_592_000),
            TimeDisplay(primary: "1mo 00:00:00", secondary: "2592000s")
        )
        XCTAssertEqual(
            viewModel.formatTimeDisplay(31_536_000),
            TimeDisplay(primary: "1y 00:00:00", secondary: "31536000s")
        )
    }

    @MainActor
    func testTimerDisplayPrecisionDoesNotShowExcessiveDecimals() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimeDisplay(128).secondary, "128s")
        XCTAssertEqual(viewModel.formatTimeDisplay(21.158).secondary, "21.158s")
        XCTAssertFalse(viewModel.formatTimeDisplay(128).secondary.contains(".000"))
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

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()
        let id = try XCTUnwrap(viewModel.timers.first?.id)
        let originalSummary = viewModel.timers.first?.basisSummary

        currentDate = startDate.addingTimeInterval(1)
        viewModel.stopTimer(id: id)
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

        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        var timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.remainingTime).primary, "8s")

        currentDate = startDate.addingTimeInterval(3)
        viewModel.stopTimer(id: id)
        timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .stopped)
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
        XCTAssertEqual(initialTimer.name, "6 stops - 2s")
        XCTAssertEqual(initialTimer.basisSummary, "Base 1/30s · 6 stops")

        viewModel.baseShutter = 1
        viewModel.ndStop = 3

        let timerAfterInputChange = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timerAfterInputChange.name, "6 stops - 2s")
        XCTAssertEqual(timerAfterInputChange.basisSummary, "Base 1/30s · 6 stops")
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

    @MainActor
    func testTargetDurationNeverChangesAcrossStateTransitions() throws {
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

        let originalDuration = try XCTUnwrap(viewModel.timers.first?.duration)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.stopTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)

        currentDate = startDate.addingTimeInterval(6)
        viewModel.resumeTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)

        currentDate = startDate.addingTimeInterval(15)
        timerManager.tick(now: currentDate)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)
    }

    @MainActor
    func testDisplayDoesNotUseForbiddenCharacters() throws {
        let startDate = Date(timeIntervalSince1970: 100)

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { startDate }
            )
        )

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

    @MainActor
    func testViewModelForwardsRuntimeStoreObjectWillChange() {
        let store = TimerRuntimeStore(
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerRuntimeStore: store
        )
        var changeCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }

        store.startTimer(
            TimerCreationRequest(duration: 8, name: "Timer - 8s", basisSummary: "Manual timer")
        )

        XCTAssertGreaterThanOrEqual(changeCount, 1)
        XCTAssertEqual(viewModel.timers.count, 1)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testStartingTimerTriggersViewModelChangePropagation() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        var changeCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }

        viewModel.startTimer(from: 8)

        XCTAssertGreaterThanOrEqual(changeCount, 1)
        XCTAssertEqual(viewModel.timers.first?.status, .running)
        XCTAssertEqual(try XCTUnwrap(viewModel.timers.first?.remainingTime), 8, accuracy: 0.0001)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testRuntimeTickTriggersViewModelChangePropagationWhileTimerRemainsRunning() throws {
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
        var changeCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }

        viewModel.startTimer(from: 8)
        let countAfterStart = changeCount

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        XCTAssertGreaterThan(changeCount, countAfterStart)
        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.remainingTime, 5, accuracy: 0.0001)
        withExtendedLifetime(cancellable) {}
    }
}

@MainActor
final class TimerRuntimeStoreTests: XCTestCase {
    func testVisibleTimersSortRunningPausedCompleted() {
        let now = Date(timeIntervalSince1970: 100)
        var currentDate = now
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let store = TimerRuntimeStore(timerManager: timerManager)

        store.startTimer(
            TimerCreationRequest(duration: 10, name: "Completed", basisSummary: "Manual timer")
        )
        store.startTimer(
            TimerCreationRequest(duration: 12, name: "Paused", basisSummary: "Manual timer")
        )
        store.startTimer(
            TimerCreationRequest(duration: 14, name: "Running", basisSummary: "Manual timer")
        )

        let completedID = try! XCTUnwrap(store.timers.first(where: { $0.name == "Completed" })?.id)
        let pausedID = try! XCTUnwrap(store.timers.first(where: { $0.name == "Paused" })?.id)

        currentDate = now.addingTimeInterval(3)
        store.stopTimer(id: pausedID)

        currentDate = now.addingTimeInterval(11)
        timerManager.tick(now: currentDate)

        XCTAssertEqual(store.visibleTimers.map(\.name), ["Running", "Paused", "Completed"])
        XCTAssertEqual(store.timers.first(where: { $0.id == completedID })?.status, .completed)
    }

    func testVisibleTimersEmptyWhenNoTimersExist() {
        let store = TimerRuntimeStore(
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertTrue(store.visibleTimers.isEmpty)
    }
}

@MainActor
final class ExposureWorkspaceScreenLayoutTests: XCTestCase {
    func testDockDisplayModeIsResolvedInPresentationLayer() {
        XCTAssertEqual(FloatingTimerDockDisplayMode.resolve(hasVisibleTimers: false), .collapsed)
        XCTAssertEqual(FloatingTimerDockDisplayMode.resolve(hasVisibleTimers: true), .expanded)
    }

    func testWorkspaceRendersCalculatorPanelAndCollapsedDock() {
        let store = TimerRuntimeStore(
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        let screen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: store
            )
        )
        let hostingController = makeHostingController(for: screen)

        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.calculatorPanel", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.collapsed", in: hostingController.view))
        XCTAssertNil(nearestAncestorScrollView(for: try! XCTUnwrap(findView(withAccessibilityIdentifier: "exposure.workspace.calculatorPanel", in: hostingController.view))))
    }

    func testWorkspaceShowsExpandedDockWithIndependentScrollRegion() {
        let store = populatedRuntimeStore()
        let screen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: store
            )
        )
        let hostingController = makeHostingController(for: screen)

        let dockScrollMarker = try! XCTUnwrap(
            findView(withAccessibilityIdentifier: "exposure.workspace.dock.scrollContent", in: hostingController.view)
        )
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.expanded", in: hostingController.view))
        XCTAssertNotNil(nearestAncestorScrollView(for: dockScrollMarker))
        XCTAssertNotNil(findTextLabel(containing: "Add Timer", in: hostingController.view))
        XCTAssertNotNil(findTextLabel(containing: "Timers 2", in: hostingController.view))
    }

    func testWorkspaceDoesNotWrapWholeScreenInPageScrollView() {
        let store = populatedRuntimeStore()
        let screen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: store
            )
        )
        let hostingController = makeHostingController(for: screen)

        let rootView = try! XCTUnwrap(findView(withAccessibilityIdentifier: "exposure.workspace.root", in: hostingController.view))
        let rootScrollAncestor = nearestAncestorScrollView(for: rootView)
        XCTAssertNil(rootScrollAncestor)
    }

    func testNarrowPortraitWorkspaceKeepsDockReadableWithoutBrokenPlaceholderButtons() {
        let store = populatedRuntimeStore()
        let screen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: store
            )
        )
        let hostingController = makeHostingController(
            for: screen,
            size: CGSize(width: 390, height: 844)
        )

        XCTAssertNotNil(findTextLabel(containing: "Exposure", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.expanded", in: hostingController.view))
        XCTAssertNil(findTextLabel(containing: "View All", in: hostingController.view))
        XCTAssertNil(findTextLabel(containing: "Details", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowList", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.0", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.cell.running", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.compactTime", in: hostingController.view))
        XCTAssertNil(findControl(withAccessibilityIdentifier: "exposure.workspace.dock.timerAction.Pause", in: hostingController.view))
    }

    func testExpandedDockUsesPlaceholderLabelForViewAllInsteadOfDisabledButton() {
        let store = populatedRuntimeStore()
        let dock = FloatingTimerDock(
            timers: store.visibleTimers,
            displayMode: .expanded,
            formatTimeDisplay: store.formatTimeDisplay,
            onPauseTimer: { _ in },
            onResumeTimer: { _ in },
            onOpenCompletedTimer: { _ in },
            onViewAll: nil
        )
        let hostingController = makeHostingController(
            for: dock,
            size: CGSize(width: 220, height: 500)
        )

        XCTAssertNotNil(findTextLabel(containing: "View All", in: hostingController.view))
        XCTAssertNil(findButton(titled: "View All", in: hostingController.view))
    }

    func testCompletedTileUsesConsistentPlaceholderInsteadOfDetailsButtonInCompactMode() {
        let completedTimer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Completed",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 8,
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 108),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: Date(timeIntervalSince1970: 120)
        )
        let dock = FloatingTimerDock(
            timers: [completedTimer],
            displayMode: .expanded,
            formatTimeDisplay: { _ in TimeDisplay(primary: "8s", secondary: "8s") },
            onPauseTimer: { _ in },
            onResumeTimer: { _ in },
            onOpenCompletedTimer: { _ in },
            onViewAll: nil
        )
        let hostingController = makeHostingController(
            for: dock,
            size: CGSize(width: 132, height: 420)
        )

        XCTAssertNotNil(findTextLabel(containing: "Done", in: hostingController.view))
        XCTAssertNil(findTextLabel(containing: "Details", in: hostingController.view))
        XCTAssertNil(findButton(titled: "Details", in: hostingController.view))
    }

    func testDockQuickActionsEmitCallbacksWithoutOwningRuntimeMutation() throws {
        let store = populatedRuntimeStore()
        let runningTimer = try XCTUnwrap(store.visibleTimers.first(where: { $0.status == .running }))
        let recorder = DockIntentRecorder()
        let dock = FloatingTimerDock(
            timers: [runningTimer],
            displayMode: .expanded,
            formatTimeDisplay: store.formatTimeDisplay,
            onPauseTimer: { recorder.pauseIDs.append($0) },
            onResumeTimer: { recorder.resumeIDs.append($0) },
            onOpenCompletedTimer: { recorder.openIDs.append($0) },
            onViewAll: nil
        )
        let hostingController = makeHostingController(
            for: dock,
            size: CGSize(width: 220, height: 320)
        )

        let pauseButton = try XCTUnwrap(
            findControl(withAccessibilityIdentifier: "exposure.workspace.dock.timerAction.Pause", in: hostingController.view)
        )
        pauseButton.sendActions(for: .touchUpInside)

        XCTAssertEqual(recorder.pauseIDs, [runningTimer.id])
        XCTAssertTrue(recorder.resumeIDs.isEmpty)
        XCTAssertEqual(store.timers.first(where: { $0.id == runningTimer.id })?.status, .running)
    }

    func testNarrowPortraitKeepsCalculatorWidthStableWhenTimersAppear() {
        let size = CGSize(width: 390, height: 844)
        let collapsedStore = TimerRuntimeStore(
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        let expandedStore = populatedRuntimeStore()

        let collapsedScreen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: collapsedStore
            )
        )
        let expandedScreen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: expandedStore
            )
        )

        let collapsedHost = makeHostingController(for: collapsedScreen, size: size)
        let expandedHost = makeHostingController(for: expandedScreen, size: size)

        let collapsedPanel = try! XCTUnwrap(
            findView(withAccessibilityIdentifier: "exposure.workspace.calculatorPanel", in: collapsedHost.view)
        )
        let expandedPanel = try! XCTUnwrap(
            findView(withAccessibilityIdentifier: "exposure.workspace.calculatorPanel", in: expandedHost.view)
        )

        XCTAssertEqual(collapsedPanel.frame.width, expandedPanel.frame.width, accuracy: 1.0)
    }

    func testNarrowPortraitKeepsShutterAndNDOnSameStructuralRowWhenTimersAppear() {
        let size = CGSize(width: 390, height: 844)
        let collapsedStore = TimerRuntimeStore(
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        let expandedStore = populatedRuntimeStore()

        let collapsedHost = makeHostingController(
            for: ExposureWorkspaceScreen(
                viewModel: ExposureCalculatorViewModel(
                    calculator: ExposureCalculator(),
                    timerRuntimeStore: collapsedStore
                )
            ),
            size: size
        )
        let expandedHost = makeHostingController(
            for: ExposureWorkspaceScreen(
                viewModel: ExposureCalculatorViewModel(
                    calculator: ExposureCalculator(),
                    timerRuntimeStore: expandedStore
                )
            ),
            size: size
        )

        let collapsedShutter = try! XCTUnwrap(findTextLabel(containing: "Shutter", in: collapsedHost.view))
        let collapsedND = try! XCTUnwrap(findTextLabel(containing: "ND", in: collapsedHost.view))
        let expandedShutter = try! XCTUnwrap(findTextLabel(containing: "Shutter", in: expandedHost.view))
        let expandedND = try! XCTUnwrap(findTextLabel(containing: "ND", in: expandedHost.view))

        XCTAssertEqual(collapsedShutter.frame.minY, collapsedND.frame.minY, accuracy: 6.0)
        XCTAssertEqual(expandedShutter.frame.minY, expandedND.frame.minY, accuracy: 6.0)
    }

    func testNarrowPortraitKeepsTimerActionVisibleInsideCalculatorPanel() {
        let screen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: populatedRuntimeStore()
            )
        )
        let hostingController = makeHostingController(
            for: screen,
            size: CGSize(width: 390, height: 844)
        )

        let panel = try! XCTUnwrap(
            findView(withAccessibilityIdentifier: "exposure.workspace.calculatorPanel", in: hostingController.view)
        )
        let timerAction = try! XCTUnwrap(
            findView(withAccessibilityIdentifier: "exposure.workspace.timerAction", in: hostingController.view)
        )

        let timerActionFrame = timerAction.convert(timerAction.bounds, to: hostingController.view)
        let panelFrame = panel.convert(panel.bounds, to: hostingController.view)

        XCTAssertLessThanOrEqual(timerActionFrame.maxY, panelFrame.maxY)
        XCTAssertTrue(panelFrame.intersects(timerActionFrame))
    }

    func testNarrowPortraitDockSurfacesMultipleTimersTruthfully() {
        let size = CGSize(width: 390, height: 844)
        let now = Date(timeIntervalSince1970: 100)
        var currentDate = now
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let store = TimerRuntimeStore(timerManager: timerManager)

        store.startTimer(
            TimerCreationRequest(duration: 200, name: "Long", basisSummary: "Manual timer")
        )
        store.startTimer(
            TimerCreationRequest(duration: 3, name: "Short 1", basisSummary: "Manual timer")
        )
        store.startTimer(
            TimerCreationRequest(duration: 3, name: "Short 2", basisSummary: "Manual timer")
        )

        currentDate = now.addingTimeInterval(5)
        timerManager.tick(now: currentDate)

        let screen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: store
            )
        )
        let hostingController = makeHostingController(for: screen, size: size)

        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowList", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.0", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.1", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.2", in: hostingController.view))
        XCTAssertNil(findTextLabel(containing: "Completed", in: hostingController.view))
    }

    func testNarrowPortraitDockAllowsCompletedTimersToAccumulateInScroll() {
        let size = CGSize(width: 390, height: 844)
        let now = Date(timeIntervalSince1970: 100)
        var currentDate = now
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let store = TimerRuntimeStore(timerManager: timerManager)

        store.startTimer(
            TimerCreationRequest(duration: 200, name: "Long", basisSummary: "Manual timer")
        )
        store.startTimer(
            TimerCreationRequest(duration: 12, name: "Paused", basisSummary: "Manual timer")
        )
        store.startTimer(
            TimerCreationRequest(duration: 3, name: "Done 1", basisSummary: "Manual timer")
        )
        store.startTimer(
            TimerCreationRequest(duration: 3, name: "Done 2", basisSummary: "Manual timer")
        )

        let pausedID = try! XCTUnwrap(store.timers.first(where: { $0.name == "Paused" })?.id)
        currentDate = now.addingTimeInterval(2)
        store.stopTimer(id: pausedID)
        currentDate = now.addingTimeInterval(5)
        timerManager.tick(now: currentDate)

        let screen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: store
            )
        )
        let hostingController = makeHostingController(for: screen, size: size)

        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.scrollView", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.0", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.1", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.2", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.3", in: hostingController.view))
    }

    func testPausedCellUsesFullCellResumeAffordance() throws {
        let pausedTimer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Paused",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 90,
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 190),
            pausedRemainingTime: 65,
            pausedAt: Date(timeIntervalSince1970: 125),
            status: .stopped,
            referenceDate: Date(timeIntervalSince1970: 130)
        )
        let recorder = DockIntentRecorder()
        let dock = FloatingTimerDock(
            timers: [pausedTimer],
            displayMode: .expanded,
            formatTimeDisplay: { _ in TimeDisplay(primary: "dummy", secondary: "dummy") },
            onPauseTimer: { recorder.pauseIDs.append($0) },
            onResumeTimer: { recorder.resumeIDs.append($0) },
            onOpenCompletedTimer: { recorder.openIDs.append($0) },
            onViewAll: nil
        )
        let hostingController = makeHostingController(for: dock, size: CGSize(width: 86, height: 180))

        let resumeControl = try XCTUnwrap(
            findControl(withAccessibilityIdentifier: "exposure.workspace.dock.pausedResume", in: hostingController.view)
        )
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.pausedOverlay", in: hostingController.view))
        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.cell.paused", in: hostingController.view))

        resumeControl.sendActions(for: .touchUpInside)
        XCTAssertEqual(recorder.resumeIDs, [pausedTimer.id])
    }

    func testCompletedCellStaysQuietWithoutInlineActionControls() {
        let completedTimer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Completed",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 8,
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 108),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: Date(timeIntervalSince1970: 120)
        )
        let dock = FloatingTimerDock(
            timers: [completedTimer],
            displayMode: .expanded,
            formatTimeDisplay: { _ in TimeDisplay(primary: "dummy", secondary: "dummy") },
            onPauseTimer: { _ in },
            onResumeTimer: { _ in },
            onOpenCompletedTimer: { _ in },
            onViewAll: nil
        )
        let hostingController = makeHostingController(for: dock, size: CGSize(width: 86, height: 180))

        XCTAssertNotNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.cell.completed", in: hostingController.view))
        XCTAssertNil(findControl(withAccessibilityIdentifier: "exposure.workspace.dock.pausedResume", in: hostingController.view))
        XCTAssertNil(findView(withAccessibilityIdentifier: "exposure.workspace.dock.pausedOverlay", in: hostingController.view))
        XCTAssertNil(findControl(withAccessibilityIdentifier: "exposure.workspace.dock.timerAction.Pause", in: hostingController.view))
        XCTAssertNil(findControl(withAccessibilityIdentifier: "exposure.workspace.dock.timerAction.Resume", in: hostingController.view))
    }

    func testNarrowPortraitDockWidthRemainsAggressivelyBounded() {
        let screen = ExposureWorkspaceScreen(
            viewModel: ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: populatedRuntimeStore()
            )
        )
        let hostingController = makeHostingController(
            for: screen,
            size: CGSize(width: 390, height: 844)
        )

        let dock = try! XCTUnwrap(
            findView(withAccessibilityIdentifier: "exposure.workspace.dock", in: hostingController.view)
        )

        XCTAssertLessThanOrEqual(dock.frame.width, 90)
    }

    func testCompactDockRowHeightRemainsStableAcrossDisplayThresholds() {
        let longTimer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Long",
            basisSummary: "Base 1/30s · 10 stops",
            duration: 12_000,
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 12_100),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: Date(timeIntervalSince1970: 100)
        )
        let shortTimer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Short",
            basisSummary: "Base 1/30s · 10 stops",
            duration: 45,
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 145),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: Date(timeIntervalSince1970: 100)
        )

        let longDock = FloatingTimerDock(
            timers: [longTimer],
            displayMode: .expanded,
            formatTimeDisplay: { _ in TimeDisplay(primary: "dummy", secondary: "dummy") },
            onPauseTimer: { _ in },
            onResumeTimer: { _ in },
            onOpenCompletedTimer: { _ in },
            onViewAll: nil
        )
        let shortDock = FloatingTimerDock(
            timers: [shortTimer],
            displayMode: .expanded,
            formatTimeDisplay: { _ in TimeDisplay(primary: "dummy", secondary: "dummy") },
            onPauseTimer: { _ in },
            onResumeTimer: { _ in },
            onOpenCompletedTimer: { _ in },
            onViewAll: nil
        )

        let longHost = makeHostingController(for: longDock, size: CGSize(width: 86, height: 180))
        let shortHost = makeHostingController(for: shortDock, size: CGSize(width: 86, height: 180))

        let longRow = try! XCTUnwrap(
            findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.0", in: longHost.view)
        )
        let shortRow = try! XCTUnwrap(
            findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.0", in: shortHost.view)
        )

        XCTAssertEqual(longRow.frame.height, shortRow.frame.height, accuracy: 1.0)
    }

    func testCompactDockRowHeightRemainsStableAcrossStatuses() {
        let baseDate = Date(timeIntervalSince1970: 100)
        let runningTimer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Running",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 200,
            startDate: baseDate,
            endDate: baseDate.addingTimeInterval(200),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: baseDate
        )
        let pausedTimer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Paused",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 200,
            startDate: baseDate,
            endDate: baseDate.addingTimeInterval(200),
            pausedRemainingTime: 120,
            pausedAt: baseDate.addingTimeInterval(80),
            status: .stopped,
            referenceDate: baseDate.addingTimeInterval(80)
        )
        let completedTimer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Completed",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 8,
            startDate: baseDate,
            endDate: baseDate.addingTimeInterval(8),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: baseDate.addingTimeInterval(10)
        )

        let runningHost = makeHostingController(
            for: FloatingTimerDock(
                timers: [runningTimer],
                displayMode: .expanded,
                formatTimeDisplay: { _ in TimeDisplay(primary: "dummy", secondary: "dummy") },
                onPauseTimer: { _ in },
                onResumeTimer: { _ in },
                onOpenCompletedTimer: { _ in },
                onViewAll: nil
            ),
            size: CGSize(width: 86, height: 180)
        )
        let pausedHost = makeHostingController(
            for: FloatingTimerDock(
                timers: [pausedTimer],
                displayMode: .expanded,
                formatTimeDisplay: { _ in TimeDisplay(primary: "dummy", secondary: "dummy") },
                onPauseTimer: { _ in },
                onResumeTimer: { _ in },
                onOpenCompletedTimer: { _ in },
                onViewAll: nil
            ),
            size: CGSize(width: 86, height: 180)
        )
        let completedHost = makeHostingController(
            for: FloatingTimerDock(
                timers: [completedTimer],
                displayMode: .expanded,
                formatTimeDisplay: { _ in TimeDisplay(primary: "dummy", secondary: "dummy") },
                onPauseTimer: { _ in },
                onResumeTimer: { _ in },
                onOpenCompletedTimer: { _ in },
                onViewAll: nil
            ),
            size: CGSize(width: 86, height: 180)
        )

        let runningRow = try! XCTUnwrap(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.0", in: runningHost.view))
        let pausedRow = try! XCTUnwrap(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.0", in: pausedHost.view))
        let completedRow = try! XCTUnwrap(findView(withAccessibilityIdentifier: "exposure.workspace.dock.narrowRow.0", in: completedHost.view))

        XCTAssertEqual(runningRow.frame.height, pausedRow.frame.height, accuracy: 1.0)
        XCTAssertEqual(pausedRow.frame.height, completedRow.frame.height, accuracy: 1.0)
    }

    private func populatedRuntimeStore() -> TimerRuntimeStore {
        let store = TimerRuntimeStore(
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        store.startTimer(
            TimerCreationRequest(duration: 2, name: "Cam A", basisSummary: "Base 1/30s · 6 stops")
        )
        store.startTimer(
            TimerCreationRequest(duration: 8, name: "Cam B", basisSummary: "Base 1/15s · 8 stops")
        )
        return store
    }

    private func makeHostingController(
        for screen: some View,
        size: CGSize = CGSize(width: 900, height: 700)
    ) -> UIHostingController<some View> {
        let hostingController = UIHostingController(rootView: screen.frame(width: size.width, height: size.height))
        hostingController.loadViewIfNeeded()
        hostingController.view.frame = CGRect(origin: .zero, size: size)
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        return hostingController
    }

    private func findView(withAccessibilityIdentifier identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier {
            return view
        }

        for subview in view.subviews {
            if let match = findView(withAccessibilityIdentifier: identifier, in: subview) {
                return match
            }
        }

        return nil
    }

    private func findControl(withAccessibilityIdentifier identifier: String, in view: UIView) -> UIControl? {
        if let control = view as? UIControl, control.accessibilityIdentifier == identifier {
            return control
        }

        for subview in view.subviews {
            if let match = findControl(withAccessibilityIdentifier: identifier, in: subview) {
                return match
            }
        }

        return nil
    }

    private func findButton(titled title: String, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.currentTitle?.contains(title) == true {
            return button
        }

        for subview in view.subviews {
            if let match = findButton(titled: title, in: subview) {
                return match
            }
        }

        return nil
    }

    private func nearestAncestorScrollView(for view: UIView) -> UIScrollView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            ancestor = current.superview
        }
        return nil
    }

    private func findTextLabel(containing text: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.text?.contains(text) == true {
            return label
        }

        for subview in view.subviews {
            if let match = findTextLabel(containing: text, in: subview) {
                return match
            }
        }

        return nil
    }
}

@MainActor
private final class DockIntentRecorder {
    var pauseIDs: [UUID] = []
    var resumeIDs: [UUID] = []
    var openIDs: [UUID] = []
}
