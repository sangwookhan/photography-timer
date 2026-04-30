import Foundation

@MainActor
final class LockScreenTimerTargetCoordinator {
    private let exposer: LockScreenTimerTargetExposing
    private var activeTarget: LockScreenTimerTarget?

    init(exposer: LockScreenTimerTargetExposing) {
        self.exposer = exposer
    }

    func sync(with timers: [RunningTimerItem]) {
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

    // PTIMER-69 selection rule:
    // 1. Choose the running timer with the earliest endDate.
    // 2. If endDate is tied, prefer the existing workspace presentation order.
    // 3. If that is still tied, prefer the stable id order.
    static func selectRepresentativeTarget(from timers: [RunningTimerItem]) -> LockScreenTimerTarget? {
        let eligibleTargets = eligibleRunningTimers(from: timers)

        guard let timer = eligibleTargets.first else {
            return nil
        }

        return LockScreenTimerTarget(
            representativeTimerID: timer.timer.id,
            representativeTimerName: timer.timer.name,
            representativeEndDate: timer.endDate,
            scheduledTargets: eligibleTargets.map {
                LockScreenTimerScheduledTarget(
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

    init(timer: RunningTimerItem, endDate: Date) {
        self.timer = timer
        self.endDate = endDate
    }
}
