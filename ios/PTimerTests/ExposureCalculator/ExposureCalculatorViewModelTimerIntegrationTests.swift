import XCTest
@testable import PTimer
import PTimerKit

final class CalculatorTimerIntegrationTests: XCTestCase {
    @MainActor
    func testFilmModeCorrectedExposureTimerUsesQuantifiedCorrectedResult() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        viewModel.scaleMode = .fullStop
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)
        viewModel.startFilmCorrectedExposureTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        // PTIMER-168: Tri-X 400's official table reproduces Kodak's
        // published 1 s → 2 s anchor exactly; the duration formatter
        // renders the whole-second value as "2s".
        XCTAssertEqual(timer.duration, 2, accuracy: 1e-4)
        XCTAssertEqual(timer.name, "Tri-X 400 - 2s")
        XCTAssertEqual(
            timer.basisSummary,
            "Base 1s · 0 stops · Adjusted 1s · Tri-X 400 · Corrected 2s"
        )
    }

    @MainActor
    func testFilmModeAdjustedShutterTimerStartsFromAdjustedValueAcrossResultKinds() throws {
        // Merged from three structurally identical adjusted-shutter timer
        // tests (PTIMER-174): the adjusted-shutter affordance must enable
        // and stamp the timer with the adjusted value regardless of the
        // corrected-exposure result kind — quantified (Tri-X 400),
        // limited guidance (Portra 400), or unsupported/beyond-source
        // (Velvia 50). Each case carries the union of the original
        // assertions: canStart, duration, name, basisSummary.
        struct Case {
            let stockName: String
            let baseShutter: Double
            let ndStop: Int
            let duration: Double
            let name: String
            let basisSummary: String
        }
        let cases: [Case] = [
            Case(
                stockName: "Tri-X 400",
                baseShutter: 1,
                ndStop: 0,
                duration: 1,
                name: "0 stops - 1s",
                basisSummary: "Base 1s · 0 stops · Adjusted 1s · Tri-X 400"
            ),
            Case(
                stockName: "Portra 400",
                baseShutter: 15,
                ndStop: 0,
                duration: 15,
                name: "0 stops - 15s",
                basisSummary: "Base 15s · 0 stops · Adjusted 15s · Portra 400"
            ),
            Case(
                stockName: "Velvia 50",
                baseShutter: 8,
                ndStop: 3,
                duration: 64,
                name: "3 stops - 64s",
                basisSummary: "Base 8s · 3 stops · Adjusted 64s · Velvia 50"
            ),
        ]

        for testCase in cases {
            let timerManager = TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
            let viewModel = ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerManager: timerManager
            )
            viewModel.scaleMode = .fullStop
            let film = try XCTUnwrap(
                viewModel.availablePresetFilms.first { $0.canonicalStockName == testCase.stockName },
                "[\(testCase.stockName)] Missing preset film."
            )

            viewModel.baseShutter = testCase.baseShutter
            viewModel.ndStop = testCase.ndStop
            viewModel.selectPresetFilm(film)

            XCTAssertTrue(
                viewModel.canStartFilmAdjustedShutterTimer,
                "[\(testCase.stockName)] Adjusted-shutter timer must be startable."
            )

            viewModel.startFilmAdjustedShutterTimer()

            let timer = try XCTUnwrap(viewModel.timers.first, "[\(testCase.stockName)] Missing started timer.")
            XCTAssertEqual(timer.duration, testCase.duration, accuracy: 0.0001, "[\(testCase.stockName)] duration mismatch.")
            XCTAssertEqual(timer.name, testCase.name, "[\(testCase.stockName)] name mismatch.")
            XCTAssertEqual(timer.basisSummary, testCase.basisSummary, "[\(testCase.stockName)] basisSummary mismatch.")
        }
    }

    @MainActor
    func testFilmModeLimitedGuidanceDoesNotProvideCorrectedExposureTimerSource() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        viewModel.scaleMode = .fullStop
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)

        viewModel.startFilmCorrectedExposureTimer()

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertEqual(viewModel.filmModeExposureResultState?.correctedExposure.kind, .limitedGuidance)
    }

    @MainActor
    func testFilmModeBeyondVelvia50SourceRangeStartsCorrectedExposureTimerFromFormulaPrediction() throws {
        // Velvia 50's source-backed range ends at the 32 s anchor;
        // the 64 s row is a published "Not recommended" warning
        // marker only. At adjusted shutter 64 s the result is
        // beyond-source-with-numeric — the formula keeps producing
        // a corrected exposure, so the corrected-exposure timer
        // affordance enables and stamps the timer with the
        // formula-predicted duration.
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        viewModel.scaleMode = .fullStop
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        let expectedCorrected = pow(64.0, 1.1821)
        XCTAssertNotNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, expectedCorrected, accuracy: 0.5)
        XCTAssertTrue(viewModel.canStartFilmCorrectedExposureTimer)

        viewModel.startFilmCorrectedExposureTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, expectedCorrected, accuracy: 0.5)
        XCTAssertEqual(viewModel.filmModeExposureResultState?.correctedExposure.kind, .quantified)
    }

    @MainActor
    func testDigitalModeStartTimerBehaviorRemainsUnchanged() throws {
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

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "6 stops - 2s")
        XCTAssertEqual(timer.basisSummary, "Base 1/30s · 6 stops")
    }

    // MARK: - Live preview + target duration stability

    @MainActor
    func testStartTimerUsesLivePreviewCalculationWhenPresent() throws {
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
        viewModel.updateLiveNDStop(10)
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.name, "10 stops - 30s")
        XCTAssertEqual(timer.basisSummary, "Base 1/30s · 10 stops")
        XCTAssertEqual(timer.duration, 30, accuracy: 0.0001)
    }

    @MainActor
    func testStartTimerUsesLiveBaseShutterPreviewCalculationWhenPresent() throws {
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
        viewModel.updateLiveBaseShutter(1.0 / 15.0)
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.name, "6 stops - 4s")
        XCTAssertEqual(timer.basisSummary, "Base 1/15s · 6 stops")
        XCTAssertEqual(timer.duration, 4, accuracy: 0.0001)
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
        viewModel.scaleMode = .fullStop

        viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        let originalDuration = try XCTUnwrap(viewModel.timers.first?.duration)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)

        currentDate = startDate.addingTimeInterval(6)
        viewModel.resumeTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)

        currentDate = startDate.addingTimeInterval(15)
        timerManager.tick(now: currentDate)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)
    }
}
