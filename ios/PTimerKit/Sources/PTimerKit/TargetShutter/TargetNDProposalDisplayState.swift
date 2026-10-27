// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Transient presentation only; a displayed proposal never owns calculator inputs.
public struct TargetNDProposalDisplayState: Equatable, Sendable {
    public let requiredText: String
    public let detailText: String?
    public let warningText: String?
    public let canApply: Bool

    public init(requiredText: String, detailText: String? = nil, warningText: String? = nil, canApply: Bool = false) {
        self.requiredText = requiredText
        self.detailText = detailText
        self.warningText = warningText
        self.canApply = canApply
    }

    public var fullText: String {
        [requiredText, detailText, warningText].compactMap { $0 }.joined(separator: " · ")
    }
}
