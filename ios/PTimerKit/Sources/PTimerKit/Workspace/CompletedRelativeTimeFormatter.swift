// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public struct CompletedRelativeTimeFormatter {
    public init() {}
    public enum Style {
        case regular
        case compact
    }

    public func string(from completionDate: Date, relativeTo referenceDate: Date) -> String {
        string(from: completionDate, relativeTo: referenceDate, style: .regular)
    }

    public func compactString(from completionDate: Date, relativeTo referenceDate: Date) -> String {
        string(from: completionDate, relativeTo: referenceDate, style: .compact)
    }

    private func string(from completionDate: Date, relativeTo referenceDate: Date, style: Style) -> String {
        let elapsedSeconds = max(0, Int(referenceDate.timeIntervalSince(completionDate).rounded(.down)))

        switch elapsedSeconds {
        case ..<60:
            return String(localized: "just now")
        case ..<3_600:
            let minutes = elapsedSeconds / 60
            return style == .compact
                ? String(localized: "\(minutes)m ago")
                : String(localized: "\(minutes) min ago")
        case ..<86_400:
            let hours = elapsedSeconds / 3_600
            return style == .compact
                ? String(localized: "\(hours)h ago")
                : String(localized: "\(hours) hr ago")
        default:
            let days = elapsedSeconds / 86_400
            if style == .compact {
                return String(localized: "\(days)d ago")
            }
            return days == 1
                ? String(localized: "\(days) day ago")
                : String(localized: "\(days) days ago")
        }
    }

    public func nextRefreshDate(from completionDate: Date, relativeTo referenceDate: Date) -> Date? {
        let elapsedSeconds = max(0, referenceDate.timeIntervalSince(completionDate))
        let nextBoundary: TimeInterval

        switch elapsedSeconds {
        case ..<60:
            nextBoundary = 60
        case ..<3_600:
            nextBoundary = (floor(elapsedSeconds / 60) + 1) * 60
        case ..<86_400:
            nextBoundary = (floor(elapsedSeconds / 3_600) + 1) * 3_600
        default:
            nextBoundary = (floor(elapsedSeconds / 86_400) + 1) * 86_400
        }

        let refreshDate = completionDate.addingTimeInterval(nextBoundary)
        return refreshDate > referenceDate ? refreshDate : nil
    }

}
