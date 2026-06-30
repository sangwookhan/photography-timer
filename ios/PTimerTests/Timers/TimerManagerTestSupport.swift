// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

@MainActor
final class CompletionAlertSpy: TimerCompletionAlerting {
    private(set) var events: [TimerCompletionEvent] = []

    func handleTimerCompletion(_ event: TimerCompletionEvent) {
        events.append(event)
    }
}

@MainActor
final class CompletionFeedbackSpy: TimerCompletionFeedbackPlaying {
    private(set) var playCount = 0
    private(set) var lastTimerID: UUID?

    func playCompletionFeedback(for timerID: UUID) {
        playCount += 1
        lastTimerID = timerID
    }
}

@MainActor
final class AlarmAudioPlayerSpy: TimerAlarmAudioPlaying {
    private(set) var playCount = 0
    private(set) var stopCount = 0
    private(set) var lastTimerID: UUID?

    func playCompletionAlarm(for timerID: UUID) {
        playCount += 1
        lastTimerID = timerID
    }

    func stop() {
        stopCount += 1
    }
}

struct ScheduledTimerNotification: Equatable {
    let timerID: UUID
    let endDate: Date
    let status: TimerStatus
}

@MainActor
final class CompletionNotificationSchedulerSpy: TimerCompletionNotificationScheduling {
    private(set) var authorizationRequestCount = 0
    private(set) var scheduledTimers: [ScheduledTimerNotification] = []
    private(set) var canceledTimerIDs: [UUID] = []

    func requestAuthorizationIfNeeded() {
        authorizationRequestCount += 1
    }

    func scheduleCompletionNotification(for timer: TimerState) {
        scheduledTimers.append(
            ScheduledTimerNotification(
                timerID: timer.id,
                endDate: timer.endDate ?? .distantPast,
                status: timer.status
            )
        )
    }

    func cancelCompletionNotification(forTimerID timerID: UUID) {
        canceledTimerIDs.append(timerID)
    }

    func resetHistory() {
        authorizationRequestCount = 0
        scheduledTimers = []
        canceledTimerIDs = []
    }
}

final class InMemoryTimerPersistenceStore: TimerPersistenceStoring {
    private(set) var snapshot: PersistentTimerCollectionSnapshot?
    private(set) var loadCallCount = 0

    func loadSnapshot() -> PersistentTimerCollectionSnapshot? {
        loadCallCount += 1
        return snapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}

extension XCTestCase {
    func tryUnwrapTimer(
        withID id: UUID,
        from timers: [TimerState],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> TimerState {
        guard let timer = timers.first(where: { $0.id == id }) else {
            XCTFail("Expected timer \(id) to exist", file: file, line: line)
            return TimerState(
                id: id,
                duration: 0,
                startDate: .distantPast,
                endDate: nil,
                pausedRemainingTime: 0,
                pausedAt: nil,
                status: .paused
            )
        }

        return timer
    }
}
