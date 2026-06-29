// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import UserNotifications
import PTimerCore
@testable import PTimer

/// PTIMER-73: the background notification scheduler maps a running timer's
/// staged-alert schedule onto one local notification per stage, with distinct
/// identifiers, stage-specific copy, and a haptic-first (silent) pre1. Cancel
/// removes every stage for the timer. Past pre-alerts are skipped (a resume
/// near the end never fires a stale "Ns remaining") and a cancel that races a
/// still-in-flight async add leaves no stale pending requests.
final class StagedNotificationSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let calendar = Calendar.current

    @MainActor
    func testLongTimerSchedulesPre1Pre2AndCompletion() async throws {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        let timer = runningTimer(id: id, start: now, duration: 75) // pre1@65, pre2@70, end@75

        center.expectAdds(3)
        scheduler.scheduleCompletionNotification(for: timer)
        await center.awaitAdds()

        let byIdentifier = Dictionary(
            uniqueKeysWithValues: center.addedRequests.map { ($0.identifier, $0) }
        )

        let pre1 = try XCTUnwrap(byIdentifier["timer-pre1-\(id.uuidString.lowercased())"])
        XCTAssertEqual(pre1.content.body, "10s remaining")
        XCTAssertNil(pre1.content.sound, "pre1 is haptic-first and must carry no sound")

        let pre2 = try XCTUnwrap(byIdentifier["timer-pre2-\(id.uuidString.lowercased())"])
        XCTAssertEqual(pre2.content.body, "5s remaining")
        XCTAssertEqual(pre2.content.sound, .default)

        let completion = try XCTUnwrap(byIdentifier["timer-completion-\(id.uuidString.lowercased())"])
        XCTAssertEqual(completion.content.title, "Timer Complete")
        XCTAssertEqual(completion.content.sound, .default)
    }

    @MainActor
    func testMediumTimerSchedulesPre1AndCompletionOnly() async throws {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        let timer = runningTimer(id: id, start: now, duration: 45)

        center.expectAdds(2)
        scheduler.scheduleCompletionNotification(for: timer)
        await center.awaitAdds()

        let identifiers = Set(center.addedRequests.map(\.identifier))
        XCTAssertEqual(identifiers, [
            "timer-pre1-\(id.uuidString.lowercased())",
            "timer-completion-\(id.uuidString.lowercased())",
        ])
    }

    @MainActor
    func testShortTimerSchedulesCompletionOnly() async throws {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        let timer = runningTimer(id: id, start: now, duration: 25)

        center.expectAdds(1)
        scheduler.scheduleCompletionNotification(for: timer)
        await center.awaitAdds()

        XCTAssertEqual(center.addedRequests.map(\.identifier), [
            "timer-completion-\(id.uuidString.lowercased())",
        ])
    }

    @MainActor
    func testResumeNearEndSkipsAllPastPreAlertsButKeepsCompletion() async {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        // A >60s timer resumed with only 3s left: end is now+3, so pre1 (end-10)
        // and pre2 (end-5) are both in the past.
        let timer = resumedTimer(id: id, duration: 75, remaining: 3)

        center.expectAdds(1)
        scheduler.scheduleCompletionNotification(for: timer)
        await center.awaitAdds()

        XCTAssertEqual(center.addedRequests.map(\.identifier), [
            "timer-completion-\(id.uuidString.lowercased())",
        ])
    }

    @MainActor
    func testResumeSkipsOnlyThePastPreAlertStage() async {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        // A >60s timer resumed with 7s left: pre1 (end-10 = now-3) is past, but
        // pre2 (end-5 = now+2) is still ahead, so pre2 + completion schedule.
        let timer = resumedTimer(id: id, duration: 75, remaining: 7)

        center.expectAdds(2)
        scheduler.scheduleCompletionNotification(for: timer)
        await center.awaitAdds()

        XCTAssertEqual(Set(center.addedRequests.map(\.identifier)), [
            "timer-pre2-\(id.uuidString.lowercased())",
            "timer-completion-\(id.uuidString.lowercased())",
        ])
    }

    @MainActor
    func testCancelRemovesEveryStageIdentifier() {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()

        scheduler.cancelCompletionNotification(forTimerID: id)

        XCTAssertEqual(center.removedIdentifiers, [
            [
                "timer-pre1-\(id.uuidString.lowercased())",
                "timer-pre2-\(id.uuidString.lowercased())",
                "timer-completion-\(id.uuidString.lowercased())",
            ],
        ])
    }

    @MainActor
    func testReschedulingCancelsPreviousStagesFirst() async {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        let timer = runningTimer(id: id, start: now, duration: 75)

        center.expectAdds(3)
        scheduler.scheduleCompletionNotification(for: timer)
        await center.awaitAdds()

        // A reschedule clears the pending stages before adding the new ones.
        XCTAssertEqual(center.removedIdentifiers.first, [
            "timer-pre1-\(id.uuidString.lowercased())",
            "timer-pre2-\(id.uuidString.lowercased())",
            "timer-completion-\(id.uuidString.lowercased())",
        ])
    }

    @MainActor
    func testRescheduleDoesNotLetObsoleteTaskDeleteNewerSchedule() async {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        // Schedule A for a 75s timer ending at now+75.
        let timerA = runningTimer(id: id, start: now, duration: 75)
        // Schedule B for the SAME timer, rescheduled (resumed) to end at now+90.
        let timerB = TimerState(
            id: id,
            duration: 75,
            startDate: now.addingTimeInterval(90 - 75),
            endDate: now.addingTimeInterval(90),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        // Hold A's adds so B can start while A is still in flight.
        center.gateEnabled = true
        scheduler.scheduleCompletionNotification(for: timerA)
        await Task.yield() // A reaches its first suspended add

        scheduler.scheduleCompletionNotification(for: timerB)
        await Task.yield() // B starts and waits on A

        // Let A's in-flight add finish, then let B add freely.
        center.gateEnabled = false
        center.releaseAllAdds()
        for _ in 0..<20 { await Task.yield() }

        let pre1 = "timer-pre1-\(id.uuidString.lowercased())"
        let pre2 = "timer-pre2-\(id.uuidString.lowercased())"
        let completion = "timer-completion-\(id.uuidString.lowercased())"

        // B's three valid requests remain — and exactly those (A did not delete
        // them and left nothing stale behind).
        XCTAssertEqual(Set(center.pendingIdentifiers), [pre1, pre2, completion])

        // The surviving requests are B's (end now+90), not A's (end now+75):
        // the obsolete task neither clobbered nor deleted the newer schedule.
        let expected = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now.addingTimeInterval(90)
        )
        let trigger = center.pendingByIdentifier[completion]?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents, expected)
    }

    @MainActor
    func testCancelDuringInFlightAddLeavesNoPendingRequests() async {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        let timer = runningTimer(id: id, start: now, duration: 75)

        // Make the async add suspend so a cancel can interleave before it
        // finishes (the schedule/cancel race PTIMER-73 must survive).
        center.gateEnabled = true
        scheduler.scheduleCompletionNotification(for: timer)
        await Task.yield() // let the scheduling task reach its suspended add

        scheduler.cancelCompletionNotification(forTimerID: id)

        center.gateEnabled = false
        center.releaseAllAdds() // let the suspended add(s) proceed
        for _ in 0..<10 { await Task.yield() }

        XCTAssertTrue(
            center.pendingIdentifiers.isEmpty,
            "a mid-flight cancel must leave no stale pending requests; got \(center.pendingIdentifiers)"
        )
    }

    @MainActor
    func testCancelDuringCompletionOnlyInFlightAddLeavesNoPendingRequests() async {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        let timer = runningTimer(id: id, start: now, duration: 25) // completion only

        // Hold the (only) completion add so a cancel can land while it is in
        // flight — there is no next loop iteration to catch the mismatch, so
        // only a post-add token check prevents a stale completion.
        center.gateEnabled = true
        scheduler.scheduleCompletionNotification(for: timer)
        await Task.yield() // task reaches the suspended completion add

        scheduler.cancelCompletionNotification(forTimerID: id)

        center.releaseAllAdds() // completion add finishes after the cancel
        for _ in 0..<10 { await Task.yield() }

        XCTAssertTrue(
            center.pendingIdentifiers.isEmpty,
            "a cancel during the only in-flight add must leave nothing; got \(center.pendingIdentifiers)"
        )
    }

    @MainActor
    func testCancelDuringFinalCompletionAddLeavesNoPendingRequests() async {
        let center = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: center)
        let id = UUID()
        let timer = runningTimer(id: id, start: now, duration: 75) // pre1, pre2, completion

        // Let pre1/pre2 add freely; hold only the final completion add.
        center.gateEnabled = true
        center.gateIdentifierSubstring = "completion"
        scheduler.scheduleCompletionNotification(for: timer)
        for _ in 0..<10 { await Task.yield() } // pre1+pre2 added; completion suspended

        scheduler.cancelCompletionNotification(forTimerID: id)

        center.releaseAllAdds() // final completion add finishes after the cancel
        for _ in 0..<10 { await Task.yield() }

        XCTAssertTrue(
            center.pendingIdentifiers.isEmpty,
            "a cancel during the final completion add must leave nothing; got \(center.pendingIdentifiers)"
        )
    }

    @MainActor
    private func makeScheduler(
        center: FakeUserNotificationCenter
    ) -> UserNotificationTimerCompletionScheduler {
        UserNotificationTimerCompletionScheduler(notificationCenter: center, dateProvider: { self.now })
    }

    private func runningTimer(id: UUID, start: Date, duration: TimeInterval) -> TimerState {
        TimerState(
            id: id,
            duration: duration,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )
    }

    /// A running timer whose original `duration` is preserved but whose end is
    /// `remaining` seconds from `now` — exactly the shape produced by resuming a
    /// long timer late, where pre-alert instants may already be in the past.
    private func resumedTimer(id: UUID, duration: TimeInterval, remaining: TimeInterval) -> TimerState {
        TimerState(
            id: id,
            duration: duration,
            startDate: now.addingTimeInterval(remaining - duration),
            endDate: now.addingTimeInterval(remaining),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )
    }
}

@MainActor
private final class FakeUserNotificationCenter: UserNotificationCentering {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []
    /// The request currently pending for each identifier (added minus removed),
    /// so a test can assert both *which* requests survive and *which schedule*
    /// they belong to (via their trigger).
    private(set) var pendingByIdentifier: [String: UNNotificationRequest] = [:]

    /// Identifiers currently pending. Empty means no stale request survived.
    var pendingIdentifiers: [String] { Array(pendingByIdentifier.keys) }

    /// When enabled, an `add` suspends until `releaseAllAdds()` so a test can
    /// interleave a cancel between schedule and the async add completing. When
    /// `gateIdentifierSubstring` is set, only adds whose identifier contains it
    /// suspend (so e.g. pre1/pre2 add freely and only the completion add is
    /// held), letting a test target the final in-flight add.
    var gateEnabled = false
    var gateIdentifierSubstring: String?
    private var gateContinuations: [CheckedContinuation<Void, Never>] = []

    private var addExpectation: XCTestExpectation?

    func expectAdds(_ count: Int) {
        let expectation = XCTestExpectation(description: "added \(count) notification requests")
        expectation.expectedFulfillmentCount = count
        addExpectation = expectation
    }

    func awaitAdds() async {
        guard let addExpectation else { return }
        await XCTWaiter().fulfillment(of: [addExpectation], timeout: 1)
    }

    func releaseAllAdds() {
        let continuations = gateContinuations
        gateContinuations = []
        continuations.forEach { $0.resume() }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }

    func add(_ request: UNNotificationRequest) async throws {
        let shouldGate = gateEnabled
            && (gateIdentifierSubstring.map { request.identifier.contains($0) } ?? true)
        if shouldGate {
            await withCheckedContinuation { continuation in
                gateContinuations.append(continuation)
            }
        }
        addedRequests.append(request)
        pendingByIdentifier[request.identifier] = request
        addExpectation?.fulfill()
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
        identifiers.forEach { pendingByIdentifier.removeValue(forKey: $0) }
    }
}
