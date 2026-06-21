// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

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
            representativeTimerName: lockScreenExposedName(for: timer.timer),
            representativeEndDate: timer.endDate,
            scheduledTargets: eligibleTargets.map {
                ScheduledTimerTarget(
                    timerID: $0.timer.id,
                    timerName: lockScreenExposedName(for: $0.timer),
                    endDate: $0.endDate
                )
            }
        )
    }

    /// Lock-screen-exposed timer name (PTIMER-171). Default-model
    /// timers keep `timer.name` byte-for-byte; a timer started from a
    /// non-default reciprocity model appends its captured label so the
    /// Live Activity / widget can distinguish e.g.
    /// `"Tri-X 400 - 20m · App formula"` from the default
    /// `"Tri-X 400 - 20m"`. Appended rather than inserted so the
    /// composer-owned name shapes are never parsed here.
    public static func lockScreenExposedName(for timer: RunningTimerItem) -> String {
        guard let label = timer.selectedModelLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else {
            return timer.name
        }
        return "\(timer.name) · \(label)"
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
