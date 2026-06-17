import XCTest
import PTimerCore

/// PTIMER-188: tests for the terminal `canceled` timer state and its
/// persistence round-trip. Canceled mirrors completed as a terminal
/// record but stays a distinct status so the UI can label it Canceled.
final class TimerStateCancelTests: XCTestCase {
    @MainActor
    func testCancelingRunningTimerProducesCanceledRecordAtCancellationTime() {
        let startDate = Date(timeIntervalSince1970: 100)
        let timer = TimerState(
            id: UUID(),
            duration: 60,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        let cancellationDate = startDate.addingTimeInterval(20)
        let canceled = timer.canceled(at: cancellationDate)

        XCTAssertEqual(canceled.status, .canceled)
        XCTAssertEqual(canceled.remainingTime(at: cancellationDate), 0, accuracy: 0.0001)
        // Remaining-at-cancel is captured: 60s timer canceled 20s in → 40s left.
        XCTAssertEqual(try XCTUnwrap(canceled.remainingAtCancel), 40, accuracy: 0.0001)
        XCTAssertEqual(canceled.endDate, cancellationDate)
        XCTAssertNil(canceled.pausedAt)
        XCTAssertNil(canceled.pausedRemainingTime)
        XCTAssertEqual(canceled.duration, 60, accuracy: 0.0001)
        XCTAssertEqual(canceled.startDate, startDate)
    }

    @MainActor
    func testCancelingPausedTimerProducesCanceledRecord() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(10)
        let timer = TimerState(
            id: UUID(),
            duration: 60,
            startDate: startDate,
            endDate: nil,
            pausedRemainingTime: 50,
            pausedAt: pausedAt,
            status: .paused
        )

        let cancellationDate = pausedAt.addingTimeInterval(5)
        let canceled = timer.canceled(at: cancellationDate)

        XCTAssertEqual(canceled.status, .canceled)
        XCTAssertEqual(canceled.endDate, cancellationDate)
        XCTAssertNil(canceled.pausedRemainingTime)
        // A paused timer's frozen remaining (50s) is captured as the
        // remaining-at-cancel, regardless of wall-clock since pausing.
        XCTAssertEqual(try XCTUnwrap(canceled.remainingAtCancel), 50, accuracy: 0.0001)
    }

    @MainActor
    func testCancelingTerminalTimerIsANoOp() {
        let startDate = Date(timeIntervalSince1970: 100)
        let completed = TimerState(
            id: UUID(),
            duration: 30,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed
        )

        let afterCancel = completed.canceled(at: startDate.addingTimeInterval(40))

        // A stray cancel must not rewrite a finished record.
        XCTAssertEqual(afterCancel, completed)
        XCTAssertEqual(afterCancel.status, .completed)
    }

    @MainActor
    func testCanceledTimerSurvivesPersistenceRoundTrip() {
        let startDate = Date(timeIntervalSince1970: 100)
        let canceledAt = startDate.addingTimeInterval(25)
        // Build via the running→canceled transition so remaining-at-cancel
        // is captured the way the runtime captures it.
        let running = TimerState(
            id: UUID(),
            duration: 90,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(90),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )
        let canceled = running.canceled(at: canceledAt)
        XCTAssertEqual(try XCTUnwrap(canceled.remainingAtCancel), 65, accuracy: 0.0001)

        let snapshot = PersistentTimerSnapshot(timer: canceled)
        XCTAssertEqual(snapshot.status, .canceled)
        XCTAssertEqual(snapshot.completedAt, canceledAt)
        XCTAssertNil(snapshot.expectedCompletionAt)
        XCTAssertEqual(try XCTUnwrap(snapshot.pausedRemainingDuration), 65, accuracy: 0.0001,
                       "Remaining-at-cancel persists in the pausedRemainingDuration slot")

        // Restore must not consume wall-clock time or auto-complete a
        // canceled record, regardless of how far "now" has advanced, and
        // must preserve the remaining-at-cancel.
        let restored = snapshot.restore(at: startDate.addingTimeInterval(10_000))
        XCTAssertEqual(restored.status, .canceled)
        XCTAssertEqual(restored.endDate, canceledAt)
        XCTAssertEqual(restored.duration, 90, accuracy: 0.0001)
        XCTAssertEqual(restored.startDate, startDate)
        XCTAssertEqual(try XCTUnwrap(restored.remainingAtCancel), 65, accuracy: 0.0001)
    }

    @MainActor
    func testCanceledSnapshotStatusDecodesAndUnknownStillThrows() throws {
        let decoder = JSONDecoder()

        let canceled = try decoder.decode(
            PersistentTimerSnapshot.SnapshotStatus.self,
            from: Data("\"canceled\"".utf8)
        )
        XCTAssertEqual(canceled, .canceled)

        // Legacy alias and unknown values keep their existing behavior.
        let legacyStopped = try decoder.decode(
            PersistentTimerSnapshot.SnapshotStatus.self,
            from: Data("\"stopped\"".utf8)
        )
        XCTAssertEqual(legacyStopped, .paused)

        XCTAssertThrowsError(
            try decoder.decode(
                PersistentTimerSnapshot.SnapshotStatus.self,
                from: Data("\"bogus\"".utf8)
            )
        )
    }
}
