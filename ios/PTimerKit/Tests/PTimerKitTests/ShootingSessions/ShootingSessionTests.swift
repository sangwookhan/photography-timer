// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class ShootingSessionTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    func testConnectionBoundaryB01() {
        for (gap, expected) in [(3599.999, true), (3600, true), (3600.001, false)] {
            XCTAssertEqual(ShootingSessionPolicy.normal.connects(
                start: epoch + gap, firstStart: epoch, latestStart: epoch
            ), expected)
        }
    }

    func testAdmissionSpanBoundaryB02() {
        for (span, expected) in [(28799.999, true), (28800, false), (28800.001, false)] {
            XCTAssertEqual(ShootingSessionPolicy.normal.connects(
                start: epoch + span, firstStart: epoch, latestStart: epoch + 27000
            ), expected)
        }
    }

    @MainActor
    func testSimultaneousInputPermutationB03() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let activity = ShootingSessionActivity(startedAt: epoch, policy: .normal)
        let first = ShootingSessionLedger(store: NoOpShootingSessionStore())
        let second = ShootingSessionLedger(store: NoOpShootingSessionStore())
        first.reconcile(activities: [(a, 1, activity), (b, 2, activity)])
        second.reconcile(activities: [(b, 2, activity), (a, 1, activity)])
        XCTAssertEqual(first.confirmed, second.confirmed)
        XCTAssertEqual(first.membership(for: a)?.sessionID, first.membership(for: b)?.sessionID)
    }

    @MainActor
    func testAlternatingStartsB04() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0)
        let b = try rig.start(at: 3000)
        let c = try rig.start(at: 6000)
        XCTAssertEqual(rig.session(a), rig.session(b))
        XCTAssertEqual(rig.session(a), rig.session(c))
    }

    @MainActor
    func testCompletionDoesNotRenewActivityB05() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0, duration: 7140)
        rig.clock.now = rig.epoch + 7200
        rig.manager.tick()
        let b = try rig.start(at: 7200)
        XCTAssertNotEqual(rig.session(a), rig.session(b))
    }

    func testMidnightAndClockReversalB06B07() {
        XCTAssertTrue(ShootingSessionPolicy.normal.connects(start: epoch + 1200, firstStart: epoch, latestStart: epoch))
        XCTAssertFalse(ShootingSessionPolicy.normal.connects(start: epoch - 60, firstStart: epoch, latestStart: epoch))
    }

    @MainActor
    func testSeventySecondsInEachModeB16A() throws {
        for shortened in [false, true] {
            let rig = SessionRig()
            rig.model.shortenedSessionIntervals = shortened
            let a = try rig.start(at: 0)
            let b = try rig.start(at: 70)
            XCTAssertEqual(rig.session(a) == rig.session(b), !shortened)
        }
    }

    @MainActor
    func testDebugMaximumSpan479And480B16B() throws {
        for shortened in [false, true] {
            for end in [479.0, 480.0] {
                let rig = SessionRig()
                rig.model.shortenedSessionIntervals = shortened
                let a = try rig.start(at: 0)
                for time in stride(from: 50.0, through: 450.0, by: 50) {
                    let id = try rig.start(at: time)
                    XCTAssertEqual(rig.session(a), rig.session(id))
                }
                let last = try rig.start(at: end)
                XCTAssertEqual(rig.session(a) == rig.session(last), !shortened || end < 480)
                XCTAssertEqual(rig.session(a), a)
            }
        }
    }

    @MainActor
    func testModeSwitchAndRelaunchKeepEachSessionIDB16C() throws {
        for shortened in [false, true] {
            let disk = SessionDisk()
            let rig = SessionRig(disk: disk)
            rig.model.shortenedSessionIntervals = shortened
            let a = try rig.start(at: 0)
            let b = try rig.start(at: 70)
            let before = [a: try XCTUnwrap(rig.session(a)), b: try XCTUnwrap(rig.session(b))]
            XCTAssertEqual(before[a] == before[b], !shortened)
            rig.model.shortenedSessionIntervals.toggle()
            XCTAssertEqual(rig.session(a), before[a])
            XCTAssertEqual(rig.session(b), before[b])
            let restored = SessionRig(disk: disk, now: rig.epoch + 75)
            XCTAssertEqual(restored.session(a), before[a])
            XCTAssertEqual(restored.session(b), before[b])
            XCTAssertEqual(Set(restored.manager.timers.map(\.id)), Set([a, b]))
        }
    }

    @MainActor
    func testModeSwitchPreservesPauseBoundaryB16D() throws {
        for shortened in [false, true] {
            let rig = SessionRig()
            rig.model.shortenedSessionIntervals = shortened
            let a = try rig.start(at: 0, duration: 300)
            let session = try XCTUnwrap(rig.session(a))
            rig.clock.now = rig.epoch + 10
            rig.manager.pause(id: a)
            rig.clock.now = rig.epoch + 20
            rig.model.shortenedSessionIntervals.toggle()
            rig.clock.now = rig.epoch + 129.999
            rig.manager.tick()
            XCTAssertEqual(rig.manager.timers.first?.status, .paused)
            XCTAssertEqual(rig.manager.timers.first?.pausedRemainingTime, 290)
            XCTAssertEqual(rig.session(a), session)
            rig.clock.now = rig.epoch + 130
            rig.manager.tick()
            XCTAssertEqual(rig.manager.timers.first?.status, .canceled)
            XCTAssertEqual(rig.manager.timers.first?.endDate, rig.epoch + 130)
            XCTAssertEqual(rig.manager.timers.first?.remainingAtCancel, 290)
            XCTAssertEqual(rig.manager.timers.first?.id, a)
            XCTAssertEqual(rig.session(a), session)
        }
    }

    @MainActor
    func testLongTimerDoesNotImposeDurationExceptionB17() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0, duration: 25 * 3600)
        let b = try rig.start(at: 3000)
        XCTAssertEqual(rig.session(a), rig.session(b))
        XCTAssertEqual(rig.manager.timers.first(where: { $0.id == a })?.status, .running)
    }

    @MainActor
    func testCancellationTimeDoesNotRenewActivityB18() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0, duration: 7200)
        let session = try XCTUnwrap(rig.session(a))
        rig.clock.now = rig.epoch + 3540
        rig.manager.pause(id: a)
        rig.clock.now = rig.epoch + 3660
        rig.manager.tick()
        let b = try rig.start(at: 3900)
        XCTAssertEqual(rig.manager.timers.first(where: { $0.id == a })?.endDate, rig.epoch + 3660)
        XCTAssertEqual(rig.session(a), session)
        XCTAssertNotEqual(rig.session(b), session)
    }

    @MainActor
    func testOvernightPausedRestoreKeepsOriginalSessionB18() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        let a = try rig.start(at: 0, duration: 300)
        rig.clock.now = rig.epoch + 60
        rig.manager.pause(id: a)
        let session = try XCTUnwrap(rig.session(a))
        let restored = SessionRig(disk: disk, now: rig.epoch + 90000)
        let b = try restored.start(at: 90000)
        XCTAssertEqual(restored.manager.timers.first(where: { $0.id == a })?.endDate, rig.epoch + 180)
        XCTAssertEqual(restored.manager.timers.first(where: { $0.id == a })?.remainingAtCancel, 240)
        XCTAssertEqual(restored.session(a), session)
        XCTAssertNotEqual(restored.session(b), session)
    }

    @MainActor
    func testResumeDoesNotRenewActivityB20() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0, duration: 7200)
        rig.clock.now = rig.epoch + 3480
        rig.manager.pause(id: a)
        rig.clock.now = rig.epoch + 3540
        rig.manager.resume(id: a)
        let b = try rig.start(at: 3660)
        XCTAssertNotEqual(rig.session(a), rig.session(b))
    }

    @MainActor
    func testAssignmentFailuresCountRetainedStartsThenRetryWithoutDuplicatesF01F02() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        disk.failAssignments = true
        let a = try rig.start(at: 0)
        let b = try rig.start(at: 1800)
        XCTAssertNil(rig.session(a))
        XCTAssertNil(rig.session(b))
        XCTAssertTrue(rig.model.sessions.hasPendingAssignments)
        for _ in 0..<3 { rig.model.retrySessionAssignments() }
        disk.failAssignments = false
        for _ in 0..<3 { rig.model.retrySessionAssignments() }
        XCTAssertEqual(rig.session(a), rig.session(b))
        XCTAssertNotNil(rig.session(a))
        XCTAssertEqual(Set(rig.manager.timers.map(\.id)), Set([a, b]))
    }

    @MainActor
    func testInterruptedAssignmentRecoversOriginalActivityF03F04() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        disk.failAssignments = true
        let a = try rig.start(at: 0)
        let b = try rig.start(at: 1800)
        disk.failAssignments = false
        let restored = SessionRig(disk: disk, now: rig.epoch + 1900)
        XCTAssertEqual(restored.session(a), restored.session(b))
        let again = SessionRig(disk: disk, now: rig.epoch + 1900)
        XCTAssertEqual(again.session(a), restored.session(a))
        XCTAssertEqual(again.manager.timers.count, 2)
    }

    @MainActor
    func testConfirmedRecordSaveFailureDoesNotStartOrCancelPausedTimersF09() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        let a = try rig.start(at: 0, duration: 600)
        rig.clock.now = rig.epoch + 10
        rig.manager.pause(id: a)
        let session = rig.session(a)
        disk.failTimerStarts = true
        XCTAssertNil(rig.model.startTimer(duration: 60, name: "Failed", basisSummary: ""))
        XCTAssertEqual(rig.manager.timers.count, 1)
        XCTAssertEqual(rig.manager.timers.first?.status, .paused)
        XCTAssertEqual(rig.session(a), session)
        XCTAssertNotNil(rig.model.startError)
        disk.failTimerStarts = false
        let b = try rig.start(at: 4000)
        XCTAssertNotEqual(rig.session(b), session)
    }

    @MainActor
    func testUnknownRetainedWriteIsResolvedWithoutDuplicateStart() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        disk.uncertainTimerStart = true
        let a = try rig.start(at: 0)
        XCTAssertEqual(rig.manager.timers.map(\.id), [a])
        let restored = SessionRig(disk: disk)
        XCTAssertEqual(restored.manager.timers.map(\.id), [a])
    }

    @MainActor
    func testUncertainUnreadableStartRetriesSameTimerAndOriginalActivity() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        let a = try rig.start(at: 0, duration: 600)
        rig.clock.now = rig.epoch + 10
        rig.manager.pause(id: a)
        let originalSession = rig.session(a)
        disk.uncertainTimerStart = true
        disk.blockVerificationOnUncertainWrite = true
        let requestedID = UUID()
        rig.clock.now = rig.epoch + 20
        XCTAssertNil(rig.model.startTimer(id: requestedID, duration: 2, name: "Retried", basisSummary: ""))
        XCTAssertEqual(rig.manager.timers.map(\.id), [a])
        XCTAssertEqual(rig.manager.timers.first?.status, .paused)
        rig.clock.now = rig.epoch + 30
        rig.manager.tick()
        disk.readFails = false
        let retriedID = try XCTUnwrap(rig.model.startTimer(duration: 60, name: "Different request", basisSummary: ""))
        XCTAssertEqual(retriedID, requestedID)
        XCTAssertEqual(Set(rig.manager.timers.map(\.id)), Set([a, requestedID]))
        let retained = try XCTUnwrap(rig.manager.timers.first(where: { $0.id == requestedID }))
        XCTAssertEqual(retained.startDate, rig.epoch + 20)
        XCTAssertEqual(retained.status, .completed)
        XCTAssertEqual(retained.endDate, rig.epoch + 22)
        XCTAssertEqual(rig.session(requestedID), originalSession)
        XCTAssertEqual(rig.model.timers.first(where: { $0.id == requestedID })?.name, "Retried")
    }

    @MainActor
    func testRemovalWhileStartUncertainDoesNotResurrectDeletedTimer() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        let a = try rig.start(at: 0, duration: 600)
        disk.uncertainTimerStart = true
        disk.blockVerificationOnUncertainWrite = true
        let b = UUID()
        rig.clock.now = rig.epoch + 20
        XCTAssertNil(rig.model.startTimer(id: b, duration: 60, name: "Pending", basisSummary: ""))
        rig.model.removeTimer(id: a)
        disk.readFails = false
        XCTAssertEqual(rig.model.startTimer(duration: 60, name: "Retry", basisSummary: ""), b)
        XCTAssertEqual(rig.manager.timers.map(\.id), [b])
        let restored = SessionRig(disk: disk, now: rig.epoch + 25)
        XCTAssertEqual(restored.manager.timers.map(\.id), [b])
    }

    @MainActor
    func testDeletionDoesNotRewindBoundaryB13() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0)
        let b = try rig.start(at: 3000)
        rig.model.removeTimer(id: b)
        let c = try rig.start(at: 6000)
        XCTAssertEqual(rig.session(a), rig.session(c))
    }
    @MainActor
    func testHistoryInterleavingAndSessionProjectionB19() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0, duration: 10800)
        let b = try rig.start(at: 7200, duration: 60)
        let c = try rig.start(at: 8400, duration: 3600)
        rig.clock.now = rig.epoch + 12001
        rig.manager.tick()
        XCTAssertEqual(rig.model.timers.map(\.id), [c, a, b])
        let snapshot = BottomSheetWorkspaceSnapshot.make(
            from: rig.model.timers, formatRemaining: { "\($0)" }, formatShutter: { "\($0)" },
            ndNotationMode: .stops, timeContext: { _ in nil }, compactCompletedSupplementaryText: { _ in nil }
        )
        let session = try XCTUnwrap(rig.session(b))
        XCTAssertEqual(rig.model.sessions.sections(for: session, from: snapshot).flatMap(\.items).map(\.id), [c, b])
        XCTAssertEqual(rig.model.timers.map(\.id), [c, a, b])
    }

    func testEqualStartAndTerminalTimesHaveStableHistoryOrderB03() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        for equalOrder in [false, true] {
            let items = [(a, equalOrder ? 2 : 1), (b, 2)].map { id, order in
                RunningTimerItem(id: id, order: order, name: "Timer", basisSummary: "", duration: 60,
                                 startDate: epoch, endDate: epoch + 60, pausedRemainingTime: nil,
                                 pausedAt: nil, status: .completed, referenceDate: epoch + 61)
            }
            let expected = equalOrder ? [a, b] : [b, a]
            XCTAssertEqual(TimerWorkspaceOrdering.sort(items).map(\.id), expected)
            XCTAssertEqual(TimerWorkspaceOrdering.sort(Array(items.reversed())).map(\.id), expected)
        }
    }

    @MainActor
    func testInvalidStartDoesNotCancelPausedOrRenewSessionB09() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0, duration: 600)
        let running = try rig.start(at: 1, duration: 9000)
        rig.manager.pause(id: a)
        XCTAssertNil(rig.model.startTimer(duration: .nan, name: "Invalid", basisSummary: ""))
        XCTAssertEqual(rig.manager.timers.first(where: { $0.id == a })?.status, .paused)
        let next = try rig.start(at: 4000)
        XCTAssertEqual(rig.manager.timers.first(where: { $0.id == a })?.status, .canceled)
        XCTAssertEqual(rig.manager.timers.first(where: { $0.id == running })?.status, .running)
        XCTAssertNotEqual(rig.session(next), rig.session(a))
        XCTAssertEqual(rig.manager.timers.count, 3)
    }

    @MainActor
    func testRepeatAssignsFreshActivityB10() throws {
        let rig = SessionRig()
        let a = try rig.start(at: 0)
        rig.clock.now = rig.epoch + 4000
        rig.manager.tick()
        let source = try XCTUnwrap(rig.model.timers.first)
        let b = try XCTUnwrap(rig.model.startTimer(cloning: source))
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(rig.session(a), rig.session(b))
        XCTAssertEqual(rig.model.timers.first(where: { $0.id == a })?.status, .completed)
    }

    @MainActor
    func testSessionReadFailureDoesNotOverwriteAndCanRetryF05F06() {
        let store = DelayedSessionStore()
        let a = UUID()
        let activity = ShootingSessionActivity(startedAt: epoch, policy: .normal)
        let model = ShootingSessionLedger(store: store)
        model.reconcile(activities: [(a, 1, activity)])
        XCTAssertEqual(store.writes, 0)
        XCTAssertNil(model.membership(for: a))
        store.readFails = false
        model.reconcile(activities: [(a, 1, activity)])
        XCTAssertEqual(model.membership(for: a)?.sessionID, a)
        XCTAssertEqual(store.writes, 1)
        model.reconcile(activities: [(a, 1, activity)])
        XCTAssertEqual(store.writes, 1)
    }

    @MainActor
    func testMalformedMembershipDoesNotDropOtherRecordsF07() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        let a = try rig.start(at: 0)
        let b = try rig.start(at: 20)
        try disk.editSessions { root in
            var members = root["memberships"] as? [[String: Any]] ?? []
            members.append(["timerID": "invalid"])
            root["memberships"] = members
        }
        let restored = SessionRig(disk: disk, now: rig.epoch + 30)
        XCTAssertEqual(restored.manager.timers.count, 2)
        XCTAssertEqual(restored.session(a), rig.session(a))
        XCTAssertEqual(restored.session(b), rig.session(b))
    }

    @MainActor
    func testUnsupportedSessionPayloadDoesNotEraseTimerRecordsF05() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        let a = try rig.start(at: 0)
        try disk.editSessions { $0["schemaVersion"] = 99 }
        let badSessions = try XCTUnwrap(disk.sessionData())
        let restored = SessionRig(disk: disk, now: rig.epoch + 10)
        restored.model.retrySessionAssignments()
        XCTAssertEqual(restored.manager.timers.map(\.id), [a])
        XCTAssertEqual(disk.sessionData(), badSessions)
        XCTAssertNil(restored.session(a))
    }

    @MainActor
    func testMalformedSessionComponentKeepsReadableTimersAndRawQuarantine() throws {
        let disk = SessionDisk()
        let rig = SessionRig(disk: disk)
        let a = try rig.start(at: 0)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(disk.data)) as? [String: Any])
        root["sessions"] = "not base64"
        root.removeValue(forKey: "schemaVersion")
        let raw = try JSONSerialization.data(withJSONObject: root)
        disk.data = raw
        var quarantined: Data?
        let repository = TimerRecordRepository(read: { disk.data }, write: disk.write, quarantine: { quarantined = $0 })
        let manager = RuntimeBackedTimerManaging(dateProvider: { self.epoch + 20 }, persistenceStore: TimerRecordRuntimeStore(repository: repository))
        let workspace = TimerWorkspaceModel(timerManager: manager, metadataPersistenceStore: TimerRecordMetadataStore(repository: repository), defaultName: { _ in "Timer" }, sessionStore: repository)
        XCTAssertEqual(workspace.timers.map(\.id), [a])
        XCTAssertNil(workspace.sessions.membership(for: a))
        XCTAssertEqual(quarantined, raw)
    }

    @MainActor
    func testLegacyRecordsMigrateWithoutRetrospectiveAssignmentF08() throws {
        let disk = SessionDisk()
        let id = UUID()
        let state = TimerState(id: id, duration: 60, startDate: epoch, endDate: epoch + 60,
                               pausedRemainingTime: nil, pausedAt: nil, status: .completed)
        let repository = TimerRecordRepository(
            read: { disk.data }, write: disk.write,
            legacyTimers: .init(timers: [state]),
            legacyMetadata: .init(nextTimerOrder: 2, timers: [
                .init(id: id, order: 1, name: "Legacy", basisSummary: "Legacy context")
            ])
        )
        let manager = RuntimeBackedTimerManaging(dateProvider: { self.epoch + 120 }, persistenceStore: TimerRecordRuntimeStore(repository: repository))
        let workspace = TimerWorkspaceModel(timerManager: manager, metadataPersistenceStore: TimerRecordMetadataStore(repository: repository), defaultName: { _ in "Timer" }, sessionStore: repository)
        XCTAssertEqual(workspace.timers.first?.name, "Legacy")
        XCTAssertNil(workspace.sessions.membership(for: id))
        let restored = SessionRig(disk: disk, now: epoch + 150)
        XCTAssertEqual(restored.manager.timers.map(\.id), [id])
        XCTAssertNil(restored.session(id))
    }

}

private final class SessionClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private final class SessionDisk {
    var data: Data?
    var failAssignments = false
    var failTimerStarts = false
    var uncertainTimerStart = false
    var blockVerificationOnUncertainWrite = false
    var readFails = false

    func read() throws -> Data? {
        if readFails { throw NSError(domain: "SessionDisk", code: 1) }
        return data
    }

    func write(_ candidate: Data) -> TimerSnapshotSaveResult {
        let old = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        let new = (try? JSONSerialization.jsonObject(with: candidate)) as? [String: Any] ?? [:]
        if failAssignments, (old["sessions"] as? String) != (new["sessions"] as? String) { return .failed }
        let oldTimers = timerCount(old["timers"] as? String)
        let newTimers = timerCount(new["timers"] as? String)
        if failTimerStarts, newTimers > oldTimers { return .failed }
        data = candidate
        if uncertainTimerStart, newTimers > oldTimers {
            uncertainTimerStart = false
            readFails = blockVerificationOnUncertainWrite
            return .uncertain
        }
        return .saved
    }

    func sessionData() -> Data? {
        let root = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        return (root?["sessions"] as? String).flatMap { Data(base64Encoded: $0) }
    }

    func editSessions(_ update: (inout [String: Any]) -> Void) throws {
        let retained = try XCTUnwrap(data)
        var archive = try XCTUnwrap(try JSONSerialization.jsonObject(with: retained) as? [String: Any])
        let sessionBytes = try XCTUnwrap(sessionData())
        var sessions = try XCTUnwrap(try JSONSerialization.jsonObject(with: sessionBytes) as? [String: Any])
        update(&sessions)
        archive["sessions"] = try JSONSerialization.data(withJSONObject: sessions).base64EncodedString()
        data = try JSONSerialization.data(withJSONObject: archive)
    }

    private func timerCount(_ value: String?) -> Int {
        guard let value, let data = Data(base64Encoded: value) else { return 0 }
        return PersistentTimerCollectionSnapshot.decode(from: data).snapshot.timers.count
    }
}

@MainActor
private final class SessionRig {
    let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    let clock: SessionClock
    let manager: RuntimeBackedTimerManaging
    let model: TimerWorkspaceModel

    init(disk: SessionDisk = SessionDisk(), now: Date? = nil) {
        clock = SessionClock(now ?? epoch)
        let clock = clock
        let repository = TimerRecordRepository(read: disk.read, write: disk.write)
        manager = RuntimeBackedTimerManaging(dateProvider: { clock.now }, persistenceStore: TimerRecordRuntimeStore(repository: repository))
        model = TimerWorkspaceModel(
            timerManager: manager, metadataPersistenceStore: TimerRecordMetadataStore(repository: repository),
            defaultName: { _ in "Timer" }, sessionStore: repository
        )
    }

    func start(at seconds: TimeInterval, duration: TimeInterval = 2) throws -> UUID {
        clock.now = epoch + seconds
        manager.tick()
        return try XCTUnwrap(model.startTimer(duration: duration, name: "Timer", basisSummary: ""))
    }

    func session(_ timer: UUID) -> UUID? { model.sessions.membership(for: timer)?.sessionID }
}

private final class DelayedSessionStore: ShootingSessionStoring {
    var readFails = true
    var writes = 0
    var stored = PersistentShootingSessions()
    func loadSessions() -> ShootingSessionLoadResult { readFails ? .failed : .loaded(stored) }
    func saveSessions(_ snapshot: PersistentShootingSessions) -> Bool {
        writes += 1
        stored = snapshot
        return true
    }
}
