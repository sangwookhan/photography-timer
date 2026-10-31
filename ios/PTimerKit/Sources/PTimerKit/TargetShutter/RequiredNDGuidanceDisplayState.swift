// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
import Foundation
import PTimerCore

public struct RequiredNDGuidanceDisplayState: Equatable {
    public let valueText: String
    public let reason: String?
    public let compactReason: String?
    public let isWarning: Bool
    public let spokenValue: String

    public init(result: RequiredNDResult) {
        switch result {
        case let .value(stops, beyond):
            let rounded = (stops * 10).rounded() / 10
            valueText = rounded == rounded.rounded()
                ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
            reason = beyond ? String(localized: "required-nd-beyond-source-range") : nil
            compactReason = beyond ? String(localized: "Out of range") : nil
            isWarning = beyond
            spokenValue = String(localized: "Required ND \(valueText) stops")
        case let .unavailable(failure):
            valueText = "—"
            isWarning = true
            spokenValue = String(localized: "Required ND unavailable")
            switch failure {
            case .negativeAttenuation:
                reason = String(localized: "Attenuation cannot reach Target")
                compactReason = String(localized: "Target too short")
            case .noQuantifiedInverse:
                reason = String(localized: "No quantified inverse")
                compactReason = String(localized: "No inverse")
            case .multipleSolutions:
                reason = String(localized: "Multiple inverse solutions")
                compactReason = String(localized: "Multiple inverses")
            case .invalidInput:
                reason = String(localized: "Invalid exposure input")
                compactReason = String(localized: "Invalid input")
            case .numericalFailure:
                reason = String(localized: "Inverse calculation failed")
                compactReason = String(localized: "Calculation failed")
            }
        }
    }

    public var label: String { String(localized: "Required ND") }
    public var unit: String { valueText == "—" ? "" : String(localized: "stops") }
}
