// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Why an item save is blocked (FILTER-ITEM-005).
public enum FilterItemSaveBlockReason: Equatable, Sendable {
    /// A camera's active contributions would exceed 30 stops.
    case exceedsTotalLimit
    /// A camera currently mounts a row of this item that the edit
    /// removes — a selected CPL exposure-loss choice. The selection is
    /// never replaced silently.
    case removesSelectedChoice
    /// A kind change would move a mounted item onto the ND wheels
    /// beyond the wheel limit (three beside the summary, four without).
    case tooManyNDWheels
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
    /// display order; empty while the summary is hidden.
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

    /// The Shooting Filters exposure reduction in stops: only the
    /// working selection's auxiliary contributions, never the ND
    /// wheels, which Shooting Filters does not show (FILTER-AUX-003).
    /// The 30-stop guard still uses the complete stack
    /// (`shootingFiltersPreview`).
    public func auxiliaryFiltersSubtotal(_ mounts: [MountedAuxiliaryFilter]) -> Double {
        mounts
            .compactMap { FilterStack.resolvedAuxiliaryFilter($0, inventory: filterInventory) }
            .reduce(0) { $0 + $1.contributionStops }
    }

    /// The Plus wheel's vertical choices (FILTER-PLUS-001): Standard,
    /// the candidate ND sources, then the Shooting filters action.
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

    /// The active camera's candidate Filter Sets in their selection
    /// order (FILTER-SET-004). Standard is always available and is not
    /// listed.
    public var candidateFilterSetIDs: [FilterSetID] {
        calculatorModel.candidateFilterSetIDs
    }

    /// Sets the active camera's stack still references — through an
    /// ND wheel (Empty included) or a mounted auxiliary filter. Shooting
    /// Filters marks them in use; leaving one out on Apply takes its
    /// filters and ND wheels off this camera (FILTER-CAMERA-003).
    public var filterSetIDsReferencedByActiveCamera: Set<FilterSetID> {
        Set(calculatorModel.filterWheels.compactMap { $0.source.filterSetID })
            .union(calculatorModel.filterStack.auxiliaryFilters.map(\.filterSetID))
    }

    // MARK: Shooting Filters session (FILTER-AUX-003, FILTER-CAMERA-003)

    /// The Selected filters panel of a Shooting Filters session
    /// (FILTER-FLOW-003): every selected filter in Main's order.
    public func selectedFilterRows(_ mounts: [MountedAuxiliaryFilter]) -> [SelectedFilterRowDisplayState] {
        let rows = mounts.compactMap { FilterStack.resolvedAuxiliaryFilter($0, inventory: filterInventory) }
        return AuxiliaryFilterSummaryPresenter.selectedFilterRows(for: FilterStack.displayOrdered(rows, inventory: filterInventory))
    }

    /// The working Selected Sets that still exist, in their selection
    /// order (FILTER-SET-001/004).
    public func selectedFilterSets(_ selected: [FilterSetID]) -> [FilterSet] {
        selected.compactMap(filterInventory.filterSet(withID:))
    }

    /// The working Selected Sets as Shooting Filters shows them
    /// (FILTER-SET-004): grouped ND-only, ND and auxiliary,
    /// auxiliary-only, empty, by their current items, each group in
    /// selection order.
    public func displayedSelectedFilterSets(_ selected: [FilterSetID]) -> [FilterSet] {
        SelectedFilterSetGroup.ordered(selectedFilterSets(selected))
    }

    /// Every other Filter Set, sorted by name (FILTER-SET-004).
    public func availableFilterSets(excluding selected: [FilterSetID]) -> [FilterSet] {
        FilterSetItemOrder.sortedByName(filterInventory.filterSets.filter { !selected.contains($0.id) })
    }

    /// What applying a Shooting Filters session would yield
    /// (FILTER-AUX-003/004): the resulting Total, or the reason Apply
    /// would be refused. Only the working mounts of selected sets count,
    /// and the ND wheels of unselected sets are left out. Nothing is
    /// committed.
    public func shootingFiltersPreview(
        selectedFilterSetIDs selected: [FilterSetID],
        mounts: [MountedAuxiliaryFilter]
    ) -> Result<NDStep, FilterStackRejection> {
        calculatorModel.shootingFiltersStack(
            selectedFilterSetIDs: Set(selected),
            mounts: mounts.filter { selected.contains($0.filterSetID) }
        ).result.map(\.effectiveStep)
    }

    /// One mount change in a Shooting Filters session (FILTER-AUX-007):
    /// mounting an item or changing its CPL choice or GND mode is refused
    /// at once when the working state would be invalid — over 30 stops,
    /// or an auxiliary filter beside four ND wheels that the working Set
    /// selection keeps — and the session stays as it was. Unmounting is
    /// always accepted. No ND wheel is ever removed to make room.
    public func shootingFiltersSession(
        _ session: ShootingFiltersSession,
        settingMount mount: MountedAuxiliaryFilter?,
        for itemID: FilterItemID
    ) -> Result<ShootingFiltersSession, FilterStackRejection> {
        var next = session
        next.setMount(mount, for: itemID)
        guard mount != nil else {
            return .success(next)
        }
        if case .failure(let rejection) = shootingFiltersPreview(selectedFilterSetIDs: next.selectedFilterSetIDs, mounts: next.mounts) {
            return .failure(rejection)
        }
        return .success(next)
    }

    // MARK: Plus wheel — Filter Source selection (FILTER-PLUS)

    /// Standard first, then the active camera's candidate Filter Sets
    /// that hold ND items, in their selection order (FILTER-PLUS-001).
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

    /// Saves a new filter into a proposed New Filter Set: the Set and
    /// the filter are created together, or nothing is (FILTER-ITEM-009).
    /// A new filter in a new Set is on no camera, so no stack can block it.
    @discardableResult
    public func createFilterSet(name: String, color: FilterSetColor, holding item: FilterItem) -> FilterSet? {
        filterInventoryModel.createFilterSet(name: name, color: color, holding: item)
    }

    /// Appends fresh Sample copies (FILTER-SET-008). No camera selects
    /// them, so every camera keeps its state.
    @discardableResult
    public func addSampleFilterSets() -> [FilterSet] {
        filterInventoryModel.addSampleFilterSets()
    }

    public func renameFilterSet(id: FilterSetID, name: String) {
        filterInventoryModel.renameFilterSet(id: id, name: name)
    }

    public func recolorFilterSet(id: FilterSetID, color: FilterSetColor) {
        filterInventoryModel.recolorFilterSet(id: id, color: color)
    }

    /// Deletes a Filter Set. Its wheels and mounted auxiliary filters
    /// leave every camera, and it leaves every camera's selected Sets,
    /// through the inventory-change reconciliation; a camera left with no
    /// wheel receives one Standard 0 wheel (FILTER-ITEM-006).
    public func deleteFilterSet(id: FilterSetID) {
        filterInventoryModel.deleteFilterSet(id: id)
    }

    // MARK: Physical item management (FILTER-ITEM)

    /// Deletes a physical item. Every wheel that referenced it becomes
    /// Empty and every auxiliary mount of it is unmounted, on every
    /// camera (FILTER-ITEM-006).
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
            // A new item, or an existing one moving here from another
            // set (FILTER-ITEM-009).
            for index in candidate.filterSets.indices {
                candidate.filterSets[index].items.removeAll { $0.id == item.id }
            }
            candidate.filterSets[setIndex].items.append(item)
        }
        var conflicts: [FilterItemSaveConflict] = []
        for slotID in cameraSlotSessionModel.availableSlots {
            guard let stack = cameraStack(for: slotID) else {
                continue
            }
            if let reason = Self.stackConflict(stack, itemID: item.id, candidate: candidate) {
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
    /// (its selected CPL choice is gone), when a kind change would move
    /// the mounted item into a role that is already full, or when the
    /// re-resolved stack would exceed the cap. A kind change within the
    /// limits moves the selection into the new role and does not
    /// conflict (FILTER-ITEM-005).
    private static func stackConflict(
        _ current: CameraStack,
        itemID: FilterItemID,
        candidate: FilterInventory
    ) -> FilterItemSaveBlockReason? {
        let reassigned = FilterStack.reassigningRoles(
            wheels: current.wheels,
            auxiliaryFilters: current.auxiliaryFilters,
            selectedFilterSetIDs: current.candidateFilterSetIDs,
            inventory: candidate
        )
        let wheels = reassigned.wheels
        let auxiliaryFilters = reassigned.auxiliaryFilters
        if wheels.count > FilterStack.wheelLimit(hasAuxiliaryFilters: !auxiliaryFilters.isEmpty) {
            return .tooManyNDWheels
        }
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

    /// Saves a new or edited item into `filterSetID`. An existing item
    /// saved into another set moves there with its id at once, and each
    /// camera judges the move against its own selected Filter Sets: where
    /// that set is selected, an ND wheel keeps the item and an auxiliary
    /// filter stays mounted; elsewhere the ND wheel becomes Empty under
    /// its original source and the auxiliary filter is unmounted. No
    /// camera selects the set (FILTER-ITEM-005/009).
    /// Blocked — and nothing changes — when any camera would lose a
    /// selected choice, need more ND wheels than its stack allows, or
    /// exceed the cap.
    @discardableResult
    public func saveFilterItem(_ item: FilterItem, in filterSetID: FilterSetID) -> FilterItemSaveOutcome {
        let conflicts = filterItemSaveConflictDetails(for: item, in: filterSetID)
        guard conflicts.isEmpty else {
            // One reason is shown: a removed selection first, then a
            // full role, then the cap.
            let priority: [FilterItemSaveBlockReason] = [.removesSelectedChoice, .tooManyNDWheels, .exceedsTotalLimit]
            let reason = priority.first { candidate in conflicts.contains { $0.reason == candidate } } ?? .exceedsTotalLimit
            return .blocked(affectedCameras: conflicts.map(\.cameraName), reason: reason)
        }
        if let owner = filterInventory.item(withID: item.id)?.filterSet {
            if owner.id == filterSetID {
                filterInventoryModel.updateItem(item)
            } else {
                filterInventoryModel.moveItem(item, to: filterSetID)
            }
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
        let candidateFilterSetIDs: [FilterSetID]
    }

    private func cameraStack(for slotID: CameraSlotID) -> CameraStack? {
        if slotID == cameraSlotSessionModel.activeSlotID {
            return CameraStack(
                wheels: calculatorModel.filterWheels,
                auxiliaryFilters: calculatorModel.filterStack.auxiliaryFilters,
                candidateFilterSetIDs: calculatorModel.candidateFilterSetIDs
            )
        }
        guard let snapshot = cameraSlotSessionModel.snapshot(forInactiveSlot: slotID) else {
            return nil
        }
        return CameraStack(
            wheels: snapshot.filterWheels,
            auxiliaryFilters: snapshot.auxiliaryFilters,
            candidateFilterSetIDs: snapshot.candidateFilterSetIDs
        )
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
