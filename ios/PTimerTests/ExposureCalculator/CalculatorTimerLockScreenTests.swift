import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

final class CalculatorTimerLockScreenTests: XCTestCase {
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
        viewModel.scaleMode = .fullStop

        viewModel.startTimer(from: 10)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(exposer.exposedTargets, [
            LockScreenTimerTarget(
                representativeTimerID: timer.id,
                representativeTimerName: timer.name,
                representativeEndDate: try XCTUnwrap(timer.endDate),
                scheduledTargets: [
                    ScheduledTimerTarget(
                        timerID: timer.id,
                        timerName: timer.name,
                        endDate: try XCTUnwrap(timer.endDate)
                    ),
                ]
            ),
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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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

        let target = LockScreenTimerCoordinator.selectRepresentativeTarget(
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
        viewModel.scaleMode = .fullStop

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

        let target = LockScreenTimerCoordinator.selectRepresentativeTarget(
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
                ScheduledTimerTarget(
                    timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
                    timerName: "30s timer",
                    endDate: Date(timeIntervalSince1970: 130)
                ),
                ScheduledTimerTarget(
                    timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
                    timerName: "2m timer",
                    endDate: Date(timeIntervalSince1970: 220)
                ),
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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

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
        viewModel.scaleMode = .fullStop

        viewModel.startTimer(from: 6)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(2)
        viewModel.pauseTimer(id: id)

        XCTAssertNil(exposer.currentTarget)
        XCTAssertEqual(exposer.clearCount, 1)
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
