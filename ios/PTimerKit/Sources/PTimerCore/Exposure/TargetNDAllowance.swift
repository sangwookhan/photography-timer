// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum TargetNDMedium: String, Codable, CaseIterable, Sendable {
    case negative, positive, digital
}

public enum TargetNDAllowance: String, Codable, CaseIterable, Sendable {
    case standard, extended

    public func interval(for medium: TargetNDMedium) -> ClosedRange<Double> {
        switch (medium, self) {
        case (.negative, .standard): return -0.5...1
        case (.negative, .extended): return -0.5...2
        case (.positive, .standard): return (-1.0 / 3)...(1.0 / 3)
        case (.positive, .extended): return -0.5...0.5
        case (.digital, .standard): return -1...0
        case (.digital, .extended): return -2...0
        }
    }
}
