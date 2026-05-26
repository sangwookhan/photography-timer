import XCTest
@testable import PTimer

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
        // Tri-X 400's free log-log formula fit lands at 2.014 s at
        // Tm = 1 s (within ~1/100 stop of Kodak's published 2 s row);
        // the duration formatter renders that as "2.0s".
        XCTAssertEqual(timer.duration, 2, accuracy: 0.05)
        XCTAssertEqual(timer.name, "Tri-X 400 - 2.0s")
        XCTAssertEqual(
            timer.basisSummary,
            "Base 1s · 0 stops · Adjusted 1s · Tri-X 400 · Corrected 2.0s"
        )
    }

    @MainActor
    func testFilmModeAdjustedShutterTimerStartsFromAdjustedValueWhenCorrectedIsQuantified() throws {
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

        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)

        viewModel.startFilmAdjustedShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 1, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "0 stops - 1s")
        XCTAssertEqual(
            timer.basisSummary,
            "Base 1s · 0 stops · Adjusted 1s · Tri-X 400"
        )
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
    func testFilmModeAdjustedShutterTimerStartsForLimitedGuidanceResult() throws {
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

        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)

        viewModel.startFilmAdjustedShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 15, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "0 stops - 15s")
        XCTAssertEqual(timer.basisSummary, "Base 15s · 0 stops · Adjusted 15s · Portra 400")
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
    func testFilmModeAdjustedShutterTimerStartsForUnsupportedResult() throws {
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

        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)

        viewModel.startFilmAdjustedShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 64, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "3 stops - 64s")
        XCTAssertEqual(timer.basisSummary, "Base 8s · 3 stops · Adjusted 64s · Velvia 50")
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
