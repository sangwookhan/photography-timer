// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore

/// The working state of one Shooting Filters session (FILTER-AUX-003,
/// FILTER-CAMERA-003, FILTER-FLOW-003): the Filter Sets selected for the
/// camera and the mounted auxiliary filters, copied from the camera's
/// committed state when the surface opens. Nothing here is committed;
/// Apply commits `selectedFilterSetIDs` and `mounts` together, and Cancel
/// simply drops the session.
///
/// The selected sets keep their selection order: an added set goes last
/// (FILTER-SET-004). Removing a set hides its auxiliary filters but keeps
/// their working mounts for the session, so adding it again restores
/// them.
public struct ShootingFiltersSession: Equatable, Sendable {
    public private(set) var selectedFilterSetIDs: [FilterSetID]
    /// Every working mount, including those of sets that are removed
    /// right now.
    private var workingMounts: [MountedAuxiliaryFilter]
    private var committedFilterSetIDs: [FilterSetID]
    private var committedMounts: Set<MountedAuxiliaryFilter>

    public init(committedFilterSetIDs: [FilterSetID], committedMounts: [MountedAuxiliaryFilter]) {
        selectedFilterSetIDs = committedFilterSetIDs
        workingMounts = committedMounts
        self.committedFilterSetIDs = committedFilterSetIDs
        self.committedMounts = Set(committedMounts)
    }

    /// The mounts Apply commits: the working mounts of selected sets.
    public var mounts: [MountedAuxiliaryFilter] {
        let selected = Set(selectedFilterSetIDs)
        return workingMounts.filter { selected.contains($0.filterSetID) }
    }

    /// Apply is offered when either the set selection, its order
    /// included, or the mounts differ from the camera's committed state.
    /// Mount order never matters; the display order is fixed.
    public var hasChanges: Bool {
        selectedFilterSetIDs != committedFilterSetIDs || Set(mounts) != committedMounts
    }

    /// Adds a set to the end of the working selection, or removes it,
    /// in the working state only.
    public mutating func setSelected(_ id: FilterSetID, _ isSelected: Bool) {
        if isSelected {
            if !selectedFilterSetIDs.contains(id) {
                selectedFilterSetIDs.append(id)
            }
        } else {
            selectedFilterSetIDs.removeAll { $0 == id }
        }
    }

    public func mount(of itemID: FilterItemID) -> MountedAuxiliaryFilter? {
        workingMounts.first { $0.itemID == itemID }
    }

    /// Mounts, changes, or (with `nil`) unmounts one item in the working
    /// selection.
    public mutating func setMount(_ mount: MountedAuxiliaryFilter?, for itemID: FilterItemID) {
        workingMounts.removeAll { $0.itemID == itemID }
        if let mount {
            workingMounts.append(mount)
        }
    }

    /// Follows an inventory edit made from a set editor opened here,
    /// which is immediate and not rolled back (FILTER-FLOW-003). Call it
    /// whenever the camera's committed state or the inventory changes:
    /// it rebases on a committed change and then reconciles against the
    /// inventory, so the screen's change handlers may fire in any order,
    /// or more than once, with the same result.
    public mutating func follow(
        committedFilterSetIDs ids: [FilterSetID],
        committedMounts mounts: [MountedAuxiliaryFilter],
        inventory: FilterInventory
    ) {
        if ids != committedFilterSetIDs || Set(mounts) != committedMounts {
            rebase(committedFilterSetIDs: ids, committedMounts: mounts, inventory: inventory)
        }
        reconcile(with: inventory)
    }

    /// The camera's committed state changed underneath the session —
    /// an inventory edit made from a set editor opened here, which is
    /// immediate and not rolled back (FILTER-FLOW-003). Each item follows
    /// the edit only where its committed mount changed: a pick the
    /// session had not changed takes the new committed mount, a pick the
    /// session had changed keeps its choice, and every other working pick
    /// or unmount stays as it is, so Apply never undoes the edit and never
    /// loses an unrelated draft change. A committed mount whose item moved
    /// stays picked only while the session selects the item's new Set
    /// (FILTER-ITEM-009), and one the camera dropped otherwise leaves the
    /// session too. A set the camera gained joins the selection, and sets
    /// that no longer exist leave it. Together with `reconcile`, which
    /// leaves these committed picks alone, the result does not depend on
    /// which of the two runs first.
    mutating func rebase(
        committedFilterSetIDs ids: [FilterSetID],
        committedMounts mounts: [MountedAuxiliaryFilter],
        inventory: FilterInventory
    ) {
        // A set the camera gained — a moved ND wheel's new set — joins the
        // working selection, so Apply keeps that item's references.
        for id in ids where !committedFilterSetIDs.contains(id) && !selectedFilterSetIDs.contains(id) {
            selectedFilterSetIDs.append(id)
        }
        let before = Dictionary(committedMounts.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(mounts.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        var rebased: [MountedAuxiliaryFilter] = []
        for working in workingMounts {
            let old = before[working.itemID], new = after[working.itemID]
            if old == new {
                rebased.append(working)
            } else if let new {
                if let old, old.filterSetID != new.filterSetID, !selectedFilterSetIDs.contains(new.filterSetID) {
                    continue
                }
                rebased.append(working == old || !new.choice.sameRole(as: working.choice)
                    ? new
                    : MountedAuxiliaryFilter(filterSetID: new.filterSetID, itemID: working.itemID, choice: working.choice))
            } else if working == old {
                // The camera dropped a pick the session had not changed. An
                // item that moved to a Set this session selects stays picked
                // there; anything else leaves with the camera's mount.
                if let owner = inventory.item(withID: working.itemID)?.filterSet.id,
                   owner != working.filterSetID,
                   selectedFilterSetIDs.contains(owner) {
                    let moved = MountedAuxiliaryFilter(filterSetID: owner, itemID: working.itemID, choice: working.choice)
                    if FilterStack.resolvedAuxiliaryFilter(moved, inventory: inventory) != nil {
                        rebased.append(moved)
                    }
                }
            } else {
                rebased.append(working)
            }
        }
        // A newly committed mount joins the session; one the session had
        // unmounted stays unmounted.
        for mount in mounts where before[mount.itemID] == nil && !rebased.contains(where: { $0.itemID == mount.itemID }) {
            rebased.append(mount)
        }
        committedFilterSetIDs = ids
        committedMounts = Set(mounts)
        workingMounts = rebased
        selectedFilterSetIDs.removeAll { inventory.filterSet(withID: $0) == nil }
    }

    /// An inventory edit made from a set editor opened here can leave the
    /// working state naming what no longer exists even when the camera's
    /// committed state did not change: a working pick of a deleted item,
    /// of an item in a deleted Set, or with a choice no longer configured
    /// or no longer fitting the item's kind is dropped, never replaced
    /// (FILTER-ITEM-006, FILTER-PERSIST-002), and a deleted Set leaves the
    /// selection. A pick whose item now lives in another Set follows it
    /// there with its choice while the session selects that Set, and is
    /// otherwise cleared for good, so selecting the Set later does not
    /// bring it back (FILTER-ITEM-009). A pick that still equals the
    /// camera's committed mount is left to `rebase`: the camera's own
    /// reconciliation decides it. Every other working choice is kept.
    mutating func reconcile(with inventory: FilterInventory) {
        selectedFilterSetIDs.removeAll { inventory.filterSet(withID: $0) == nil }
        workingMounts = workingMounts.compactMap { mount in
            if committedMounts.contains(mount) { return mount }
            guard let owner = inventory.item(withID: mount.itemID)?.filterSet.id else { return nil }
            var mount = mount
            if owner != mount.filterSetID {
                guard selectedFilterSetIDs.contains(owner) else { return nil }
                mount = MountedAuxiliaryFilter(filterSetID: owner, itemID: mount.itemID, choice: mount.choice)
            }
            return FilterStack.resolvedAuxiliaryFilter(mount, inventory: inventory) == nil ? nil : mount
        }
    }
}

private extension AuxiliaryFilterChoice {
    /// The same kind of choice: a CPL loss, a GND mode, or a registered
    /// loss.
    func sameRole(as other: AuxiliaryFilterChoice) -> Bool {
        switch (self, other) {
        case (.cplLoss, .cplLoss), (.gnd, .gnd), (.registeredLoss, .registeredLoss): return true
        default: return false
        }
    }
}

/// Where a Selected Set in Shooting Filters offers New Filter
/// (FILTER-SET-001, FILTER-FLOW-004): a trailing control in its header
/// while it holds at least one filter, otherwise a full-width Add Filter
/// row in its place.
public enum SelectedFilterSetAddFilterPlacement: Equatable, Sendable {
    case headerControl
    case fullWidthRow

    public init(for filterSet: FilterSet) {
        self = filterSet.items.isEmpty ? .fullWidthRow : .headerControl
    }
}

/// The groups Shooting Filters shows its Selected Filter Sets in, by
/// each set's current items (FILTER-SET-004): ND-only sets first, then
/// sets with both ND and auxiliary filters, then auxiliary-only sets,
/// then empty sets. Only that display is grouped; the camera's
/// selection order is unchanged.
public enum SelectedFilterSetGroup: Int, Comparable, Sendable {
    case ndOnly
    case mixed
    case auxiliaryOnly
    case empty

    public init(for filterSet: FilterSet) {
        let hasND = filterSet.items.contains { $0.behavior.kind == .fixed }
        let hasAuxiliary = !filterSet.auxiliaryItems.isEmpty
        switch (hasND, hasAuxiliary) {
        case (true, false): self = .ndOnly
        case (true, true): self = .mixed
        case (false, true): self = .auxiliaryOnly
        case (false, false): self = .empty
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// `sets` grouped for display, each group keeping the order given
    /// (the working selection order).
    public static func ordered(_ sets: [FilterSet]) -> [FilterSet] {
        sets.enumerated()
            .sorted { lhs, rhs in
                let left = Self(for: lhs.element), right = Self(for: rhs.element)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}

extension FilterSet {
    /// A Selected Set that holds ND filters, alone or beside auxiliary
    /// filters, shows a passive inline ND cue in its Shooting Filters
    /// header (FILTER-FLOW-003); its ND values are chosen on Main.
    public var showsNDCue: Bool {
        items.contains { $0.behavior.kind == .fixed }
    }
}
