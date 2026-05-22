import XCTest
@testable import PTimer

/// Direct tests for `LockScreenTimerCoordinator`.
///
/// Wider integration via the ViewModel lives in
/// `CalculatorTimerIntegrationTests`. These tests
/// exercise the coordinator alone: representative selection, sync
/// idempotence, and exposer call recording. They are faster and
/// pinpoint coordinator regressions without the ViewModel surface.
@MainActor
final class LockScreenTimerCoordinatorTests: XCTestCase {

    // MARK: - sync(with:)

    func testSyncWithEmptyTimersClearsExposerOnlyOnce() {
        let exposer = SpyExposer()
        let coordinator = LockScreenTimerCoordinator(exposer: exposer)

        coordinator.sync(with: [])
        coordinator.sync(with: [])
        coordinator.sync(with: [])

        // No active target before — clear is a no-op until something
        // was exposed first. (sync only calls clear when the active
        // target transitions from non-nil to nil.)
        XCTAssertEqual(exposer.exposeCount, 0)
        XCTAssertEqual(exposer.clearCount, 0)
    }

    func testSyncWithOneRunningTimerExposesTargetOnce() {
        let exposer = SpyExposer()
        let coordinator = LockScreenTimerCoordinator(exposer: exposer)
        let timer = makeRunningTimer(order: 1, name: "Timer A", endIn: 60)

        coordinator.sync(with: [timer])
        coordinator.sync(with: [timer])  // idempotent

        XCTAssertEqual(exposer.exposeCount, 1)
        XCTAssertEqual(exposer.exposed.first?.representativeTimerID, timer.id)
        XCTAssertEqual(exposer.exposed.first?.representativeTimerName, "Timer A")
    }

    func testSyncTransitionsFromExposeToClearWhenAllTimersStop() {
        let exposer = SpyExposer()
        let coordinator = LockScreenTimerCoordinator(exposer: exposer)
        let timer = makeRunningTimer(order: 1, name: "Timer A", endIn: 60)

        coordinator.sync(with: [timer])
        coordinator.sync(with: [])

        XCTAssertEqual(exposer.exposeCount, 1)
        XCTAssertEqual(exposer.clearCount, 1)
    }

    func testSyncRespectsEarliestEndDateAcrossRunningTimers() {
        let exposer = SpyExposer()
        let coordinator = LockScreenTimerCoordinator(exposer: exposer)
        let later = makeRunningTimer(order: 1, name: "Later", endIn: 600)
        let sooner = makeRunningTimer(order: 2, name: "Sooner", endIn: 30)

        coordinator.sync(with: [later, sooner])

        XCTAssertEqual(exposer.exposed.last?.representativeTimerID, sooner.id)
        XCTAssertEqual(
            exposer.exposed.last?.scheduledTargets.map(\.timerID),
            [sooner.id, later.id]
        )
    }

    func testSyncIgnoresPausedAndCompletedTimers() {
        let exposer = SpyExposer()
        let coordinator = LockScreenTimerCoordinator(exposer: exposer)
        let running = makeRunningTimer(order: 1, name: "Running", endIn: 120)
        let paused = makePausedTimer(order: 2, name: "Paused", remaining: 30)
        let completed = makeCompletedTimer(order: 3, name: "Completed")

        coordinator.sync(with: [paused, running, completed])

        XCTAssertEqual(exposer.exposed.last?.representativeTimerID, running.id)
        XCTAssertEqual(exposer.exposed.last?.scheduledTargets.count, 1)
    }

    // MARK: - selectRepresentativeTarget(from:) (static utility)

    func testSelectRepresentativeReturnsNilForEmptyList() {
        XCTAssertNil(
            LockScreenTimerCoordinator.selectRepresentativeTarget(from: [])
        )
    }

    func testSelectRepresentativeReturnsNilWhenAllTimersAreNonRunning() {
        let paused = makePausedTimer(order: 1, name: "P", remaining: 60)
        let completed = makeCompletedTimer(order: 2, name: "C")

        XCTAssertNil(
            LockScreenTimerCoordinator.selectRepresentativeTarget(from: [paused, completed])
        )
    }

    func testSelectRepresentativeUsesIDOrderWhenEndDateAndPresentationTie() {
        // Two running timers at the exact same endDate AND same order ->
        // tie-break must fall through to stable id ordering.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endDate = now.addingTimeInterval(60)
        let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let aFirst = RunningTimerItem(
            id: idA, order: 1, name: "A", basisSummary: "", duration: 60,
            startDate: now, endDate: endDate,
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let bFirst = RunningTimerItem(
            id: idB, order: 1, name: "B", basisSummary: "", duration: 60,
            startDate: now, endDate: endDate,
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )

        let target = LockScreenTimerCoordinator
            .selectRepresentativeTarget(from: [bFirst, aFirst])

        // Stable id ordering picks the lexicographically smaller UUID string.
        XCTAssertEqual(target?.representativeTimerID, idA)
    }

    func testSelectRepresentativeSchedulesAllRunningTargetsInOrder() {
        let first = makeRunningTimer(order: 1, name: "First", endIn: 30)
        let second = makeRunningTimer(order: 2, name: "Second", endIn: 60)
        let third = makeRunningTimer(order: 3, name: "Third", endIn: 90)

        let target = LockScreenTimerCoordinator
            .selectRepresentativeTarget(from: [third, first, second])

        XCTAssertEqual(target?.representativeTimerID, first.id)
        XCTAssertEqual(
            target?.scheduledTargets.map(\.timerID),
            [first.id, second.id, third.id]
        )
    }

    // MARK: - Helpers

    private func makeRunningTimer(
        order: Int,
        name: String,
        endIn seconds: TimeInterval
    ) -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return RunningTimerItem(
            id: UUID(),
            order: order,
            name: name,
            basisSummary: "",
            duration: seconds,
            startDate: now,
            endDate: now.addingTimeInterval(seconds),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    private func makePausedTimer(
        order: Int,
        name: String,
        remaining: TimeInterval
    ) -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return RunningTimerItem(
            id: UUID(),
            order: order,
            name: name,
            basisSummary: "",
            duration: remaining,
            startDate: now,
            endDate: now.addingTimeInterval(remaining),
            pausedRemainingTime: remaining,
            pausedAt: now,
            status: .paused,
            referenceDate: now
        )
    }

    private func makeCompletedTimer(order: Int, name: String) -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return RunningTimerItem(
            id: UUID(),
            order: order,
            name: name,
            basisSummary: "",
            duration: 60,
            startDate: now.addingTimeInterval(-120),
            endDate: now.addingTimeInterval(-60),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )
    }
}

// MARK: - Spy

@MainActor
private final class SpyExposer: LockScreenTimerTargetExposing {
    private(set) var exposed: [LockScreenTimerTarget] = []
    private(set) var clearCount = 0

    var exposeCount: Int { exposed.count }

    func expose(_ target: LockScreenTimerTarget) {
        exposed.append(target)
    }

    func clear() {
        clearCount += 1
    }
}
