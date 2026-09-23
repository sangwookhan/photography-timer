// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore

/// Platform-neutral direction for an assistive-technology adjustment
/// of one filter wheel (FILTER-A11Y-004).
public enum FilterWheelAdjustmentDirection: Sendable {
    case increment
    case decrement
}

/// Result of scanning a wheel's existing row order in one direction
/// (FILTER-A11Y-004): the first available row, the nearest rejected
/// candidate when unavailable rows prevented progress, or the plain
/// end of the wheel when no candidate lay in that direction at all.
public enum FilterWheelAdjustmentOutcome: Equatable, Sendable {
    case selection(FilterWheelSelection)
    case unavailable(FilterStackRejection)
    case boundary
}

/// Finds the next available row for VoiceOver without changing the
/// sighted picker's visible rows or touch rejection behavior.
public enum FilterWheelAccessibilityAdjustment {
    public static func outcome(
        from current: FilterWheelSelection,
        direction: FilterWheelAdjustmentDirection,
        options: [FilterWheelRowOption]
    ) -> FilterWheelAdjustmentOutcome {
        guard let currentIndex = options.firstIndex(where: { $0.selection == current }) else {
            return .unavailable(.unresolvedSelection)
        }

        let step = direction == .increment ? 1 : -1
        var index = currentIndex + step
        var firstRejection: FilterStackRejection?

        while options.indices.contains(index) {
            let option = options[index]
            if option.isAvailable {
                return .selection(option.selection)
            }
            if firstRejection == nil {
                firstRejection = option.unavailability
            }
            index += step
        }

        guard let firstRejection else {
            return .boundary
        }
        return .unavailable(firstRejection)
    }
}
