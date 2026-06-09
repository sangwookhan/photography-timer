import Combine
import Foundation
import PTimerCore

@MainActor
public final class LockScreenTimerCoordinator {
    private let exposer: LockScreenTimerTargetExposing
    private var activeTarget: LockScreenTimerTarget?
    private var cancellable: AnyCancellable?

    public init(exposer: LockScreenTimerTargetExposing) {
        self.exposer = exposer
    }

    /// Subscribes to a publisher of `RunningTimerItem` updates and drives
    /// the lock-screen surface automatically. The coordinator owns the
    /// subscription for its lifetime; callers retain the coordinator so
    /// the subscription stays alive.
    public convenience init(
        exposer: LockScreenTimerTargetExposing,
        timersPublisher: AnyPublisher<[RunningTimerItem], Never>
    ) {
        self.init(exposer: exposer)
        self.cancellable = timersPublisher
            .sink { [weak self] timers in
                self?.sync(with: timers)
            }
    }

    public func sync(with timers: [RunningTimerItem]) {
        let nextTarget = Self.selectRepresentativeTarget(from: timers)

        guard nextTarget != activeTarget else {
            return
        }

        activeTarget = nextTarget

        if let nextTarget {
            exposer.expose(nextTarget)
        } else {
            exposer.clear()
        }
    }

    // Selection rule:
    // 1. Choose the running timer with the earliest endDate.
    // 2. If endDate is tied, prefer the existing workspace presentation order.
    // 3. If that is still tied, prefer the stable id order.
    public static func selectRepresentativeTarget(from timers: [RunningTimerItem]) -> LockScreenTimerTarget? {
        let eligibleTargets = eligibleRunningTimers(from: timers)

        guard let timer = eligibleTargets.first else {
            return nil
        }

        return LockScreenTimerTarget(
            representativeTimerID: timer.timer.id,
            representativeTimerName: timer.timer.name,
            representativeEndDate: timer.endDate,
            scheduledTargets: eligibleTargets.map {
                ScheduledTimerTarget(
                    timerID: $0.timer.id,
                    timerName: $0.timer.name,
                    endDate: $0.endDate
                )
            }
        )
    }

    private static func eligibleRunningTimers(from timers: [RunningTimerItem]) -> [EligibleRunningTimer] {
        timers
            .compactMap { timer in
                guard timer.status == .running, let endDate = timer.endDate else {
                    return nil
                }

                return EligibleRunningTimer(timer: timer, endDate: endDate)
            }
            .sorted(by: areInRepresentativeOrder(lhs:rhs:))
    }

    private static func areInRepresentativeOrder(
        lhs: EligibleRunningTimer,
        rhs: EligibleRunningTimer
    ) -> Bool {
        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }

        if TimerWorkspaceOrdering.areInPresentationOrder(lhs: lhs.timer, rhs: rhs.timer) {
            return true
        }

        if TimerWorkspaceOrdering.areInPresentationOrder(lhs: rhs.timer, rhs: lhs.timer) {
            return false
        }

        return lhs.timer.id.uuidString < rhs.timer.id.uuidString
    }
}

private struct EligibleRunningTimer {
    let timer: RunningTimerItem
    let endDate: Date
}
