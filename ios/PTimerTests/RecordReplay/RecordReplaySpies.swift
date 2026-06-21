// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit
import PTimerCore
@testable import PTimer

// Trace-recording implementations of the collaborator protocols
// the ViewModel and TimerManager talk to. Each spy forwards the
// observed call (and a deterministic textual representation of its
// payload) into the supplied `RecordReplayRecorder`.
//
// Spies do **not** add fake business behavior — when a protocol
// method has a non-trivial return type (e.g. `loadSnapshot()` →
// `PersistentTimerCollectionSnapshot?`), the spy returns `nil` /
// the empty default the corresponding `NoOp*` implementation would
// have returned. If a future scenario needs a primed return value,
// extend the spy explicitly rather than letting hidden defaults
// drift in.

// MARK: - Date rendering

/// Canonical date rendering for trace payloads. Real timestamps
/// would change every run, so we express dates as
/// `+<delta>s/<referenceDate>` where the reference is the harness's
/// reference date.
enum RecordReplayDateRendering {
    static func render(_ date: Date?, referenceDate: Date) -> String {
        guard let date else { return "nil" }
        let delta = date.timeIntervalSince(referenceDate)
        return String(format: "+%.3fs", delta)
    }
}

// MARK: - LockScreen exposer spy

@MainActor
final class RecordingLockScreenExposer: LockScreenTimerTargetExposing {
    private let recorder: RecordReplayRecorder
    private let prefix: String
    private let referenceDate: Date

    init(
        recorder: RecordReplayRecorder,
        prefix: String = "exposer",
        referenceDate: Date
    ) {
        self.recorder = recorder
        self.prefix = prefix
        self.referenceDate = referenceDate
    }

    func expose(_ target: LockScreenTimerTarget) {
        // Render the target with reference-date-relative timestamps so
        // the trace is reproducible across runs. Field order is fixed
        // for byte-stable diffs.
        let scheduled = target.scheduledTargets
            .map { entry in
                "\(entry.timerID.uuidString)|\(entry.timerName)|\(RecordReplayDateRendering.render(entry.endDate, referenceDate: referenceDate))"
            }
            .joined(separator: ", ")
        recorder.record(
            "\(prefix).expose",
            fields: [
                OrderedField(key: "representativeTimerID", value: target.representativeTimerID.uuidString),
                OrderedField(key: "representativeTimerName", value: target.representativeTimerName),
                OrderedField(
                    key: "representativeEndDate",
                    value: RecordReplayDateRendering.render(target.representativeEndDate, referenceDate: referenceDate)
                ),
                OrderedField(key: "scheduledTargets", value: scheduled),
            ]
        )
    }

    func clear() {
        recorder.recordSignal("\(prefix).clear")
    }
}

// MARK: - Timer persistence spy

@MainActor
final class RecordingTimerPersistenceStore: TimerPersistenceStoring {
    private let recorder: RecordReplayRecorder
    private let prefix: String
    private let referenceDate: Date

    init(
        recorder: RecordReplayRecorder,
        prefix: String = "timer.persistence",
        referenceDate: Date
    ) {
        self.recorder = recorder
        self.prefix = prefix
        self.referenceDate = referenceDate
    }

    // The spy mirrors `NoOpTimerPersistenceStore.loadSnapshot` semantics:
    // returning `nil` keeps the TimerManager's restore path on the empty
    // branch. Tests that need a primed snapshot should construct a
    // dedicated spy variant rather than poking state in here.
    func loadSnapshot() -> PersistentTimerCollectionSnapshot? {
        recorder.recordSignal("\(prefix).load")
        return nil
    }

    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {
        let summaries = snapshot.timers.map { entry -> String in
            let endDate = RecordReplayDateRendering.render(entry.expectedCompletionAt, referenceDate: referenceDate)
            return "\(entry.id.uuidString)|status=\(entry.status.rawValue)|duration=\(entry.duration)|endDate=\(endDate)"
        }
        recorder.record(
            "\(prefix).save",
            fields: [
                OrderedField(key: "timers", value: "[" + summaries.joined(separator: "; ") + "]")
            ]
        )
    }

    func clearSnapshot() {
        recorder.recordSignal("\(prefix).clear")
    }
}

// MARK: - Timer completion notification scheduler spy

@MainActor
final class RecordingTimerCompletionScheduler: TimerCompletionNotificationScheduling {
    private let recorder: RecordReplayRecorder
    private let prefix: String
    private let referenceDate: Date

    init(
        recorder: RecordReplayRecorder,
        prefix: String = "timer.notification",
        referenceDate: Date
    ) {
        self.recorder = recorder
        self.prefix = prefix
        self.referenceDate = referenceDate
    }

    func requestAuthorizationIfNeeded() {
        recorder.recordSignal("\(prefix).requestAuthorization")
    }

    func scheduleCompletionNotification(for timer: TimerState) {
        recorder.record(
            "\(prefix).schedule",
            fields: [
                OrderedField(key: "id", value: timer.id.uuidString),
                OrderedField(key: "duration", value: "\(timer.duration)"),
                OrderedField(
                    key: "endDate",
                    value: RecordReplayDateRendering.render(timer.endDate, referenceDate: referenceDate)
                ),
            ]
        )
    }

    func cancelCompletionNotification(forTimerID timerID: UUID) {
        recorder.record(
            "\(prefix).cancel",
            fields: [OrderedField(key: "id", value: timerID.uuidString)]
        )
    }
}
