// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
@testable import PTimerKit

@MainActor
extension ExposureCalculatorViewModel {
    /// Test arrangement: makes every inventory Filter Set a candidate of
    /// the active camera (FILTER-CAMERA-001), so a test can select a set
    /// as the Plus source without the Shooting Filters screen. Nothing is
    /// mounted or removed and Plus does not move; tests of the commit
    /// itself use `selectFilterSets` or `applyShootingFilters`.
    func assignAllFilterSetsAsCandidates() {
        arrangeFilterSets(filterInventory.filterSets.map(\.id))
    }

    /// Test arrangement: sets the active camera's candidates without a
    /// Shooting Filters commit, and saves the camera.
    func arrangeFilterSets(_ ids: [FilterSetID]) {
        calculatorModel.arrangeCandidateFilterSetIDs(ids)
        objectWillChange.send()
        persistCalculatorContext()
    }

    /// Applies `ids` as the active camera's selected Filter Sets with
    /// its current mounts, through the production Apply.
    @discardableResult
    func selectFilterSets(_ ids: [FilterSetID]) -> FilterStackRejection? {
        applyShootingFilters(selectedFilterSetIDs: ids, mounts: mountedAuxiliaryFilters.map(\.mount))
    }

    /// Applies `mounts` as the complete auxiliary selection through the
    /// production Apply, keeping the selected Filter Sets and adding
    /// the sets the mounts come from.
    @discardableResult
    func applyMounts(_ mounts: [MountedAuxiliaryFilter]) -> FilterStackRejection? {
        var selected = candidateFilterSetIDs
        for id in mounts.map(\.filterSetID) where !selected.contains(id) {
            selected.append(id)
        }
        return applyShootingFilters(selectedFilterSetIDs: selected, mounts: mounts)
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
