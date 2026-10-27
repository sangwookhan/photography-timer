// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Immutable value captured at the event boundary. Equality covers both
/// identities and content, including an edited profile/inventory with the
/// same IDs. Camera identity prevents proposals leaking across cameras.
public struct TargetNDProposalInput: Equatable {
    public let cameraID: String
    public let baseSeconds: Double
    public let targetSeconds: Double
    public let profile: ReciprocityProfile?
    public let inventory: FilterInventory
    public let selectedSets: [FilterSetID]
    public let current: FilterStack
    public let settings: TargetNDSettings
    public let medium: TargetNDMedium
    public let filmID: String?
    public let filmColor: FilmColor?

    public init(cameraID: String, baseSeconds: Double, targetSeconds: Double, profile: ReciprocityProfile?, inventory: FilterInventory, selectedSets: [FilterSetID], current: FilterStack, settings: TargetNDSettings, medium: TargetNDMedium, filmID: String? = nil, filmColor: FilmColor? = nil) {
        self.cameraID = cameraID
        self.baseSeconds = baseSeconds
        self.targetSeconds = targetSeconds
        self.profile = profile
        self.inventory = inventory
        self.selectedSets = selectedSets
        self.current = current
        self.settings = settings
        self.medium = medium
        self.filmID = filmID
        self.filmColor = filmColor
    }

    public func replacingBase(_ seconds: Double) -> Self {
        .init(cameraID: cameraID, baseSeconds: seconds, targetSeconds: targetSeconds,
              profile: profile, inventory: inventory, selectedSets: selectedSets,
              current: current, settings: settings, medium: medium, filmID: filmID, filmColor: filmColor)
    }

    public func evaluate() -> TargetNDSelectionResult {
        TargetNDSelection().evaluate(
            baseSeconds: baseSeconds, targetSeconds: targetSeconds,
            profile: profile, inventory: inventory, context: .init(selectedSets: selectedSets,
                current: current, allowance: settings[medium].interval(for: medium))
        )
    }
}
