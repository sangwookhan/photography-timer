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

    // MARK: Mounted auxiliary filters (FILTER-AUX)

    /// The active camera's mounted auxiliary filters, resolved, in
    /// mount order; empty while the summary is hidden.
    public var mountedAuxiliaryFilters: [ResolvedAuxiliaryFilter] {
        calculatorModel.mountedAuxiliaryFilters
    }

    /// Page-aware mounted auxiliary filters: live for the active slot,
    /// the stored snapshot resolved against the current inventory for
    /// inactive pages (a mount that no longer resolves is omitted).
    public func mountedAuxiliaryFilters(forPage pageState: CameraSlotPageState) -> [ResolvedAuxiliaryFilter] {
        if pageState.isActive {
            return mountedAuxiliaryFilters
        }
        let inventory = calculatorModel.filterInventory
        return (cameraSlotSessionModel.snapshot(forInactiveSlot: pageState.slotID)?.auxiliaryFilters ?? [])
            .compactMap { FilterStack.resolvedAuxiliaryFilter($0, inventory: inventory) }
    }

    /// What the shooting popup's working selection would yield if
    /// applied now (FILTER-AUX-003): the effective total in stops, or
    /// the rejection Apply would report. Nothing is committed.
    public func auxiliaryFiltersPreview(_ mounts: [MountedAuxiliaryFilter]) -> Result<NDStep, FilterStackRejection> {
        calculatorModel.filterStack
            .replacingAuxiliaryFilters(with: mounts, inventory: filterInventory)
            .map(\.effectiveStep)
    }

    /// The Plus wheel's vertical choices (FILTER-PLUS-001): Standard,
    /// the candidate ND sources, then the Auxiliary filters action.
    public var filterPlusChoices: [FilterPlusChoice] {
        FilterPlusChoice.choices(for: filterSources)
    }

    /// The Main summary of the active camera's mounted auxiliary
    /// filters; `nil` hides the space (FILTER-AUX-001).
    public var auxiliaryFilterSummary: AuxiliaryFilterSummaryDisplayState? {
        AuxiliaryFilterSummaryPresenter.displayState(for: mountedAuxiliaryFilters)
    }

    /// Page-aware summary: live for the active slot, the stored
    /// snapshot for inactive pages.
    public func auxiliaryFilterSummary(forPage pageState: CameraSlotPageState) -> AuxiliaryFilterSummaryDisplayState? {
        AuxiliaryFilterSummaryPresenter.displayState(for: mountedAuxiliaryFilters(forPage: pageState))
    }

    // MARK: Camera candidate Filter Sets (FILTER-CAMERA)

    /// The active camera's candidate Filter Sets in user-defined set
    /// order. Standard is always available and is not listed.
    public var candidateFilterSetIDs: [FilterSetID] {
        calculatorModel.candidateFilterSetIDs
    }

    /// Sets the active camera's stack still references — through an
    /// ND wheel (Empty included) or a mounted auxiliary filter. They
    /// cannot leave the candidates until those selections are cleared.
    public var filterSetIDsReferencedByActiveCamera: Set<FilterSetID> {
        Set(calculatorModel.filterWheels.compactMap { $0.source.filterSetID })
            .union(calculatorModel.filterStack.auxiliaryFilters.map(\.filterSetID))
    }

    /// Outcome of a candidate assignment.
    public enum CandidateFilterSetAssignmentOutcome: Equatable, Sendable {
        case assigned
        /// The excluded sets the camera still references, by name;
        /// nothing changed.
        case blocked(referencedFilterSetNames: [String])
    }

    /// Replaces the active camera's candidate Filter Sets
    /// (FILTER-CAMERA-001). Assignment saves immediately and mounts
    /// nothing. Excluding a set this camera still references is
    /// blocked with the set names, so a candidate change can never
    /// alter the exposure calculation implicitly; a remembered ND
    /// source that is no longer a candidate falls back to Standard.
    @discardableResult
    public func setCandidateFilterSetIDs(_ ids: [FilterSetID]) -> CandidateFilterSetAssignmentOutcome {
        let excludedReferenced = filterSetIDsReferencedByActiveCamera.subtracting(ids)
        guard excludedReferenced.isEmpty else {
            let names = filterInventory.filterSets
                .filter { excludedReferenced.contains($0.id) }
                .map(\.name)
            return .blocked(referencedFilterSetNames: names)
        }
        guard ids != calculatorModel.candidateFilterSetIDs else {
            return .assigned
        }
        calculatorModel.setCandidateFilterSetIDs(ids)
        objectWillChange.send()
        persistCalculatorContext()
        return .assigned
    }

    // MARK: Plus wheel — Filter Source selection (FILTER-PLUS)

    /// Standard first, then the active camera's candidate Filter Sets
    /// that hold ND items, in user-defined order (FILTER-PLUS-001).
    public var filterSources: [FilterSource] {
        calculatorModel.filterSources
    }

    /// The active camera's settled Filter Source — what Plus adds.
    public var selectedFilterSource: FilterSource {
        calculatorModel.lastFilterSource
    }

    /// Programmatic seam (tests): settles the camera's remembered
    /// source without adding. The UI never calls it — a Plus tap, a
    /// settled browse, or an assistive activation goes through
    /// `addFilterWheel(from:)`, and only a successful addition moves
    /// the remembered source (FILTER-PLUS-004). Assistive source
    /// stepping browses a transient candidate on the control itself.
    func selectFilterSource(_ source: FilterSource) {
        guard source != calculatorModel.lastFilterSource,
              filterSources.contains(source) else {
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

    /// Localized reason `source` cannot add right now; `nil` when
    /// adding is possible (FILTER-PLUS-005). The Plus control asks for
    /// the source it displays — the remembered source, or the
    /// transient candidate an assistive adjustment is browsing — so
    /// its enabled state and spoken reason follow what it shows.
    public func filterAddUnavailabilityText(for source: FilterSource) -> String? {
        calculatorModel.filterAddUnavailability(for: source)
            .map(FilterWheelPresenter.addUnavailabilityText(for:))
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
        cameraNames { wheels, auxiliaryFilters in
            wheels.contains { $0.mountedItemID == itemID }
                || auxiliaryFilters.contains { $0.itemID == itemID }
        }
    }

    /// Cameras whose stack holds a wheel of the Filter Set.
    public func cameraNames(affectedByDeletingFilterSet filterSetID: FilterSetID) -> [String] {
        cameraNames { wheels, auxiliaryFilters in
            wheels.contains { $0.source == .filterSet(filterSetID) }
                || auxiliaryFilters.contains { $0.filterSetID == filterSetID }
        }
    }

    /// Cameras whose stack would become invalid if `item` were saved as
    /// given (FILTER-ITEM-005): a total over 30 stops, or a mounted row
    /// of this item that would no longer exist — a CPL exposure-loss
    /// choice currently selected on that camera, or a row removed by a
    /// kind change. Empty when the save is safe. The system never
    /// replaces a selected CPL choice with another configured value.
    func filterItemSaveConflicts(for item: FilterItem, in filterSetID: FilterSetID) -> [String] {
        filterItemSaveConflictDetails(for: item, in: filterSetID).map(\.cameraName)
    }

    /// One conflicting camera and why it conflicts.
    struct FilterItemSaveConflict: Equatable, Sendable {
        let cameraName: String
        let reason: FilterItemSaveBlockReason
    }

    private func filterItemSaveConflictDetails(for item: FilterItem, in filterSetID: FilterSetID) -> [FilterItemSaveConflict] {
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
            guard let stack = cameraStack(for: slotID) else {
                continue
            }
            if let reason = Self.stackConflict(stack.wheels, auxiliaryFilters: stack.auxiliaryFilters, itemID: item.id, candidate: candidate) {
                conflicts.append(FilterItemSaveConflict(
                    cameraName: cameraSlotSessionModel.identity(for: slotID).displayName,
                    reason: reason
                ))
            }
        }
        return conflicts
    }

    /// A camera's stack conflicts with the candidate inventory when a
    /// wheel or auxiliary filter mounting `itemID` no longer resolves
    /// (its selected row, CPL choice, or kind is gone) or when the
    /// re-resolved stack would exceed the cap.
    private static func stackConflict(
        _ wheels: [FilterWheel],
        auxiliaryFilters: [MountedAuxiliaryFilter],
        itemID: FilterItemID,
        candidate: FilterInventory
    ) -> FilterItemSaveBlockReason? {
        let selectedRowVanishes = wheels.contains { wheel in
            wheel.mountedItemID == itemID
                && FilterStack.resolvedRow(for: wheel, inventory: candidate) == nil
        } || auxiliaryFilters.contains { mount in
            mount.itemID == itemID
                && FilterStack.resolvedAuxiliaryFilter(mount, inventory: candidate) == nil
        }
        if selectedRowVanishes {
            return .removesSelectedChoice
        }
        let auxiliary = FilterStack.normalizedAuxiliaryFilters(auxiliaryFilters, inventory: candidate)
        guard let normalized = FilterStack.normalizedWheels(wheels, inventory: candidate),
              FilterStack.validated(wheels: normalized, auxiliaryFilters: auxiliary, inventory: candidate) != nil else {
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

    /// One camera's stack as the inventory reconciliation sees it:
    /// the live model for the active slot, the stored snapshot for
    /// the others (`nil` for a never-visited slot).
    private struct CameraStack {
        let wheels: [FilterWheel]
        let auxiliaryFilters: [MountedAuxiliaryFilter]
    }

    private func cameraStack(for slotID: CameraSlotID) -> CameraStack? {
        if slotID == cameraSlotSessionModel.activeSlotID {
            return CameraStack(wheels: calculatorModel.filterWheels, auxiliaryFilters: calculatorModel.filterStack.auxiliaryFilters)
        }
        guard let snapshot = cameraSlotSessionModel.snapshot(forInactiveSlot: slotID) else {
            return nil
        }
        return CameraStack(wheels: snapshot.filterWheels, auxiliaryFilters: snapshot.auxiliaryFilters)
    }

    private func cameraNames(where predicate: ([FilterWheel], [MountedAuxiliaryFilter]) -> Bool) -> [String] {
        var names: [String] = []
        for slotID in cameraSlotSessionModel.availableSlots {
            guard let stack = cameraStack(for: slotID) else {
                continue
            }
            if predicate(stack.wheels, stack.auxiliaryFilters) {
                names.append(cameraSlotSessionModel.identity(for: slotID).displayName)
            }
        }
        return names
    }
}
