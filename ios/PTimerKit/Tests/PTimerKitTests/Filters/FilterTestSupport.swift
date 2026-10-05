// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
@testable import PTimerKit

@MainActor
extension ExposureCalculatorViewModel {
    /// Test seam: makes every inventory Filter Set a candidate of the
    /// active camera (FILTER-CAMERA-001), so a test can select a set
    /// as the Plus source without walking the camera Filter Sets
    /// screen. Assignment mounts nothing.
    func assignAllFilterSetsAsCandidates() {
        setCandidateFilterSetIDs(filterInventory.filterSets.map(\.id))
    }
}

extension MountedAuxiliaryFilter {
    /// A mount of `item` from `set` with its initial choice unless a
    /// choice is given.
    static func mount(_ item: FilterItem, in set: FilterSet, _ choice: AuxiliaryFilterChoice? = nil) -> MountedAuxiliaryFilter {
        MountedAuxiliaryFilter(
            filterSetID: set.id,
            itemID: item.id,
            choice: choice ?? MountedAuxiliaryFilter.initialChoice(for: item) ?? .registeredLoss
        )
    }
}
