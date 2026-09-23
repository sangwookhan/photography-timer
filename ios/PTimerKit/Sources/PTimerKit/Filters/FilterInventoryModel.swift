// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// Source-of-truth model for the user's Filter Sets and physical
/// filter items. The model is the only writer of the inventory;
/// readers consume the `@Published` value. Every mutation persists
/// through `FilterInventoryStoring` so a relaunch restores the latest
/// state.
///
/// Stack reconciliation (making camera stacks follow an item edit or
/// deletion) is orchestrated by the view-model facade, which is the
/// one place that reads both this inventory and the calculator /
/// camera-slot state.
@MainActor
public final class FilterInventoryModel: ObservableObject {
    @Published public private(set) var inventory: FilterInventory
    private let store: FilterInventoryStoring
    /// Color suggested on the most recent creation opening — the next
    /// suggestion must differ from it (FILTER-SET-003). Session state.
    private var lastSuggestedColor: FilterSetColor?

    public init(
        store: FilterInventoryStoring = NoOpFilterInventoryStore(),
        initial: FilterInventory = .empty
    ) {
        self.store = store
        self.inventory = store.loadSnapshot()?.restoredInventory ?? initial
    }

    public var filterSets: [FilterSet] {
        inventory.filterSets
    }

    public func filterSet(withID id: FilterSetID) -> FilterSet? {
        inventory.filterSet(withID: id)
    }

    public func item(withID id: FilterItemID) -> (filterSet: FilterSet, item: FilterItem)? {
        inventory.item(withID: id)
    }

    // MARK: Filter Sets

    /// Random color for a new Filter Set that differs from the color
    /// suggested on the immediately preceding creation opening.
    public func suggestCreationColor() -> FilterSetColor {
        let suggestion = FilterSetColor.suggestion(excluding: lastSuggestedColor)
        lastSuggestedColor = suggestion
        return suggestion
    }

    /// Appends a new Filter Set to the user-defined order. Returns
    /// `nil` (and changes nothing) for a blank name.
    @discardableResult
    public func createFilterSet(name: String, color: FilterSetColor) -> FilterSet? {
        guard let trimmed = Self.trimmed(name) else {
            return nil
        }
        let filterSet = FilterSet(name: trimmed, color: color)
        inventory.filterSets.append(filterSet)
        persist()
        return filterSet
    }

    public func renameFilterSet(id: FilterSetID, name: String) {
        guard let trimmed = Self.trimmed(name),
              let index = inventory.filterSets.firstIndex(where: { $0.id == id }),
              inventory.filterSets[index].name != trimmed else {
            return
        }
        inventory.filterSets[index].name = trimmed
        persist()
    }

    public func recolorFilterSet(id: FilterSetID, color: FilterSetColor) {
        guard let index = inventory.filterSets.firstIndex(where: { $0.id == id }),
              inventory.filterSets[index].color != color else {
            return
        }
        inventory.filterSets[index].color = color
        persist()
    }

    /// Reorders Filter Sets with `Array.move` semantics (the SwiftUI
    /// `onMove` shape). Ids never change.
    public func moveFilterSets(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }
        inventory.filterSets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Removes a Filter Set and every item it holds. Stack cleanup for
    /// wheels that referenced the set is the facade's responsibility.
    public func deleteFilterSet(id: FilterSetID) {
        let before = inventory.filterSets.count
        inventory.filterSets.removeAll { $0.id == id }
        if inventory.filterSets.count != before {
            persist()
        }
    }

    // MARK: Items

    /// Appends a well-formed item to `filterSetID`. A duplicate item id
    /// replaces the existing entry in place.
    public func addItem(_ item: FilterItem, to filterSetID: FilterSetID) {
        guard item.isWellFormed,
              let index = inventory.filterSets.firstIndex(where: { $0.id == filterSetID }) else {
            return
        }
        if let existing = inventory.filterSets[index].items.firstIndex(where: { $0.id == item.id }) {
            inventory.filterSets[index].items[existing] = item
        } else {
            inventory.filterSets[index].items.append(item)
        }
        persist()
    }

    /// Replaces the item matching `item.id` wherever it lives. Item
    /// identity and position are preserved.
    public func updateItem(_ item: FilterItem) {
        guard item.isWellFormed else { return }
        for setIndex in inventory.filterSets.indices {
            if let itemIndex = inventory.filterSets[setIndex].items.firstIndex(where: { $0.id == item.id }) {
                guard inventory.filterSets[setIndex].items[itemIndex] != item else { return }
                inventory.filterSets[setIndex].items[itemIndex] = item
                persist()
                return
            }
        }
    }

    public func moveItems(in filterSetID: FilterSetID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty,
              let index = inventory.filterSets.firstIndex(where: { $0.id == filterSetID }) else {
            return
        }
        inventory.filterSets[index].items.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    public func deleteItem(id: FilterItemID) {
        for setIndex in inventory.filterSets.indices {
            let before = inventory.filterSets[setIndex].items.count
            inventory.filterSets[setIndex].items.removeAll { $0.id == id }
            if inventory.filterSets[setIndex].items.count != before {
                persist()
                return
            }
        }
    }

    // MARK: Helpers

    private static func trimmed(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func persist() {
        store.saveSnapshot(PersistentFilterInventorySnapshot(inventory: inventory))
    }
}
