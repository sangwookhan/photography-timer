// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum RequiredNDResult: Equatable, Sendable {
    case value(stops: Double, beyondSourceRange: Bool)
    case unavailable(Failure)

    public enum Failure: Equatable, Sendable {
        case invalidInput
        case noQuantifiedInverse
        case multipleSolutions
        case numericalFailure
        case negativeAttenuation
    }
}
