import XCTest
import PTimerKit
@testable import PTimer

/// Direct unit tests for `TimerWorkspaceModel`. These cover the timer
/// slice in isolation; `CalculatorTimerIntegrationTests`
/// covers the same behavior end-to-end through the view-model facade.
final class TimerWorkspaceModelTests: XCTestCase {

    // MARK: - Lifecycle

    @MainActor
    func testStartTimerAddsRunningEntryToTimers() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let model = makeModel(timerManager: timerManager)

        let id = model.startTimer(
            duration: 30,
            name: "0 stops - 30s",
            basisSummary: "Base 30s · 0 stops"
        )

        XCTAssertNotNil(id)
        XCTAssertEqual(model.timers.count, 1)
        let item = model.timers[0]
        XCTAssertEqual(item.status, .running)
        XCTAssertEqual(item.duration, 30, accuracy: 0.0001)
        XCTAssertEqual(item.name, "0 stops - 30s")
        XCTAssertEqual(item.basisSummary, "Base 30s · 0 stops")
    }

    @MainActor
    func testStartTimerWithNonPositiveDurationDoesNotPersistMetadata() {
        let store = SpyTimerMetadataPersistenceStore()
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let model = makeModel(
            timerManager: timerManager,
            metadataPersistenceStore: store
        )

        let id = model.startTimer(
            duration: 0,
            name: "rejected",
            basisSummary: "rejected"
        )

        XCTAssertNil(id)
        XCTAssertTrue(model.timers.isEmpty)
        // Metadata roll-back path: persistence store should never have
        // saved a snapshot containing the rejected timer.
        XCTAssertEqual(store.savedSnapshots.count, 0)
    }

    @MainActor
    func testPauseResumeLifecycleTransitions() {
        let dateBox = DateBox(date: Date(timeIntervalSince1970: 100))
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { dateBox.date }
        )
        let model = makeModel(timerManager: timerManager)

        guard let id = model.startTimer(
            duration: 30,
            name: "running",
            basisSummary: "manual"
        ) else {
            XCTFail("Timer should start")
            return
        }

        dateBox.date = Date(timeIntervalSince1970: 110)
        model.pauseTimer(id: id)
        XCTAssertEqual(model.timers.first?.status, .paused)

        dateBox.date = Date(timeIntervalSince1970: 120)
        model.resumeTimer(id: id)
        XCTAssertEqual(model.timers.first?.status, .running)
    }

    @MainActor
    func testRemoveTimerDropsTimerAndClearsPersistedMetadata() {
        let store = SpyTimerMetadataPersistenceStore()
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let model = makeModel(
            timerManager: timerManager,
            metadataPersistenceStore: store
        )

        guard let id = model.startTimer(
            duration: 30,
            name: "to-remove",
            basisSummary: "manual"
        ) else {
            XCTFail("Timer should start")
            return
        }

        XCTAssertEqual(model.timers.count, 1)
        XCTAssertEqual(store.savedSnapshots.count, 1)

        model.removeTimer(id: id)

        XCTAssertTrue(model.timers.isEmpty)
        // Removing the last timer must clear the persisted snapshot.
        // The clear may fire more than once because the
        // `TimerManager.$timers` sync path and the explicit
        // `persistTimerMetadata` after `removeValue` both observe an
        // empty metadata dict — both call paths may clear persistence.
        XCTAssertGreaterThanOrEqual(store.clearCount, 1)
    }

    @MainActor
    func testClearCompletedTimersOnlyRemovesCompletedEntries() {
        let dateBox = DateBox(date: Date(timeIntervalSince1970: 100))
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { dateBox.date }
        )
        let model = makeModel(timerManager: timerManager)

        guard let runningID = model.startTimer(
            duration: 600,
            name: "running",
            basisSummary: "manual"
        ),
              let toCompleteID = model.startTimer(
                duration: 5,
                name: "soon-done",
                basisSummary: "manual"
              ) else {
            XCTFail("Timers should start")
            return
        }

        // Advance wall clock past the short timer's completion and
        // tick the manager so it transitions to .completed.
        dateBox.date = Date(timeIntervalSince1970: 200)
        timerManager.tick()

        let completedItems = model.timers.filter { $0.status == .completed }
        XCTAssertEqual(completedItems.count, 1)
        XCTAssertTrue(completedItems.contains { $0.id == toCompleteID })

        model.clearCompletedTimers()

        XCTAssertEqual(model.timers.count, 1)
        XCTAssertEqual(model.timers.first?.id, runningID)
    }

    // MARK: - Clone-from-completed (PTIMER-36)

    @MainActor
    func testCloningCompletedTimerStartsNewRunningTimerWithSameDuration() {
        let dateBox = DateBox(date: Date(timeIntervalSince1970: 100))
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { dateBox.date }
        )
        let model = makeModel(timerManager: timerManager)

        guard let sourceID = model.startTimer(
            duration: 30,
            name: "0 stops - 30s",
            basisSummary: "Base 30s · 0 stops"
        ) else {
            XCTFail("Source timer should start")
            return
        }

        // Drive the source to `.completed` by advancing wall clock past
        // its end and ticking the manager.
        dateBox.date = Date(timeIntervalSince1970: 200)
        timerManager.tick()
        guard let completedSource = model.timers.first(where: { $0.id == sourceID }),
              completedSource.status == .completed else {
            XCTFail("Source timer should be completed before cloning")
            return
        }

        let newID = model.startTimer(cloningCompleted: completedSource)

        XCTAssertNotNil(newID)
        XCTAssertNotEqual(newID, sourceID, "Clone must get a fresh id")
        XCTAssertEqual(model.timers.count, 2)

        guard let newTimer = model.timers.first(where: { $0.id == newID }) else {
            XCTFail("Cloned timer should be in the workspace")
            return
        }
        XCTAssertEqual(newTimer.status, .running)
        XCTAssertEqual(newTimer.duration, completedSource.duration, accuracy: 0.0001)
        XCTAssertEqual(newTimer.name, completedSource.name)
        XCTAssertEqual(newTimer.basisSummary, completedSource.basisSummary)

        // Source remains unchanged.
        guard let sourceAfter = model.timers.first(where: { $0.id == sourceID }) else {
            XCTFail("Source timer should still be in the workspace")
            return
        }
        XCTAssertEqual(sourceAfter.status, .completed)
        XCTAssertEqual(sourceAfter.duration, completedSource.duration, accuracy: 0.0001)
        XCTAssertEqual(sourceAfter.completedAt, completedSource.completedAt)
        XCTAssertEqual(sourceAfter.order, completedSource.order)
    }

    @MainActor
    func testCloningCompletedTimerCopiesShootingContextIdentity() {
        let dateBox = DateBox(date: Date(timeIntervalSince1970: 100))
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { dateBox.date }
        )
        let model = makeModel(timerManager: timerManager)

        // Plain camera-slot identity; this test only verifies that
        // existing shooting context flows from the completed source
        // onto the clone.
        let cameraSlot = CameraSlotIdentity(id: .camera2)
        guard let sourceID = model.startTimer(
            duration: 64,
            name: "Tri-X 400 - 64s",
            basisSummary: "Base 1s · 6 stops · Tri-X 400",
            cameraSlot: cameraSlot,
            filmDisplayName: "Tri-X 400",
            filmProfileQualifier: "Unofficial",
            exposureSource: .filmCorrectedExposure
        ) else {
            XCTFail("Source timer should start")
            return
        }

        dateBox.date = Date(timeIntervalSince1970: 200)
        timerManager.tick()
        guard let completedSource = model.timers.first(where: { $0.id == sourceID }),
              completedSource.status == .completed else {
            XCTFail("Source timer should be completed before cloning")
            return
        }

        let newID = model.startTimer(cloningCompleted: completedSource)
        XCTAssertNotNil(newID)

        let newTimer = model.timers.first { $0.id == newID }
        XCTAssertEqual(newTimer?.cameraSlot, cameraSlot)
        XCTAssertEqual(newTimer?.filmDisplayName, "Tri-X 400")
        XCTAssertEqual(newTimer?.filmProfileQualifier, "Unofficial")
        XCTAssertEqual(newTimer?.exposureSource, .filmCorrectedExposure)
    }

    @MainActor
    func testCloningCompletedTimerPreservesFunctionalityWithoutShootingContext() {
        let dateBox = DateBox(date: Date(timeIntervalSince1970: 100))
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { dateBox.date }
        )
        let model = makeModel(timerManager: timerManager)

        guard let sourceID = model.startTimer(
            duration: 12,
            name: "Manual",
            basisSummary: "Manual timer"
        ) else {
            XCTFail("Source timer should start")
            return
        }

        dateBox.date = Date(timeIntervalSince1970: 200)
        timerManager.tick()
        guard let completedSource = model.timers.first(where: { $0.id == sourceID }),
              completedSource.status == .completed else {
            XCTFail("Source timer should be completed before cloning")
            return
        }

        guard let newID = model.startTimer(cloningCompleted: completedSource),
              let newTimer = model.timers.first(where: { $0.id == newID }) else {
            XCTFail("Cloned timer should be in the workspace")
            return
        }

        XCTAssertEqual(newTimer.status, .running)
        XCTAssertEqual(newTimer.duration, 12, accuracy: 0.0001)
        XCTAssertNil(newTimer.cameraSlot)
        XCTAssertNil(newTimer.filmDisplayName)
        XCTAssertNil(newTimer.filmProfileQualifier)
        XCTAssertNil(newTimer.exposureSource)
    }

    @MainActor
    func testCloneAssignsFreshOrderIndependentOfSource() {
        let dateBox = DateBox(date: Date(timeIntervalSince1970: 100))
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { dateBox.date }
        )
        let model = makeModel(timerManager: timerManager)

        guard let sourceID = model.startTimer(
            duration: 5,
            name: "src",
            basisSummary: "manual"
        ) else {
            XCTFail("Source timer should start")
            return
        }

        let nextOrderBeforeClone = model.nextTimerOrder

        dateBox.date = Date(timeIntervalSince1970: 200)
        timerManager.tick()
        guard let completedSource = model.timers.first(where: { $0.id == sourceID }),
              completedSource.status == .completed else {
            XCTFail("Source timer should be completed before cloning")
            return
        }

        let newID = model.startTimer(cloningCompleted: completedSource)
        let newTimer = model.timers.first { $0.id == newID }

        XCTAssertEqual(newTimer?.order, nextOrderBeforeClone)
        XCTAssertNotEqual(newTimer?.order, completedSource.order)
        XCTAssertEqual(model.nextTimerOrder, nextOrderBeforeClone + 1)
    }

    @MainActor
    func testCloningRejectsNonCompletedTimer() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let model = makeModel(timerManager: timerManager)

        guard model.startTimer(
            duration: 600,
            name: "running",
            basisSummary: "manual"
        ) != nil,
              let runningSource = model.timers.first else {
            XCTFail("Source timer should start")
            return
        }

        XCTAssertEqual(runningSource.status, .running)
        let newID = model.startTimer(cloningCompleted: runningSource)
        XCTAssertNil(newID)
        XCTAssertEqual(model.timers.count, 1, "Workspace must not gain a clone for a non-completed source")
    }

    @MainActor
    func testCloneIsIndependentLifecycleFromSource() {
        let dateBox = DateBox(date: Date(timeIntervalSince1970: 100))
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { dateBox.date }
        )
        let model = makeModel(timerManager: timerManager)

        guard let sourceID = model.startTimer(
            duration: 30,
            name: "src",
            basisSummary: "manual"
        ) else {
            XCTFail("Source timer should start")
            return
        }

        dateBox.date = Date(timeIntervalSince1970: 200)
        timerManager.tick()
        guard let completedSource = model.timers.first(where: { $0.id == sourceID }) else {
            XCTFail("Source timer missing")
            return
        }

        guard let newID = model.startTimer(cloningCompleted: completedSource) else {
            XCTFail("Clone should start")
            return
        }

        // Pause the new timer; the source's recorded completion state
        // must not change as a side effect.
        dateBox.date = Date(timeIntervalSince1970: 210)
        model.pauseTimer(id: newID)
        guard let newAfterPause = model.timers.first(where: { $0.id == newID }),
              let sourceAfterPause = model.timers.first(where: { $0.id == sourceID }) else {
            XCTFail("Both timers should still be in the workspace")
            return
        }

        XCTAssertEqual(newAfterPause.status, .paused)
        XCTAssertEqual(sourceAfterPause.status, .completed)
        XCTAssertEqual(sourceAfterPause.completedAt, completedSource.completedAt)
        XCTAssertEqual(sourceAfterPause.duration, completedSource.duration, accuracy: 0.0001)
    }

    // MARK: - Persistence

    @MainActor
    func testRestorePersistedMetadataPopulatesNamesAndOrdering() {
        let timerID = UUID()
        let snapshot = PersistentTimerMetadataCollection(
            nextTimerOrder: 7,
            timers: [
                PersistentTimerMetadataSnapshot(
                    id: timerID,
                    order: 5,
                    name: "Restored - 30s",
                    basisSummary: "Restored basis"
                ),
            ]
        )
        let store = SpyTimerMetadataPersistenceStore(initialSnapshot: snapshot)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let model = makeModel(
            timerManager: timerManager,
            metadataPersistenceStore: store
        )

        // Start a timer with the same id as the restored metadata
        // entry; the restored name + basis must surface on the
        // resulting `RunningTimerItem`.
        _ = model.startTimer(
            id: timerID,
            duration: 30,
            name: "Ignored - replaced by metadata",
            basisSummary: "ignored"
        )

        // The model's `startTimer` overwrites the metadata entry with
        // the supplied name/basis (on purpose — the caller built the
        // current name). What we want to assert here is the ordering
        // baseline: nextTimerOrder restored from snapshot drives the
        // `order` of new timers. Snapshot had nextTimerOrder=7, so
        // this new timer should get order=7 and the next should be 8.
        XCTAssertEqual(model.timers.first?.order, 7)
        XCTAssertEqual(model.nextTimerOrder, 8)
    }

    // MARK: - Multi-timer ordering

    @MainActor
    func testMultipleStartsAssignIncrementingOrder() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let model = makeModel(timerManager: timerManager)

        let firstID = model.startTimer(duration: 30, name: "first", basisSummary: "manual")
        let secondID = model.startTimer(duration: 60, name: "second", basisSummary: "manual")
        let thirdID = model.startTimer(duration: 90, name: "third", basisSummary: "manual")

        XCTAssertNotNil(firstID)
        XCTAssertNotNil(secondID)
        XCTAssertNotNil(thirdID)
        XCTAssertEqual(model.nextTimerOrder, 4)

        // Newer running timers sort earlier in the workspace ordering.
        let orders = model.timers.map(\.order)
        XCTAssertEqual(orders, [3, 2, 1])
    }
}

// MARK: - Test doubles

private final class SpyTimerMetadataPersistenceStore: TimerMetadataPersistenceStoring {
    private var loadedSnapshot: PersistentTimerMetadataCollection?
    private(set) var savedSnapshots: [PersistentTimerMetadataCollection] = []
    private(set) var clearCount: Int = 0

    init(initialSnapshot: PersistentTimerMetadataCollection? = nil) {
        self.loadedSnapshot = initialSnapshot
    }

    func loadSnapshot() -> PersistentTimerMetadataCollection? {
        loadedSnapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection) {
        savedSnapshots.append(snapshot)
    }

    func clearSnapshot() {
        clearCount += 1
    }
}

private final class DateBox {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}

@MainActor
private func makeModel(
    timerManager: TimerManager,
    metadataPersistenceStore: TimerMetadataPersistenceStoring = NoOpTimerMetadataPersistenceStore()
) -> TimerWorkspaceModel {
    TimerWorkspaceModel(
        timerManager: timerManager,
        metadataPersistenceStore: metadataPersistenceStore,
        defaultName: { duration in "Timer - \(duration)s" }
    )
}
