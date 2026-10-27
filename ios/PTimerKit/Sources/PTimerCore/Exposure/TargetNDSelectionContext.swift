// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Selection policy inputs shared by a search and apply-time revalidation.
public struct TargetNDSelectionContext {
    public let selectedSets: [FilterSetID]
    public let current: FilterStack
    public let allowance: ClosedRange<Double>

    public init(selectedSets: [FilterSetID], current: FilterStack, allowance: ClosedRange<Double>) {
        self.selectedSets = selectedSets
        self.current = current
        self.allowance = allowance
    }
}
