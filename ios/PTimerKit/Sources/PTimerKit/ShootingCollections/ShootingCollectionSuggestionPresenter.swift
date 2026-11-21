// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public enum ShootingCollectionSuggestionPresenter {
    public static func offsetText(start: Date, anchor: Date) -> String {
        let difference = start.timeIntervalSince(anchor).rounded()
        guard difference != 0 else { return String(localized: "Same start time") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .short
        formatter.zeroFormattingBehavior = .dropAll
        let duration = formatter.string(from: abs(difference))
            ?? ExposureCalculator().formatExtendedClock(abs(difference))
        return "\(difference < 0 ? "−" : "+")\(duration)"
    }
}
