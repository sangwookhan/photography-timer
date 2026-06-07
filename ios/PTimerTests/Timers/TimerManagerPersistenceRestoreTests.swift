import XCTest
import PTimerCore
@testable import PTimer

final class TimerManagerPersistenceRestoreTests: XCTestCase {
    @MainActor
    func testPersistedPausedSnapshotOmitsExpectedCompletionAt() throws {
        // Per Timer Spec §3.1, `expectedCompletionAt` is meaningful for
        // running status only. The PersistentTimerSnapshot init now
        // writes nil for paused timers; the hypothetical completion
        // date is reconstructed on read from `pausedAt +
        // pausedRemainingDuration`.
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        let snapshot = PersistentTimerSnapshot(timer: pausedTimer)

        XCTAssertEqual(snapshot.status, .paused)
        XCTAssertNil(snapshot.expectedCompletionAt)
        XCTAssertEqual(snapshot.pausedRemainingDuration, 6)
        XCTAssertEqual(snapshot.pausedAt, startDate.addingTimeInterval(4))
    }

    @MainActor
    func testRestoreLegacyPausedSnapshotIgnoresExpectedCompletionAt() throws {
        // Legacy snapshots wrote
        // `expectedCompletionAt` for paused timers. Restore must
        // ignore that field and reconstruct the hypothetical end
        // date from the freeze metadata so the resumable state is
        // identical regardless of whether the snapshot is legacy or
        // current. Simulate a legacy snapshot via JSON decoding
        // because the in-process initializer no longer accepts a
        // non-nil `expectedCompletionAt` for paused.
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)

        // Legacy JSON deliberately makes expectedCompletionAt point
        // somewhere far from `pausedAt + pausedRemainingDuration`
        // (the legacy stored value could go stale across edits).
        let legacyJSON = #"""
        {
          "id": "DEADBEEF-1111-2222-3333-444444444444",
          "status": "paused",
          "duration": 10,
          "startDate": 100,
          "expectedCompletionAt": 199,
          "pausedRemainingDuration": 6,
          "pausedAt": 104,
          "completedAt": null
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let legacy = try decoder.decode(
            PersistentTimerSnapshot.self,
            from: Data(legacyJSON.utf8)
        )

        let restored = legacy.restore(at: startDate.addingTimeInterval(50))

        XCTAssertEqual(restored.status, .paused)
        XCTAssertEqual(restored.pausedRemainingTime, 6)
        XCTAssertEqual(restored.pausedAt, pausedAt)
        XCTAssertEqual(restored.endDate, pausedAt.addingTimeInterval(6))
    }

    @MainActor
    func testRestoreRunningTimerAfterTerminationKeepsItRunningWithWallClockRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .running)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 6, accuracy: 0.0001)
        XCTAssertEqual(restored.endDate, startDate.addingTimeInterval(10))
    }

    @MainActor
    func testRestoreRunningTimerAfterTerminationCompletesIfExpectedCompletionAlreadyPassed() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 3))

        currentDate = startDate.addingTimeInterval(5)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .completed)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 0, accuracy: 0.0001)
        XCTAssertEqual(restored.endDate, startDate.addingTimeInterval(3))
    }

    @MainActor
    func testRestorePausedTimerAfterTerminationPreservesFrozenRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(4)
        initialManager.pause(id: id)

        currentDate = startDate.addingTimeInterval(40)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .paused)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 6, accuracy: 0.0001)
        XCTAssertEqual(restored.pausedAt, startDate.addingTimeInterval(4))
    }

    @MainActor
    func testRestoreWithCorruptedPersistedSnapshotSafelyFallsBackToEmptyState() {
        let suiteName = "TimerManagerTests.corrupted.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set(Data("not-json".utf8), forKey: "ptimer.timer-state.snapshot")

        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) },
            persistenceStore: UserDefaultsTimerPersistenceStore(userDefaults: userDefaults)
        )

        XCTAssertTrue(manager.timers.isEmpty)
    }

    @MainActor
    func testRestoreDecodesLegacyStoppedSnapshotValueAsPaused() throws {
        struct LegacySnapshotStatusTimer: Encodable {
            let id: UUID
            let status: String
            let duration: TimeInterval
            let startDate: Date
            let expectedCompletionAt: Date?
            let pausedRemainingDuration: TimeInterval?
            let pausedAt: Date?
            let completedAt: Date?
        }

        struct LegacySnapshotCollection: Encodable {
            let timers: [LegacySnapshotStatusTimer]
        }

        let suiteName = "TimerManagerTests.legacy.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)
        let timerID = UUID()
        let legacySnapshot = LegacySnapshotCollection(
            timers: [
                LegacySnapshotStatusTimer(
                    id: timerID,
                    status: "stopped",
                    duration: 10,
                    startDate: startDate,
                    expectedCompletionAt: startDate.addingTimeInterval(10),
                    pausedRemainingDuration: 6,
                    pausedAt: pausedAt,
                    completedAt: nil
                ),
            ]
        )

        let encoded = try JSONEncoder().encode(legacySnapshot)
        userDefaults.set(encoded, forKey: "ptimer.timer-state.snapshot")

        let currentDate = startDate.addingTimeInterval(40)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: UserDefaultsTimerPersistenceStore(userDefaults: userDefaults)
        )

        let restored = tryUnwrapTimer(withID: timerID, from: manager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .paused)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 6, accuracy: 0.0001)
        XCTAssertEqual(restored.pausedAt, pausedAt)
    }

    @MainActor
    func testRestoreCompletedTimerAfterTerminationKeepsCompletedState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 2))
        currentDate = startDate.addingTimeInterval(2)
        initialManager.tick(now: currentDate)

        currentDate = startDate.addingTimeInterval(20)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .completed)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 0, accuracy: 0.0001)
        XCTAssertEqual(restored.endDate, startDate.addingTimeInterval(2))
    }

    @MainActor
    func testRestoreMultipleTimersAfterTerminationPreservesIDsAndStatuses() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let runningID = try XCTUnwrap(initialManager.start(duration: 10))
        let pausedID = try XCTUnwrap(initialManager.start(duration: 12))
        let completedID = try XCTUnwrap(initialManager.start(duration: 3))

        currentDate = startDate.addingTimeInterval(4)
        initialManager.pause(id: pausedID)
        initialManager.tick(now: currentDate)

        currentDate = startDate.addingTimeInterval(5)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        XCTAssertEqual(restoredManager.timers.map(\.id), [runningID, pausedID, completedID])
        XCTAssertEqual(
            restoredManager.timers.map { $0.status(at: currentDate) },
            [.running, .paused, .completed]
        )
        XCTAssertEqual(
            tryUnwrapTimer(withID: runningID, from: restoredManager.timers).remainingTime(at: currentDate),
            5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            tryUnwrapTimer(withID: pausedID, from: restoredManager.timers).remainingTime(at: currentDate),
            8,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testResumeThenRelaunchRestoresRunningTimerWithReconciledRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(4)
        initialManager.pause(id: id)

        currentDate = startDate.addingTimeInterval(6)
        initialManager.resume(id: id)

        currentDate = startDate.addingTimeInterval(8)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .running)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 4, accuracy: 0.0001)
        XCTAssertEqual(restored.endDate, startDate.addingTimeInterval(12))
    }

    @MainActor
    func testRestoreEntryPointLoadsSnapshotOnlyDuringInitialization() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )
        _ = try XCTUnwrap(initialManager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(1)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        XCTAssertEqual(store.loadCallCount, 2)

        currentDate = startDate.addingTimeInterval(2)
        restoredManager.reconcile()
        restoredManager.tick(now: currentDate)

        XCTAssertEqual(store.loadCallCount, 2)
    }

    @MainActor
    func testRemovingLastTimerClearsPersistedSnapshot() throws {
        let store = InMemoryTimerPersistenceStore()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) },
            persistenceStore: store
        )

        let id = try XCTUnwrap(manager.start(duration: 5))
        XCTAssertNotNil(store.snapshot)

        manager.remove(id: id)

        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertNil(store.snapshot)
    }

    @MainActor
    func testRepeatedRelaunchRestoreDoesNotDuplicatePersistedTimers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )
        let id = try XCTUnwrap(initialManager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(2)
        let firstRelaunch = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )
        XCTAssertEqual(firstRelaunch.timers.map(\.id), [id])

        currentDate = startDate.addingTimeInterval(4)
        let secondRelaunch = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        XCTAssertEqual(secondRelaunch.timers.count, 1)
        XCTAssertEqual(secondRelaunch.timers.map(\.id), [id])
        XCTAssertEqual(
            tryUnwrapTimer(withID: id, from: secondRelaunch.timers).remainingTime(at: currentDate),
            6,
            accuracy: 0.0001
        )
    }
}
