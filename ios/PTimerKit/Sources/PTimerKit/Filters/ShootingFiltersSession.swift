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

    public func isSelected(_ id: FilterSetID) -> Bool {
        selectedFilterSetIDs.contains(id)
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

    /// The camera's committed state changed underneath the session —
    /// an inventory edit made from a set editor opened here, which is
    /// immediate and not rolled back (FILTER-FLOW-003). The mounts
    /// restart from the new committed state so Apply can never undo
    /// that edit, a set the camera gained joins the selection, and sets
    /// that no longer exist leave it.
    public mutating func rebase(
        committedFilterSetIDs ids: [FilterSetID],
        committedMounts mounts: [MountedAuxiliaryFilter],
        existingFilterSetIDs existing: Set<FilterSetID>
    ) {
        // A set the camera gained — a moved item's new set — joins the
        // working selection, so Apply keeps that item's references.
        for id in ids where !committedFilterSetIDs.contains(id) && !selectedFilterSetIDs.contains(id) {
            selectedFilterSetIDs.append(id)
        }
        committedFilterSetIDs = ids
        committedMounts = Set(mounts)
        workingMounts = mounts
        selectedFilterSetIDs.removeAll { !existing.contains($0) }
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
