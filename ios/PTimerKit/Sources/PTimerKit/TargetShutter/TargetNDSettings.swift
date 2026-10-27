// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public struct TargetNDSettings: Equatable, Sendable {
    public var isEnabled = true
    public var negative = TargetNDAllowance.standard
    public var positive = TargetNDAllowance.standard
    public var digital = TargetNDAllowance.standard

    public init() {}

    public subscript(medium: TargetNDMedium) -> TargetNDAllowance {
        get {
            switch medium {
            case .negative: return negative
            case .positive: return positive
            case .digital: return digital
            }
        }
        set {
            switch medium {
            case .negative: negative = newValue
            case .positive: positive = newValue
            case .digital: digital = newValue
            }
        }
    }
}
