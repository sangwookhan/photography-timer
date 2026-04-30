import XCTest
@testable import PTimer

final class ExposureCalculatorViewModelTimerIntegrationTests: XCTestCase {
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
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)
        viewModel.startFilmCorrectedExposureTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 1, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "Tri-X 400 - 1s")
        XCTAssertEqual(
            timer.basisSummary,
            "Base 1s · 0 stops · Adjusted 1s · Tri-X 400 · Corrected 1s"
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
    func testFilmModeAdvisoryOnlyDoesNotProvideCorrectedExposureTimerSource() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)

        viewModel.startFilmCorrectedExposureTimer()

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertEqual(viewModel.filmModeExposureResultState?.correctedExposure.kind, .advisory)
    }

    @MainActor
    func testFilmModeAdjustedShutterTimerStartsForAdvisoryOnlyResult() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
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
    func testFilmModeUnsupportedDoesNotProvideCorrectedExposureTimerSource() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)

        viewModel.startFilmCorrectedExposureTimer()

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertEqual(viewModel.filmModeExposureResultState?.correctedExposure.kind, .unsupported)
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

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "6 stops - 2s")
        XCTAssertEqual(timer.basisSummary, "Base 1/30s · 6 stops")
    }

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

        viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(4)
        viewModel.pauseTimer(id: id)

        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.paused)
        let remainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(remainingTime, 6, accuracy: 0.0001)
    }

    @MainActor
    func testRunningTimerExposesLockScreenTargetUsingTimerEndDate() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 10)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(exposer.exposedTargets, [
            LockScreenTimerTarget(
                representativeTimerID: timer.id,
                representativeTimerName: timer.name,
                representativeEndDate: try XCTUnwrap(timer.endDate),
                scheduledTargets: [
                    LockScreenTimerScheduledTarget(
                        timerID: timer.id,
                        timerName: timer.name,
                        endDate: try XCTUnwrap(timer.endDate)
                    )
                ]
            )
        ])
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, timer.endDate)
        XCTAssertEqual(exposer.clearCount, 0)
    }

    @MainActor
    func testLockScreenTargetSelectionUsesEarliestRunningTimerEndDate() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 20)
        let longerRunning = try XCTUnwrap(viewModel.timers.first)
        viewModel.startTimer(from: 12)
        let shorterRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 12 }))

        XCTAssertNotEqual(viewModel.timers.first?.id, longerRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, shorterRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, shorterRunning.endDate)
        XCTAssertEqual(exposer.currentTarget?.scheduledTargets.map(\.timerID), [shorterRunning.id, longerRunning.id])
    }

    @MainActor
    func testLockScreenTargetSelectionUsesPresentationOrderWhenEarliestEndDateIsTied() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 30)
        let olderRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 30 }))

        currentDate = startDate.addingTimeInterval(10)
        viewModel.startTimer(from: 20)
        let newerRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 20 }))

        XCTAssertEqual(olderRunning.endDate, newerRunning.endDate)
        XCTAssertEqual(viewModel.timers.first?.id, newerRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, newerRunning.id)
    }

    @MainActor
    func testLockScreenTargetSelectionUsesStableIDOrderWhenEndDateAndPresentationOrderAreTied() {
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let sharedEndDate = Date(timeIntervalSince1970: 500)
        let referenceDate = Date(timeIntervalSince1970: 100)

        let laterIDTimer = RunningTimerItem(
            id: laterID,
            order: 7,
            name: "Later ID",
            basisSummary: "Manual timer",
            duration: 30,
            startDate: Date(timeIntervalSince1970: 470),
            endDate: sharedEndDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: referenceDate
        )

        let earlierIDTimer = RunningTimerItem(
            id: earlierID,
            order: 7,
            name: "Earlier ID",
            basisSummary: "Manual timer",
            duration: 30,
            startDate: Date(timeIntervalSince1970: 470),
            endDate: sharedEndDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: referenceDate
        )

        let target = LockScreenTimerTargetCoordinator.selectRepresentativeTarget(
            from: [laterIDTimer, earlierIDTimer]
        )

        XCTAssertEqual(target?.representativeTimerID, earlierID)
        XCTAssertEqual(target?.representativeEndDate, sharedEndDate)
    }

    @MainActor
    func testPausedTimerIsNotRepresentativeAndFallsBackToNextEarliestRunningTimer() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 20)
        let fallbackRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 20 }))
        viewModel.startTimer(from: 12)
        let selectedRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 12 }))

        currentDate = startDate.addingTimeInterval(5)
        viewModel.pauseTimer(id: selectedRunning.id)

        XCTAssertEqual(viewModel.timers.first(where: { $0.id == selectedRunning.id })?.status, .paused)
        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, fallbackRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, fallbackRunning.endDate)
    }

    @MainActor
    func testPausedAndCompletedTimersAreIgnoredByEarliestEndDateRepresentativeSelection() {
        let sharedReferenceDate = Date(timeIntervalSince1970: 100)
        let runningTimer = RunningTimerItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            order: 3,
            name: "Running",
            basisSummary: "Manual timer",
            duration: 15,
            startDate: Date(timeIntervalSince1970: 95),
            endDate: Date(timeIntervalSince1970: 110),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: sharedReferenceDate
        )

        let pausedTimer = RunningTimerItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            order: 4,
            name: "Paused",
            basisSummary: "Manual timer",
            duration: 3,
            startDate: Date(timeIntervalSince1970: 99),
            endDate: Date(timeIntervalSince1970: 102),
            pausedRemainingTime: 2,
            pausedAt: Date(timeIntervalSince1970: 100),
            status: .paused,
            referenceDate: sharedReferenceDate
        )

        let completedTimer = RunningTimerItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            order: 5,
            name: "Completed",
            basisSummary: "Manual timer",
            duration: 2,
            startDate: Date(timeIntervalSince1970: 98),
            endDate: Date(timeIntervalSince1970: 101),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: sharedReferenceDate
        )

        let target = LockScreenTimerTargetCoordinator.selectRepresentativeTarget(
            from: [pausedTimer, completedTimer, runningTimer]
        )

        XCTAssertEqual(target?.representativeTimerID, runningTimer.id)
        XCTAssertEqual(target?.representativeEndDate, runningTimer.endDate)
    }

    @MainActor
    func testLockScreenScheduledTargetsCanHandOffToNextTimerWithoutAppStateRefresh() {
        let state = TimerTargetLiveActivityAttributes.ContentState(
            representativeTimerName: "30s timer",
            representativeEndDate: Date(timeIntervalSince1970: 130),
            scheduledTargets: [
                LockScreenTimerScheduledTarget(
                    timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
                    timerName: "30s timer",
                    endDate: Date(timeIntervalSince1970: 130)
                ),
                LockScreenTimerScheduledTarget(
                    timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
                    timerName: "2m timer",
                    endDate: Date(timeIntervalSince1970: 220)
                )
            ]
        )

        XCTAssertEqual(state.displayTarget(at: Date(timeIntervalSince1970: 120))?.timerName, "30s timer")
        XCTAssertEqual(state.displayTarget(at: Date(timeIntervalSince1970: 131))?.timerName, "2m timer")
    }

    @MainActor
    func testCompletedTimerIsNotRepresentativeCandidateAndClearsWhenNoRunningTimerRemains() {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 2)

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        XCTAssertNil(exposer.currentTarget)
        XCTAssertEqual(exposer.clearCount, 1)
    }

    @MainActor
    func testCompletingRepresentativeTimerHandsOffToNextEarliestRunningTimer() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 10)
        let fallbackRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 10 }))
        viewModel.startTimer(from: 2)
        _ = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 2 }))

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, fallbackRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, fallbackRunning.endDate)
        XCTAssertEqual(exposer.currentTarget?.scheduledTargets.map(\.timerID), [fallbackRunning.id])
    }

    @MainActor
    func testRemovingRepresentativeTimerHandsOffToNextEarliestRunningTimer() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 15)
        let fallbackRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 15 }))
        viewModel.startTimer(from: 8)
        let selectedRunningID = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 8 })?.id)

        viewModel.removeTimer(id: selectedRunningID)

        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, fallbackRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, fallbackRunning.endDate)
    }

    @MainActor
    func testResumeRecalculatesEndDateAndReselectsEarliestRunningRepresentative() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 20)
        let longRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 20 }))
        viewModel.startTimer(from: 8)
        let resumableID = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 8 })?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: resumableID)

        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, longRunning.id)

        currentDate = startDate.addingTimeInterval(10)
        viewModel.resumeTimer(id: resumableID)

        let resumed = try XCTUnwrap(viewModel.timers.first(where: { $0.id == resumableID }))
        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.endDate, currentDate.addingTimeInterval(5))
        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, resumed.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, resumed.endDate)
        XCTAssertLessThan(try XCTUnwrap(resumed.endDate), try XCTUnwrap(longRunning.endDate))
    }

    @MainActor
    func testNoRunningTimerClearsStaleLockScreenTargetExposure() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 6)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(2)
        viewModel.pauseTimer(id: id)

        XCTAssertNil(exposer.currentTarget)
        XCTAssertEqual(exposer.clearCount, 1)
    }

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
    func testStartTimerUsesLivePreviewCalculationWhenPresent() throws {
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

@MainActor
private final class LockScreenTimerTargetExposerSpy: LockScreenTimerTargetExposing {
    private(set) var exposedTargets: [LockScreenTimerTarget] = []
    private(set) var clearCount = 0
    private(set) var currentTarget: LockScreenTimerTarget?

    func expose(_ target: LockScreenTimerTarget) {
        currentTarget = target
        exposedTargets.append(target)
    }

    func clear() {
        currentTarget = nil
        clearCount += 1
    }
}
