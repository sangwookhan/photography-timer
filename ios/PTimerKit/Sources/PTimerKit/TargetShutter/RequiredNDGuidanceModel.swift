// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
import Combine
import Foundation
import PTimerCore

/// Owns transient manual-Base guidance through touch and inertia. Final
/// commitment starts restoration; a renderer completion ends its crossfade.
@MainActor
public final class RequiredNDGuidanceModel: ObservableObject {
    public enum Phase: Equatable {
        case ordinary
        case tracking
        case crossfading
    }

    public static let crossfadeDuration: TimeInterval = 0.5
    @Published public private(set) var result: RequiredNDResult?
    @Published public private(set) var phase: Phase = .ordinary
    public private(set) var generation = 0
    private var isTouchActive = false
    private var target: Double?
    private var profile: ReciprocityProfile?

    public init() {}

    public func begin(base: Double, target: Double, profile: ReciprocityProfile?) {
        invalidate()
        isTouchActive = true
        self.target = target
        self.profile = profile
        phase = .tracking
        update(base: base)
    }

    public func update(base: Double) {
        guard phase == .tracking, let target else { return }
        result = RequiredNDEvaluator().evaluate(baseSeconds: base, targetSeconds: target, profile: profile)
    }

    public func release() {
        isTouchActive = false
    }

    public func settle(base: Double) {
        guard phase == .tracking, !isTouchActive else { return }
        update(base: base)
        phase = .crossfading
    }

    public func complete(_ completedPhase: Phase, token: Int) {
        guard token == generation, phase == completedPhase else { return }
        guard completedPhase == .crossfading else { return }
        result = nil
        target = nil
        profile = nil
        phase = .ordinary
    }

    public func invalidate() {
        generation += 1
        isTouchActive = false
        target = nil
        profile = nil
        result = nil
        phase = .ordinary
    }
}
