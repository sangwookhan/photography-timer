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
            return "just now"
        case ..<3_600:
            let minutes = elapsedSeconds / 60
            return pluralizedAgo(value: minutes, regularUnit: "min", compactUnit: "m", style: style)
        case ..<86_400:
            let hours = elapsedSeconds / 3_600
            return pluralizedAgo(value: hours, regularUnit: "hr", compactUnit: "h", style: style)
        default:
            let days = elapsedSeconds / 86_400
            return pluralizedAgo(value: days, regularUnit: "day", compactUnit: "d", style: style)
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

    private func pluralizedAgo(
        value: Int,
        regularUnit: String,
        compactUnit: String,
        style: Style
    ) -> String {
        switch style {
        case .regular:
            let unit: String
            switch regularUnit {
            case "day":
                unit = value == 1 ? "day" : "days"
            default:
                unit = regularUnit
            }
            return "\(value) \(unit) ago"
        case .compact:
            return "\(value)\(compactUnit) ago"
        }
    }
}
