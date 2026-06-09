import Combine
import Foundation
import PTimerCore
import PTimerKit

/// Package-safe `TimerManaging` for off-simulator ViewModel tests. The app's
/// concrete `TimerManager` (RunLoop/OS) stays in the app target; film-mode
/// ViewModel suites only need *a* conforming dependency, not real ticking, so
/// this fake reports no timers and a fixed clock.
@MainActor
final class FakeTimerManaging: TimerManaging {
    var timers: [TimerState] = []
    private let subject = CurrentValueSubject<[TimerState], Never>([])
    var timersPublisher: AnyPublisher<[TimerState], Never> { subject.eraseToAnyPublisher() }
    let currentDate: Date

    init(currentDate: Date = Date(timeIntervalSince1970: 100)) {
        self.currentDate = currentDate
    }

    @discardableResult func start(id: UUID, duration: TimeInterval) -> UUID? { nil }
    func pause(id: UUID) {}
    func resume(id: UUID) {}
    func remove(id: UUID) {}
    func removeCompletedTimers() {}
    func reconcile(now: Date?) {}
}
