import XCTest
@testable import PTimer

final class TimerManagerTests: XCTestCase {
    @MainActor
    func testStartSetsRunningStateFromSnapshot() {
        let manager = TimerManager(tickInterval: 60, dateProvider: { Date(timeIntervalSince1970: 100) })
        let snapshot = makeSnapshot(duration: 5)

        manager.start(snapshot: snapshot)

        XCTAssertEqual(manager.state.status, .running)
        XCTAssertEqual(manager.state.duration, 5, accuracy: 0.0001)
        XCTAssertEqual(manager.state.remainingTime, 5, accuracy: 0.0001)
        XCTAssertEqual(manager.state.elapsedTime, 0, accuracy: 0.0001)
        XCTAssertEqual(manager.state.snapshot, snapshot)

        manager.stop()
    }

    @MainActor
    func testTickDecreasesRemainingTime() {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(tickInterval: 60, dateProvider: { startDate })

        manager.start(snapshot: makeSnapshot(duration: 5))
        manager.tick(now: startDate.addingTimeInterval(2))

        XCTAssertEqual(manager.state.status, .running)
        XCTAssertEqual(manager.state.remainingTime, 3, accuracy: 0.0001)
        XCTAssertEqual(manager.state.elapsedTime, 2, accuracy: 0.0001)

        manager.stop()
    }

    @MainActor
    func testTickCompletesWhenTimeExpires() {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(tickInterval: 60, dateProvider: { startDate })

        manager.start(snapshot: makeSnapshot(duration: 3))
        manager.tick(now: startDate.addingTimeInterval(3))

        XCTAssertEqual(manager.state.status, .completed)
        XCTAssertEqual(manager.state.remainingTime, 0, accuracy: 0.0001)
        XCTAssertEqual(manager.state.elapsedTime, 3, accuracy: 0.0001)
    }

    @MainActor
    func testRestartWhileRunningReplacesSnapshot() {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(tickInterval: 60, dateProvider: { startDate })
        let first = makeSnapshot(name: "ND64 - 2s", duration: 2)
        let second = makeSnapshot(name: "ND1000 - 30s", duration: 30)

        manager.start(snapshot: first)
        manager.tick(now: startDate.addingTimeInterval(1))
        manager.start(snapshot: second)

        XCTAssertEqual(manager.state.status, .running)
        XCTAssertEqual(manager.state.snapshot, second)
        XCTAssertEqual(manager.state.duration, 30, accuracy: 0.0001)
        XCTAssertEqual(manager.state.remainingTime, 30, accuracy: 0.0001)
        XCTAssertEqual(manager.state.elapsedTime, 0, accuracy: 0.0001)

        manager.stop()
    }

    @MainActor
    func testZeroDurationCompletesImmediately() {
        let manager = TimerManager(tickInterval: 60, dateProvider: Date.init)

        manager.start(snapshot: makeSnapshot(duration: 0))

        XCTAssertEqual(manager.state.status, .completed)
        XCTAssertEqual(manager.state.remainingTime, 0, accuracy: 0.0001)
        XCTAssertEqual(manager.state.elapsedTime, 0, accuracy: 0.0001)
    }

    private func makeSnapshot(
        name: String = "ND64 - 2s",
        duration: TimeInterval
    ) -> TimerSnapshot {
        TimerSnapshot(
            name: name,
            totalDuration: duration,
            baseShutterSeconds: 1.0 / 30.0,
            ndFactor: 64,
            resultShutterSeconds: duration
        )
    }
}
