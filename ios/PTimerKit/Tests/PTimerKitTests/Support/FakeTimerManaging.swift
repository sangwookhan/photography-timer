import Combine
import Foundation
import PTimerCore
import PTimerKit

/// Package-safe `TimerManaging` **metadata/composition stub** for
/// off-simulator ViewModel tests. The app's concrete `TimerManager`
/// (RunLoop/OS) stays in the app target; these suites only need *a*
/// conforming dependency, not a runtime.
///
/// It records started timers as `.running` against a fixed clock and
/// republishes the collection, so suites that start a timer and assert its
/// composed metadata (duration, name, basis, camera slot, source, identity
/// snapshot) run off-simulator. It deliberately does NOT advance time.
///
/// Use this ONLY for metadata/composition. For deterministic
/// tick/pause/resume/complete *lifecycle* behaviour off-simulator, use
/// `RuntimeBackedTimerManaging` (a real `TimerRuntime` driven by manual
/// ticks) — not this stub.
@MainActor
final class FakeTimerManaging: TimerManaging {
    private(set) var timers: [TimerState] = []
    private let subject = CurrentValueSubject<[TimerState], Never>([])
    var timersPublisher: AnyPublisher<[TimerState], Never> { subject.eraseToAnyPublisher() }
    let currentDate: Date

    init(currentDate: Date = Date(timeIntervalSince1970: 100)) {
        self.currentDate = currentDate
    }

    @discardableResult
    func start(id: UUID, duration: TimeInterval) -> UUID? {
        timers.append(
            TimerState(
                id: id,
                duration: duration,
                startDate: currentDate,
                endDate: currentDate.addingTimeInterval(duration),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running
            )
        )
        subject.send(timers)
        return id
    }

    // No-ops: this stub does not model the timer lifecycle. A test that
    // asserts pause/resume (or tick/completion) behaviour must use
    // `RuntimeBackedTimerManaging`, not this type.
    func pause(id: UUID) {}
    func resume(id: UUID) {}

    func remove(id: UUID) {
        timers.removeAll { $0.id == id }
        subject.send(timers)
    }

    func removeCompletedTimers() {
        timers.removeAll { $0.status(at: currentDate) == .completed }
        subject.send(timers)
    }

    // No-op: reconciliation is a runtime concern — see `RuntimeBackedTimerManaging`.
    func reconcile(now: Date?) {}
}
