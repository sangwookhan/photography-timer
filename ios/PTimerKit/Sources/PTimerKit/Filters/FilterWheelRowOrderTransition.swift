// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Presents a settled-order change of the wheel row as one coherent
/// whole-row transition (FILTER-STACK-005): the row shows the complete
/// previous arrangement, fades out, swaps to the complete new
/// arrangement, and fades back in. Wheel columns and labels never travel
/// through one another and no mixed intermediate order is ever
/// displayed. A newer committed order arriving mid-transition restarts
/// the transition toward that newest complete arrangement; adding or
/// removing a wheel replaces the displayed order at once so the
/// existing per-wheel insert and collapse transitions apply.
///
/// Pure value: the view owns the timing and renders `displayedOrder`.
public struct FilterWheelRowOrderTransition: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case settled
        /// The previous complete arrangement is fading out toward
        /// `target`.
        case fadingOut
        /// The newest complete arrangement is fading in.
        case fadingIn
    }

    /// What the view should do after an event.
    public enum Effect: Equatable, Sendable {
        case none
        /// Membership changed: render `displayedOrder` immediately.
        case replaceImmediately
        /// Start (or restart from the current opacity) the fade-out.
        case fadeOut
        /// Show `displayedOrder` and fade in.
        case fadeIn
    }

    /// Wheel ids in the order the row currently renders.
    public private(set) var displayedOrder: [Int]
    /// The newest committed order the row is transitioning toward.
    public private(set) var target: [Int]
    public private(set) var phase: Phase = .settled

    public init(order: [Int]) {
        displayedOrder = order
        target = order
    }

    /// The model's settled order changed.
    public mutating func orderChanged(to order: [Int]) -> Effect {
        target = order
        guard Set(order) == Set(displayedOrder), order.count == displayedOrder.count else {
            // A wheel was added or removed: no reorder transition.
            displayedOrder = order
            phase = .settled
            return .replaceImmediately
        }
        if order == displayedOrder {
            // Back to what is shown: nothing to transition toward.
            if phase == .fadingOut {
                phase = .fadingIn
                return .fadeIn
            }
            phase = .settled
            return .none
        }
        phase = .fadingOut
        return .fadeOut
    }

    /// The fade-out finished: swap to the newest complete arrangement.
    public mutating func fadeOutCompleted() -> Effect {
        guard phase == .fadingOut else { return .none }
        displayedOrder = target
        phase = .fadingIn
        return .fadeIn
    }

    /// The fade-in finished.
    public mutating func fadeInCompleted() {
        if phase == .fadingIn {
            phase = .settled
        }
    }
}
