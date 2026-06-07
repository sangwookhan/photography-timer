import XCTest
import PTimerCore
@testable import PTimer

final class ExposureCalculatorViewModelTests: XCTestCase {
    @MainActor
    func testCoarseLongDurationFormatterSuppressesSubdayNoiseForDayScaleValues() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        viewModel.scaleMode = .fullStop

        // Threshold: exactly 1 day still reads as raw "Nd"
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(86_400), "1d")

        // Below 1 day — delegates to fine formatter (no regression)
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(86_399), "23:59:59")
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(3_600), "01:00:00")
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(64), "01:04")
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(5.41), "5.4s")

        // 1 d–29 d → raw days
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(522_484.861), "6d")

        // 30 d+ coarsens into months / years so the user never sees
        // five- or six-digit day strings like "83,602d".
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(33_554_432), "≈1y")
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(24_099_248), "≈9mo 8d")
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(7_223_245_206), "≈229y")
        XCTAssertEqual(viewModel.formatReciprocityDurationCoarse(50_802_298_894), "≈1610y")
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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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

        let paused = RunningTimerItem(
            id: UUID(),
            order: 2,
            name: "Timer 2",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 120,
            startDate: Date(timeIntervalSince1970: 8_820),
            endDate: nil,
            pausedRemainingTime: 45,
            pausedAt: pausedDate,
            status: .paused,
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
        XCTAssertEqual(viewModel.timerTimeContext(for: paused), "Paused \(viewModel.formatDateTime(pausedDate))")
        XCTAssertEqual(
            viewModel.timerTimeContext(for: completed),
            "Completed \(viewModel.formatDateTime(pausedDate)) · just now"
        )
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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

        XCTAssertEqual(viewModel.formatTimeDisplay(128).secondary, "128s")
        XCTAssertEqual(viewModel.formatTimeDisplay(21.158).secondary, "21.158s")
        XCTAssertFalse(viewModel.formatTimeDisplay(128).secondary.contains(".000"))
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
        viewModel.scaleMode = .fullStop

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
    func testLiveNDStopPreviewFeedsCalculationBeforeSettledSelection() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveNDStop(10)

        guard case .success(let result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result for live 10-stop preview")
        }

        XCTAssertEqual(result.stop, 10)
        XCTAssertEqual(result.resultShutterSeconds, 30, accuracy: 0.0001)
    }

    @MainActor
    func testLiveBaseShutterPreviewFeedsCalculationBeforeSettledSelection() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveBaseShutter(1.0 / 15.0)

        guard case .success(let result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result for live 1/15s preview")
        }

        XCTAssertEqual(result.baseShutterSeconds, 1.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(result.stop, 6)
        XCTAssertEqual(result.resultShutterSeconds, 4, accuracy: 0.0001)
    }

    @MainActor
    func testSettledNDStopClearsMatchingLivePreview() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveNDStop(10)
        viewModel.ndStop = 10

        guard case .success(let result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result after settled 10-stop selection")
        }

        XCTAssertEqual(result.stop, 10)
        XCTAssertEqual(result.resultShutterSeconds, 30, accuracy: 0.0001)

        viewModel.clearLiveNDStopPreview()

        guard case .success(let settledResult) = viewModel.calculationResult else {
            return XCTFail("Expected valid result after live preview reset")
        }

        XCTAssertEqual(settledResult.stop, 10)
        XCTAssertEqual(settledResult.resultShutterSeconds, 30, accuracy: 0.0001)
    }

    @MainActor
    func testSettledBaseShutterClearsMatchingLivePreview() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveBaseShutter(1.0 / 15.0)
        viewModel.baseShutter = 1.0 / 15.0

        guard case .success(let result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result after settled 1/15s selection")
        }

        XCTAssertEqual(result.baseShutterSeconds, 1.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(result.stop, 6)
        XCTAssertEqual(result.resultShutterSeconds, 4, accuracy: 0.0001)

        viewModel.clearLiveBaseShutterPreview()

        guard case .success(let settledResult) = viewModel.calculationResult else {
            return XCTFail("Expected valid result after live base shutter reset")
        }

        XCTAssertEqual(settledResult.baseShutterSeconds, 1.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(settledResult.stop, 6)
        XCTAssertEqual(settledResult.resultShutterSeconds, 4, accuracy: 0.0001)
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
