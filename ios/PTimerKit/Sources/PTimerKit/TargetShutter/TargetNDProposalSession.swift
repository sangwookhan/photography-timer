// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public enum TargetNDApplyFailure: Error, Equatable {
    case expired, stale, unavailable, duplicate
}

/// Deterministic transient lifecycle. The platform supplies monotonic time
/// and start/preview/final-commit events; this value never owns a wall-clock
/// timer, persists a proposal, or changes calculator inputs itself.
public struct TargetNDProposalSession {
    public enum Phase: Equatable { case idle, interacting, evaluating, result, applied }
    public private(set) var phase = Phase.idle
    public private(set) var generation: UInt64 = 0
    public private(set) var input: TargetNDProposalInput?
    public private(set) var result: TargetNDSelectionResult?
    public private(set) var expiresAt: TimeInterval?
    public private(set) var isActionFocused = false
    private var remainingLifetime: TimeInterval = 5

    public init() {}

    @discardableResult
    public mutating func begin(_ input: TargetNDProposalInput) -> UInt64 {
        invalidate()
        guard input.settings.isEnabled else { return generation }
        self.input = input
        phase = .interacting
        return generation
    }

    public mutating func preview(_ input: TargetNDProposalInput) {
        guard phase == .interacting, input.settings.isEnabled else { return }
        self.input = input
    }

    /// A same-value gesture still reaches this event. Quiet filter controls
    /// are required; an input observer alone cannot start an offer.
    @discardableResult
    public mutating func settle(_ input: TargetNDProposalInput, filtersAreQuiet: Bool) -> UInt64? {
        guard phase == .interacting, input.settings.isEnabled, filtersAreQuiet else { return nil }
        self.input = input
        phase = .evaluating
        return generation
    }

    @discardableResult
    public mutating func complete(_ result: TargetNDSelectionResult, input: TargetNDProposalInput, generation: UInt64, now: TimeInterval) -> Bool {
        guard phase == .evaluating, generation == self.generation, input == self.input else { return false }
        self.result = result
        phase = .result
        if case .unavailable(.noCombination) = result {
            remainingLifetime = 2
        } else {
            remainingLifetime = 5
        }
        expiresAt = now + remainingLifetime
        return true
    }

    public mutating func invalidate() {
        generation &+= 1
        input = nil
        result = nil
        phase = .idle
        expiresAt = nil
        isActionFocused = false
        remainingLifetime = 5
    }

    /// A timeout carries the generation it was scheduled for. Old timeouts
    /// and late worker results cannot dismiss or recreate a later proposal.
    public mutating func expire(generation: UInt64, now: TimeInterval) {
        guard generation == self.generation, !isActionFocused,
              let deadline = expiresAt, now >= deadline else { return }
        invalidate()
    }

    public mutating func focusAction(_ focused: Bool, now: TimeInterval) {
        expire(generation: generation, now: now)
        guard phase == .result, focused != isActionFocused,
              case .available(_, let candidate) = result, !candidate.isCurrent else { return }
        if focused {
            remainingLifetime = max(0, (expiresAt ?? now) - now)
            expiresAt = nil
        } else { expiresAt = now + remainingLifetime }
        isActionFocused = focused
    }

    /// Returns the replacement value exactly once. The caller commits it in
    /// one calculator transaction only after this current-input check.
    public mutating func consume(current: TargetNDProposalInput, now: TimeInterval) -> Result<FilterStack, TargetNDApplyFailure> {
        if phase == .applied { return .failure(.duplicate) }
        let token = generation
        expire(generation: token, now: now)
        guard phase == .result else { return .failure(.expired) }
        guard input == current, current.settings.isEnabled else {
            invalidate()
            return .failure(.stale)
        }
        guard case .available(_, let candidate) = result, !candidate.isCurrent,
              current.evaluate() == result else {
            invalidate()
            return .failure(.unavailable)
        }
        phase = .applied
        result = nil
        isActionFocused = false
        expiresAt = now + 1.5
        return .success(candidate.stack)
    }
}
