// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Transient presentation only; a displayed proposal never owns calculator inputs.
public struct TargetNDProposalDisplayState: Equatable, Sendable {
    public let requiredText: String
    public let detailText: String?
    public let warningText: String?
    public let canApply: Bool
    public let isLive: Bool
    public let isNoCombination: Bool
    public let isApplied: Bool
    public let candidateTotalText: String?
    public let actionText: String?
    public let compactCombination: String?
    public let signedErrorText: String?

    public init(requiredText: String, detailText: String? = nil, warningText: String? = nil, canApply: Bool = false, isLive: Bool = false, isNoCombination: Bool = false, isApplied: Bool = false, compactCombination: String? = nil, signedErrorText: String? = nil, candidateTotalText: String? = nil, actionText: String? = nil) {
        self.candidateTotalText = candidateTotalText
        self.actionText = actionText
        self.requiredText = requiredText
        self.detailText = detailText
        self.warningText = warningText
        self.canApply = canApply
        self.isLive = isLive
        self.isNoCombination = isNoCombination
        self.isApplied = isApplied
        self.compactCombination = compactCombination
        self.signedErrorText = signedErrorText
    }

    public var fullText: String {
        [requiredText, detailText, warningText].compactMap { $0 }.joined(separator: " · ")
    }
}
