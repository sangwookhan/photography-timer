// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// Runtime owner of the transient session. The calculator owns inputs; the
/// platform supplies genuine user start/live/final-snap events. Scheduling is
/// injected so races are exercised without waiting five wall-clock seconds.
@MainActor
public final class TargetNDProposalModel: ObservableObject {
    public typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    @Published public private(set) var session = TargetNDProposalSession()
    public typealias Evaluate = (TargetNDProposalInput, @escaping @MainActor (TargetNDSelectionResult) -> Void) -> () -> Void
    private let evaluate: Evaluate
    private var cancelEvaluation: (() -> Void)?
    private let now: () -> TimeInterval
    private let schedule: Schedule
    private var cancelExpiry: (() -> Void)?
    private var context: TargetNDProposalInput?

    public init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                schedule: Schedule? = nil, evaluate: Evaluate? = nil) {
        self.evaluate = evaluate ?? { input, complete in
            let worker = Task.detached(priority: .userInitiated) { input.evaluate() }
            let delivery = Task { @MainActor in
                let result = await worker.value
                guard !Task.isCancelled else { return }
                complete(result)
            }
            return { worker.cancel(); delivery.cancel() }
        }
        self.now = now
        self.schedule = schedule ?? { delay, action in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000)) } catch { return }
                guard !Task.isCancelled else { return }
                action()
            }
            return { task.cancel() }
        }
    }

    public func begin(_ input: TargetNDProposalInput?) {
        invalidate()
        guard let input else { return }
        context = input
        session.begin(input)
    }

    public func preview(base: Double) {
        guard let context else { return }
        session.preview(context.replacingBase(base))
    }

    /// External changes never automatically open another offer. This also
    /// invalidates a same-ID inventory/profile edit during an ongoing drag.
    public func reconcile(_ current: TargetNDProposalInput?) {
        guard context != current else { return }
        invalidate()
    }

    public func settle(_ current: TargetNDProposalInput?, filtersAreQuiet: Bool) {
        guard let current, let context,
              context.replacingBase(current.baseSeconds) == current else { invalidate(); return }
        self.context = current
        guard let token = session.settle(current, filtersAreQuiet: filtersAreQuiet) else {
            invalidate()
            return
        }
        cancelEvaluation = evaluate(current) { [weak self] result in
            guard let self, self.context == current,
                  self.session.complete(result, input: current, generation: token, now: self.now()) else { return }
            self.scheduleExpiry()
        }
    }

    public func focusAction(_ focused: Bool, generation: UInt64? = nil) {
        if let generation, generation != session.generation { return }
        session.focusAction(focused, now: now())
        scheduleExpiry()
    }

    public func apply(current: TargetNDProposalInput?, filtersAreQuiet: Bool,
                      commit: (TargetNDProposalInput, TargetNDSelectionResult) -> Result<Void, TargetNDApplyFailure>) -> Result<Void, TargetNDApplyFailure> {
        guard let current, filtersAreQuiet else { invalidate(); return .failure(.stale) }
        let result = session.result
        switch session.consume(current: current, now: now()) {
        case .failure(let reason): return .failure(reason)
        case .success:
            guard let result else { return .failure(.unavailable) }
            let outcome = commit(current, result)
            if case .failure = outcome { invalidate() } else { scheduleExpiry() }
            return outcome
        }
    }

    public func invalidate() {
        cancelEvaluation?()
        cancelEvaluation = nil
        cancelExpiry?()
        cancelExpiry = nil
        context = nil
        session.invalidate()
    }

    private func scheduleExpiry() {
        cancelExpiry?()
        cancelExpiry = nil
        guard let deadline = session.expiresAt else { return }
        let token = session.generation
        cancelExpiry = schedule(max(0, deadline - now())) { [weak self] in
            guard let self else { return }
            self.session.expire(generation: token, now: self.now())
        }
    }
}
