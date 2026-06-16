import Combine
import Foundation
import PTimerCore
import PTimerKit

/// Package-safe, **manual-tick** `TimerManaging` harness backed by the real,
/// platform-neutral `TimerRuntime`. This is NOT an app `TimerManager`
/// replacement: it has no RunLoop, so time advances only when a test calls
/// `tick(now:)` (or supplies a moving `dateProvider`) — which is exactly what
/// makes lifecycle tests deterministic off-simulator.
///
/// The app's concrete `TimerManager` is a thin OS wrapper whose
/// `start/pause/resume/tick/reconcile/remove` are 1:1 delegations to
/// `TimerRuntime`; this support type provides the same runtime semantics
/// (including `tick(now:)`) without the RunLoop / UIKit / UserNotifications
/// surface, so ViewModel suites that drive real tick/pause/resume/complete
/// behaviour run via `swift test`. Use this (not `FakeTimerManaging`) whenever
/// a test asserts timer lifecycle.
///
/// The initializer mirrors `TimerManager.init` exactly (the ignored
/// `tickInterval` included) so relocating an app-hosted suite is a pure
/// `TimerManager(` -> `RuntimeBackedTimerManaging(` rename. Collaborators
/// (alert / notification / persistence) pass straight through so existing
/// spies keep working.
@MainActor
final class RuntimeBackedTimerManaging: TimerManaging {
    private let runtime: TimerRuntime

    var timers: [TimerState] { runtime.timers }
    var timersPublisher: AnyPublisher<[TimerState], Never> { runtime.$timers.eraseToAnyPublisher() }
    var currentDate: Date { runtime.currentDate }

    init(
        tickInterval: TimeInterval = 0.1,
        dateProvider: @escaping () -> Date = Date.init,
        completionAlertService: TimerCompletionAlerting = NoOpTimerCompletionAlertService(),
        completionNotificationScheduler: TimerCompletionNotificationScheduling = NoOpTimerCompletionScheduler(),
        persistenceStore: TimerPersistenceStoring = NoOpTimerPersistenceStore()
    ) {
        _ = tickInterval
        runtime = TimerRuntime(
            dateProvider: dateProvider,
            completionAlertService: completionAlertService,
            completionNotificationScheduler: completionNotificationScheduler,
            persistenceStore: persistenceStore
        )
    }

    @discardableResult
    func start(id: UUID, duration: TimeInterval) -> UUID? {
        runtime.start(id: id, duration: duration)
    }

    func pause(id: UUID) { runtime.pause(id: id) }
    func resume(id: UUID) { runtime.resume(id: id) }
    func cancel(id: UUID) { runtime.cancel(id: id) }
    func remove(id: UUID) { runtime.remove(id: id) }
    func removeCompletedTimers() { runtime.removeCompletedTimers() }
    func reconcile(now: Date? = nil) { runtime.reconcile(now: now) }
    func tick(now: Date? = nil) { runtime.tick(now: now) }
}
