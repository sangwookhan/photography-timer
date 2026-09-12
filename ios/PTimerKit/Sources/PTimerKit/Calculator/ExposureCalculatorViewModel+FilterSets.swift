// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Why an item save is blocked (FILTER-ITEM-005).
public enum FilterItemSaveBlockReason: Equatable, Sendable {
    /// A camera's active contributions would exceed 30 stops.
    case exceedsTotalLimit
    /// A camera currently mounts a row of this item that the edit
    /// removes — a selected CPL exposure-loss choice, or a row lost to
    /// a kind change. The selection is never replaced silently.
    case removesSelectedChoice
}

/// Outcome of saving a physical filter item (FILTER-ITEM-005): the
/// save commits only when every camera stack that references the item
/// stays valid afterwards.
public enum FilterItemSaveOutcome: Equatable, Sendable {
    case saved
    /// Display names of the cameras whose stack would become invalid,
    /// with the dominant reason (a removed selection outranks the cap).
    case blocked(affectedCameras: [String], reason: FilterItemSaveBlockReason)
}

/// Filter Set glue split from the main facade (Filter Set contract):
/// Plus-wheel source selection, inventory commands, the reconciliation
/// that makes every camera stack follow an inventory edit, and the
/// affected-camera lookups the management UI confirms against.
extension ExposureCalculatorViewModel {

    // MARK: Inventory change reconciliation

    /// Applies an inventory mutation to every camera stack
    /// (FILTER-ITEM-005/006, FILTER-PERSIST-002): the active stack
    /// re-resolves on the calculator model, every inactive slot
    /// snapshot re-resolves in place, a vanished last source falls
    /// back to Standard, and the session persists once. In-flight
    /// wheel interaction is discarded first — the edit came from the
    /// management surface, never mid-gesture.
    func applyFilterInventoryChange(_ inventory: FilterInventory) {
        filterInventory = inventory
        resetNDWheelInteractionState()
        calculatorModel.applyFilterInventory(inventory)
        syncNDStepMirrorFromModel()
        cameraSlotSessionModel.updateInactiveSnapshots { _, snapshot in
            snapshot.reresolvingFilterStack(against: inventory)
                ?? snapshot.emptyingMountedItems(against: inventory)
        }
        objectWillChange.send()
        persistCalculatorContext()
        reexamineNDWheelCleanup()
    }

    // MARK: Plus wheel — Filter Source selection (FILTER-PLUS)

    /// Standard first, then Filter Sets in user-defined order.
    public var filterSources: [FilterSource] {
        filterInventory.sources
    }

    /// The active camera's settled Filter Source — what Plus adds.
    public var selectedFilterSource: FilterSource {
        calculatorModel.lastFilterSource
    }

    /// Settles the Plus wheel on `source` for the active camera and
    /// remembers it across slot switches and relaunches
    /// (FILTER-PLUS-004). Changing the source never mutates the stack.
    public func selectFilterSource(_ source: FilterSource) {
        guard source != calculatorModel.lastFilterSource,
              filterInventory.contains(source) else {
            return
        }
        calculatorModel.selectFilterSource(source)
        objectWillChange.send()
        persistCalculatorContext()
    }

    public func filterSourceName(_ source: FilterSource) -> String {
        FilterWheelPresenter.sourceName(source, inventory: filterInventory)
    }

    /// The Filter Set color behind a source; `nil` for Standard.
    public func filterSetColor(for source: FilterSource) -> FilterSetColor? {
        source.filterSetID.flatMap { filterInventory.filterSet(withID: $0)?.color }
    }

    public func filterSet(withID id: FilterSetID) -> FilterSet? {
        filterInventory.filterSet(withID: id)
    }

    /// Localized reason the settled source cannot add right now;
    /// `nil` when adding is possible (FILTER-PLUS-005).
    public var filterAddUnavailabilityText: String? {
        filterAddUnavailability.map(FilterWheelPresenter.addUnavailabilityText(for:))
    }

    /// Picker rows for one wheel of the ACTIVE stack — Standard ladder
    /// or Empty plus the Filter Set's item rows with availability.
    public func filterWheelRowOptions(forWheel index: Int) -> [FilterWheelRowOption] {
        calculatorModel.rowOptions(forWheel: index)
    }

    // MARK: Filter Set management (FILTER-SET)

    public func suggestFilterSetCreationColor() -> FilterSetColor {
        filterInventoryModel.suggestCreationColor()
    }

    @discardableResult
    public func createFilterSet(name: String, color: FilterSetColor) -> FilterSet? {
        filterInventoryModel.createFilterSet(name: name, color: color)
    }

    public func renameFilterSet(id: FilterSetID, name: String) {
        filterInventoryModel.renameFilterSet(id: id, name: name)
    }

    public func recolorFilterSet(id: FilterSetID, color: FilterSetColor) {
        filterInventoryModel.recolorFilterSet(id: id, color: color)
    }

    public func moveFilterSets(fromOffsets source: IndexSet, toOffset destination: Int) {
        filterInventoryModel.moveFilterSets(fromOffsets: source, toOffset: destination)
    }

    /// Deletes a Filter Set. Wheels referencing it disappear from every
    /// camera through the inventory-change reconciliation; a camera left
    /// with no wheel receives one Standard 0 wheel (FILTER-ITEM-006).
    public func deleteFilterSet(id: FilterSetID) {
        filterInventoryModel.deleteFilterSet(id: id)
    }

    // MARK: Physical item management (FILTER-ITEM)

    public func moveFilterItems(in filterSetID: FilterSetID, fromOffsets source: IndexSet, toOffset destination: Int) {
        filterInventoryModel.moveItems(in: filterSetID, fromOffsets: source, toOffset: destination)
    }

    /// Deletes a physical item. Every wheel that referenced it becomes
    /// Empty on every camera (FILTER-ITEM-006).
    public func deleteFilterItem(id: FilterItemID) {
        filterInventoryModel.deleteItem(id: id)
    }

    /// Cameras whose stack currently mounts `itemID` — shown before a
    /// delete is confirmed (FILTER-ITEM-006).
    public func cameraNames(affectedByDeletingItem itemID: FilterItemID) -> [String] {
        cameraNames { wheels in
            wheels.contains { $0.mountedItemID == itemID }
        }
    }

    /// Cameras whose stack holds a wheel of the Filter Set.
    public func cameraNames(affectedByDeletingFilterSet filterSetID: FilterSetID) -> [String] {
        cameraNames { wheels in
            wheels.contains { $0.source == .filterSet(filterSetID) }
        }
    }

    /// Cameras whose stack would become invalid if `item` were saved as
    /// given (FILTER-ITEM-005): a total over 30 stops, or a mounted row
    /// of this item that would no longer exist — a CPL exposure-loss
    /// choice currently selected on that camera, or a row removed by a
    /// kind change. Empty when the save is safe. The system never
    /// replaces a selected CPL choice with another configured value.
    public func filterItemSaveConflicts(for item: FilterItem, in filterSetID: FilterSetID) -> [String] {
        filterItemSaveConflictDetails(for: item, in: filterSetID).map(\.cameraName)
    }

    /// One conflicting camera and why it conflicts.
    public struct FilterItemSaveConflict: Equatable, Sendable {
        public let cameraName: String
        public let reason: FilterItemSaveBlockReason
    }

    public func filterItemSaveConflictDetails(for item: FilterItem, in filterSetID: FilterSetID) -> [FilterItemSaveConflict] {
        guard item.isWellFormed else {
            return []
        }
        var candidate = filterInventory
        guard let setIndex = candidate.filterSets.firstIndex(where: { $0.id == filterSetID }) else {
            return []
        }
        if let itemIndex = candidate.filterSets[setIndex].items.firstIndex(where: { $0.id == item.id }) {
            candidate.filterSets[setIndex].items[itemIndex] = item
        } else {
            candidate.filterSets[setIndex].items.append(item)
        }
        var conflicts: [FilterItemSaveConflict] = []
        for slotID in cameraSlotSessionModel.availableSlots {
            let wheels: [FilterWheel]
            if slotID == cameraSlotSessionModel.activeSlotID {
                wheels = calculatorModel.filterWheels
            } else if let snapshot = cameraSlotSessionModel.snapshot(forInactiveSlot: slotID) {
                wheels = snapshot.filterWheels
            } else {
                continue
            }
            if let reason = Self.stackConflict(wheels, itemID: item.id, candidate: candidate) {
                conflicts.append(FilterItemSaveConflict(
                    cameraName: cameraSlotSessionModel.identity(for: slotID).displayName,
                    reason: reason
                ))
            }
        }
        return conflicts
    }

    /// A stack conflicts with the candidate inventory when a wheel
    /// mounting `itemID` no longer resolves (its selected row is gone)
    /// or when the re-resolved stack would exceed the cap.
    private static func stackConflict(_ wheels: [FilterWheel], itemID: FilterItemID, candidate: FilterInventory) -> FilterItemSaveBlockReason? {
        let selectedRowVanishes = wheels.contains { wheel in
            wheel.mountedItemID == itemID
                && FilterStack.resolvedRow(for: wheel, inventory: candidate) == nil
        }
        if selectedRowVanishes {
            return .removesSelectedChoice
        }
        guard let normalized = FilterStack.normalizedWheels(wheels, inventory: candidate),
              FilterStack.validated(wheels: normalized, inventory: candidate) != nil else {
            return .exceedsTotalLimit
        }
        return nil
    }

    /// Saves a new or edited item into `filterSetID`. Blocked — and
    /// nothing changes — when any camera stack would exceed the cap.
    @discardableResult
    public func saveFilterItem(_ item: FilterItem, in filterSetID: FilterSetID) -> FilterItemSaveOutcome {
        let conflicts = filterItemSaveConflictDetails(for: item, in: filterSetID)
        guard conflicts.isEmpty else {
            let reason: FilterItemSaveBlockReason = conflicts.contains { $0.reason == .removesSelectedChoice }
                ? .removesSelectedChoice
                : .exceedsTotalLimit
            return .blocked(affectedCameras: conflicts.map(\.cameraName), reason: reason)
        }
        if filterInventory.item(withID: item.id) != nil {
            filterInventoryModel.updateItem(item)
        } else {
            filterInventoryModel.addItem(item, to: filterSetID)
        }
        return .saved
    }

    // MARK: Helpers

    private func cameraNames(where predicate: ([FilterWheel]) -> Bool) -> [String] {
        var names: [String] = []
        for slotID in cameraSlotSessionModel.availableSlots {
            let wheels: [FilterWheel]
            if slotID == cameraSlotSessionModel.activeSlotID {
                wheels = calculatorModel.filterWheels
            } else {
                guard let snapshot = cameraSlotSessionModel.snapshot(forInactiveSlot: slotID) else {
                    continue
                }
                wheels = snapshot.filterWheels
            }
            if predicate(wheels) {
                names.append(cameraSlotSessionModel.identity(for: slotID).displayName)
            }
        }
        return names
    }
}
