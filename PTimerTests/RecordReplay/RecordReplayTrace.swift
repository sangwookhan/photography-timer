import Foundation

/// One event observed during a record-replay scenario. `step` is a
/// monotonic integer assigned by the recorder, not a wall-clock or
/// elapsed timestamp, so traces stay deterministic across runs.
///
/// `kind` is a dotted string identifier (e.g. `"timer.start"`,
/// `"exposer.expose"`). `payload` is a canonical multi-line text
/// rendering of the event's input — `Swift.dump` for v1. The same
/// rationale that justified `Swift.dump` for `DisplayStateSnapshot`
/// applies here: stable per Swift version, diff-friendly, no extra
/// dependency.
struct RecordReplayEvent: Equatable {
    let step: Int
    let kind: String
    let payload: String
}

/// Ordered key/value payload for an event. We avoid Swift
/// dictionaries here because their iteration order is hash-stable
/// only within a process, not across runs — `Swift.dump` of
/// `[String: String]` therefore produces non-deterministic output.
/// `OrderedField` keeps spies in control of payload field order.
struct OrderedField: Equatable {
    let key: String
    let value: String
}

/// Accumulator for events captured during a record-replay scenario.
/// Thread-unsafe by design — scenarios run on the main actor and the
/// ViewModel under test is `@MainActor` isolated, so all spies funnel
/// into the recorder from the same actor.
@MainActor
final class RecordReplayRecorder {
    /// Events captured so far, in record order.
    private(set) var events: [RecordReplayEvent] = []

    private var nextStep = 0

    /// Records an ordered field list against the given `kind`. Field
    /// order is preserved exactly so the trace stays byte-for-byte
    /// reproducible.
    func record(_ kind: String, fields: [OrderedField]) {
        let rendered = fields
            .map { "  \($0.key): \($0.value)" }
            .joined(separator: "\n")
        events.append(
            RecordReplayEvent(
                step: nextStep,
                kind: kind,
                payload: rendered
            )
        )
        nextStep += 1
    }

    /// Records a `kind`-only event (no payload). Useful for
    /// presence/absence assertions like `clear()` calls where the
    /// invocation itself is the signal.
    func recordSignal(_ kind: String) {
        events.append(
            RecordReplayEvent(
                step: nextStep,
                kind: kind,
                payload: ""
            )
        )
        nextStep += 1
    }

    /// Deterministic multi-line rendering of the trace. Each event
    /// becomes a block prefixed with `[step] kind`, and blocks are
    /// separated by a `---` line so diffs show event-level deltas
    /// cleanly.
    func renderTrace() -> String {
        events.map { event in
            if event.payload.isEmpty {
                return "[\(event.step)] \(event.kind)"
            }
            return "[\(event.step)] \(event.kind)\n\(event.payload)"
        }
        .joined(separator: "\n---\n")
    }
}
