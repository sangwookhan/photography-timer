// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Which source a filter wheel draws its rows from: the built-in
/// Standard ND ladder, or one user-owned Filter Set.
public enum FilterSource: Hashable, Codable, Sendable {
    case standard
    case filterSet(FilterSetID)

    public var filterSetID: FilterSetID? {
        if case .filterSet(let id) = self {
            return id
        }
        return nil
    }
}

/// Which shooting row of a physical item is selected.
public enum FilterRowChoice: Hashable, Sendable {
    /// The single row of a Fixed item.
    case fixed
    /// One of a CPL item's configured exposure-loss choices, in stops.
    case cplLoss(Double)
    /// A GND item's per-shot calculation mode.
    case gnd(GNDCalculationMode)
}

/// A mounted physical item plus the row chosen for it.
public struct FilterRowSelection: Hashable, Sendable {
    public let itemID: FilterItemID
    public let choice: FilterRowChoice

    public init(itemID: FilterItemID, choice: FilterRowChoice) {
        self.itemID = itemID
        self.choice = choice
    }
}

/// The committed (or in-flight) value of one wheel. `.standard` is the
/// only selection a Standard wheel holds; a Filter Set wheel holds
/// `.empty` (no physical item) or `.item` (a mounted item and its row).
public enum FilterWheelSelection: Hashable, Sendable {
    case standard(NDStep)
    case empty
    case item(FilterRowSelection)

    public var itemID: FilterItemID? {
        if case .item(let selection) = self {
            return selection.itemID
        }
        return nil
    }
}

/// One wheel of the mixed Filter Stack: its source and its selection.
public struct FilterWheel: Hashable, Sendable {
    public let source: FilterSource
    public let selection: FilterWheelSelection

    public init(source: FilterSource, selection: FilterWheelSelection) {
        self.source = source
        self.selection = selection
    }

    public static func standard(_ step: NDStep) -> FilterWheel {
        FilterWheel(source: .standard, selection: .standard(step))
    }

    public static func empty(in filterSetID: FilterSetID) -> FilterWheel {
        FilterWheel(source: .filterSet(filterSetID), selection: .empty)
    }

    public var isStandard: Bool {
        source == .standard
    }

    public var standardStep: NDStep? {
        if case .standard(let step) = selection {
            return step
        }
        return nil
    }

    /// Standard 0 and Filter Set Empty are the cleanable states: no
    /// physical item is mounted and nothing contributes. A mounted
    /// Record-only item is NOT cleanable.
    public var isCleanable: Bool {
        switch selection {
        case .standard(let step):
            return step.stops == 0
        case .empty:
            return true
        case .item:
            return false
        }
    }

    public var mountedItemID: FilterItemID? {
        selection.itemID
    }

    /// Source and selection agree: Standard wheels hold `.standard`,
    /// Filter Set wheels hold `.empty` or `.item`.
    public var isConsistent: Bool {
        switch (source, selection) {
        case (.standard, .standard), (.filterSet, .empty), (.filterSet, .item):
            return true
        default:
            return false
        }
    }
}

/// A wheel selection resolved against the inventory: what it
/// contributes now, what it sorts by, and the item it names.
public struct ResolvedFilterRow: Hashable, Sendable {
    public let selection: FilterWheelSelection
    /// Active contribution in canonical stops (0 for Empty and
    /// Record-only).
    public let contributionStops: Double
    /// Sort key within one source: the Standard value, an item's
    /// canonical registered value, or a CPL row's chosen loss. Empty
    /// sorts last regardless.
    public let registeredStops: Double
    /// The physical item for `.item` selections; `nil` otherwise.
    public let item: FilterItem?

    public init(selection: FilterWheelSelection, contributionStops: Double, registeredStops: Double, item: FilterItem?) {
        self.selection = selection
        self.contributionStops = contributionStops
        self.registeredStops = registeredStops
        self.item = item
    }

    public var isEmpty: Bool {
        selection == .empty
    }
}

/// Why a selection or mode change was refused. Changes are rejected,
/// never clamped; the previous valid state stays intact.
public enum FilterStackRejection: Hashable, Sendable, Error {
    /// The active contributions would exceed 30 stops.
    case exceedsTotalLimit
    /// The same physical item is already mounted on another wheel of
    /// this camera.
    case itemAlreadyMounted
    /// The selection does not resolve against the inventory or does
    /// not belong to the wheel's source.
    case unresolvedSelection
}

/// Why the selected source cannot currently add a usable wheel.
public enum FilterAddUnavailability: Hashable, Sendable {
    case stackFull
    /// Standard: the budget-truncated ladder holds no value above 0.
    case noSelectableValue
    case unknownFilterSet
    case filterSetHasNoItems
    case allItemsMounted
    /// Every unmounted item's rows would exceed the 30-stop cap.
    case exceedsTotalLimit
}

/// One selectable row of a wheel's picker.
public struct FilterWheelRowOption: Hashable, Sendable {
    public let row: ResolvedFilterRow
    /// `nil` when the row can be selected on this wheel right now.
    public let unavailability: FilterStackRejection?

    public init(row: ResolvedFilterRow, unavailability: FilterStackRejection?) {
        self.row = row
        self.unavailability = unavailability
    }

    public var selection: FilterWheelSelection {
        row.selection
    }

    public var isAvailable: Bool {
        unavailability == nil
    }
}

/// The active camera's mixed Filter Stack: one to four wheels drawn
/// from Standard and Filter Set sources, resolved against the
/// inventory. The 30-stop cap on active contributions and the
/// one-item-per-camera rule are invariants of this type: `init`
/// treats violations as programmer errors, and every mutation
/// returns either a valid stack or a rejection.
public struct FilterStack: Equatable, Sendable {
    public static let maximumWheelCount = NDFilterStack.maximumWheelCount
    static let totalLimit = Double(ExposureScale.maximumWholeNDStops)

    public private(set) var wheels: [FilterWheel]
    public private(set) var rows: [ResolvedFilterRow]

    public init(wheels: [FilterWheel], inventory: FilterInventory) {
        guard let stack = FilterStack.validated(wheels: wheels, inventory: inventory) else {
            preconditionFailure("A Filter Stack holds 1...\(Self.maximumWheelCount) resolvable wheels within \(Self.totalLimit) stops.")
        }
        self = stack
    }

    private init(wheels: [FilterWheel], rows: [ResolvedFilterRow]) {
        self.wheels = wheels
        self.rows = rows
    }

    /// A single Standard wheel — the default and legacy shape.
    public init(single step: NDStep) {
        self.init(
            wheels: [.standard(step)],
            rows: [ResolvedFilterRow(selection: .standard(step), contributionStops: step.stops, registeredStops: step.stops, item: nil)]
        )
    }

    /// Standard-only stack from raw wheel values (legacy callers).
    public init(standardSteps: [NDStep]) {
        self.init(wheels: standardSteps.map(FilterWheel.standard), inventory: .empty)
    }

    /// Validating construction: `nil` when any wheel fails to resolve,
    /// the count is outside 1–4, or the contributions exceed the cap.
    public static func validated(wheels: [FilterWheel], inventory: FilterInventory) -> FilterStack? {
        guard (1...maximumWheelCount).contains(wheels.count) else {
            return nil
        }
        var rows: [ResolvedFilterRow] = []
        var mounted: Set<FilterItemID> = []
        for wheel in wheels {
            guard let row = resolvedRow(for: wheel, inventory: inventory) else {
                return nil
            }
            if let itemID = row.selection.itemID {
                guard mounted.insert(itemID).inserted else {
                    return nil
                }
            }
            rows.append(row)
        }
        guard isWithinTotalLimit(rows.map(\.contributionStops)) else {
            return nil
        }
        return FilterStack(wheels: wheels, rows: rows)
    }

    public static func isWithinTotalLimit(_ contributions: [Double]) -> Bool {
        contributions.reduce(0, +) <= totalLimit + ExposureCalculator.stabilityEpsilon
    }

    /// Resolves one wheel against the inventory. `nil` when the wheel
    /// is inconsistent, names an unknown Filter Set or item, or names
    /// a row the item no longer offers.
    public static func resolvedRow(for wheel: FilterWheel, inventory: FilterInventory) -> ResolvedFilterRow? {
        guard wheel.isConsistent else {
            return nil
        }
        switch wheel.selection {
        case .standard(let step):
            guard step.stops.isFinite, step.stops >= 0 else {
                return nil
            }
            return ResolvedFilterRow(selection: .standard(step), contributionStops: step.stops, registeredStops: step.stops, item: nil)
        case .empty:
            guard inventory.contains(wheel.source) else {
                return nil
            }
            return ResolvedFilterRow(selection: .empty, contributionStops: 0, registeredStops: 0, item: nil)
        case .item(let selection):
            guard let filterSetID = wheel.source.filterSetID,
                  let filterSet = inventory.filterSet(withID: filterSetID),
                  let item = filterSet.item(withID: selection.itemID) else {
                return nil
            }
            return resolvedRow(item: item, choice: selection.choice)
        }
    }

    static func resolvedRow(item: FilterItem, choice: FilterRowChoice) -> ResolvedFilterRow? {
        let selection = FilterWheelSelection.item(FilterRowSelection(itemID: item.id, choice: choice))
        switch (item.behavior, choice) {
        case (.fixed(let value), .fixed):
            guard let stops = value.canonicalStops else { return nil }
            return ResolvedFilterRow(selection: selection, contributionStops: stops, registeredStops: stops, item: item)
        case (.cpl(let choices), .cplLoss(let loss)):
            guard let matched = choices.shootingChoices.first(where: {
                abs($0 - loss) <= ExposureCalculator.stabilityEpsilon
            }) else { return nil }
            let normalized = FilterWheelSelection.item(FilterRowSelection(itemID: item.id, choice: .cplLoss(matched)))
            return ResolvedFilterRow(selection: normalized, contributionStops: matched, registeredStops: matched, item: item)
        case (.gnd(let value), .gnd(let mode)):
            guard let stops = value.canonicalStops else { return nil }
            return ResolvedFilterRow(
                selection: selection,
                contributionStops: mode == .applyFullValue ? stops : 0,
                registeredStops: stops,
                item: item
            )
        default:
            return nil
        }
    }

    /// Every shooting row an item offers, in wheel order: Fixed → one
    /// row; CPL → one row per distinct configured choice; GND → Record
    /// only, then Apply full value.
    public static func rows(for item: FilterItem) -> [ResolvedFilterRow] {
        switch item.behavior {
        case .fixed:
            return [resolvedRow(item: item, choice: .fixed)].compactMap { $0 }
        case .cpl(let choices):
            return choices.shootingChoices.compactMap { resolvedRow(item: item, choice: .cplLoss($0)) }
        case .gnd:
            return GNDCalculationMode.allCases.compactMap { resolvedRow(item: item, choice: .gnd($0)) }
        }
    }

    /// Safe re-resolution of persisted or previously valid wheels
    /// against the current inventory: a wheel whose Filter Set no
    /// longer exists is dropped, and a wheel whose item or selected row
    /// no longer exists becomes Empty — a CPL selection whose configured
    /// exposure-loss choice is gone is never replaced by another choice
    /// (FILTER-PERSIST-002). An inconsistent wheel is dropped. A result
    /// with no wheel becomes one Standard 0 wheel. Returns `nil` only
    /// when more than four wheels were supplied — that is corruption,
    /// not recoverable state.
    public static func normalizedWheels(_ wheels: [FilterWheel], inventory: FilterInventory) -> [FilterWheel]? {
        guard wheels.count <= maximumWheelCount else {
            return nil
        }
        var normalized: [FilterWheel] = []
        var mounted: Set<FilterItemID> = []
        for wheel in wheels {
            guard var resolved = normalizedWheel(wheel, inventory: inventory) else {
                continue
            }
            // A physical item may be mounted once per camera: a later
            // duplicate reference becomes Empty.
            if let itemID = resolved.mountedItemID, !mounted.insert(itemID).inserted {
                resolved = FilterWheel(source: resolved.source, selection: .empty)
            }
            normalized.append(resolved)
        }
        return normalized.isEmpty ? [.standard(NDStep(stops: 0))] : normalized
    }

    /// Single-wheel step of `normalizedWheels(_:inventory:)`: the wheel
    /// as it should now read, or `nil` when it must be dropped
    /// (inconsistent, invalid Standard value, or unknown Filter Set).
    /// Exposed so a caller keeping per-wheel identity can follow each
    /// wheel through re-resolution.
    public static func normalizedWheel(_ wheel: FilterWheel, inventory: FilterInventory) -> FilterWheel? {
        guard wheel.isConsistent else {
            return nil
        }
        switch wheel.selection {
        case .standard(let step):
            guard step.stops.isFinite, step.stops >= 0 else { return nil }
            return wheel
        case .empty:
            return inventory.contains(wheel.source) ? wheel : nil
        case .item(let selection):
            guard let filterSetID = wheel.source.filterSetID,
                  let filterSet = inventory.filterSet(withID: filterSetID) else {
                return nil
            }
            guard let item = filterSet.item(withID: selection.itemID),
                  resolvedRow(item: item, choice: selection.choice) != nil else {
                return .empty(in: filterSetID)
            }
            return wheel
        }
    }

    // MARK: Derived values

    public var contributions: [Double] {
        rows.map(\.contributionStops)
    }

    /// The one effective value the calculation consumes: the sum of
    /// active contributions in canonical stops.
    public var effectiveStep: NDStep {
        NDStep(stops: contributions.reduce(0, +))
    }

    /// Standard wheel values in display order (legacy projections and
    /// the forward-compatible downgrade write).
    public var standardSteps: [NDStep] {
        wheels.compactMap(\.standardStep)
    }

    public var isStandardOnly: Bool {
        wheels.allSatisfy(\.isStandard)
    }

    /// Remaining budget for the wheel at `index`: the cap minus every
    /// OTHER wheel's active contribution.
    public func remainingBudget(excludingWheelAt index: Int) -> Double {
        precondition(wheels.indices.contains(index), "Wheel index out of range.")
        let others = rows.enumerated()
            .filter { $0.offset != index }
            .reduce(0.0) { $0 + $1.element.contributionStops }
        return Self.totalLimit - others
    }

    public func mountedItemIDs(excludingWheelAt index: Int?) -> Set<FilterItemID> {
        Set(wheels.enumerated().compactMap { offset, wheel in
            offset == index ? nil : wheel.mountedItemID
        })
    }

    // MARK: Row options

    /// Picker rows for the wheel at `index`. Standard wheels get the
    /// active scale's ladder truncated from the top to the remaining
    /// budget (every row selectable); Filter Set wheels get Empty plus
    /// every row of the set's items, each marked unavailable when its
    /// item is mounted elsewhere on this camera or its contribution
    /// would exceed the cap. The wheel's own current row is always
    /// available.
    public func rowOptions(forWheelAt index: Int, inventory: FilterInventory, scale: ExposureScale) -> [FilterWheelRowOption] {
        guard wheels.indices.contains(index) else {
            return []
        }
        let wheel = wheels[index]
        switch wheel.source {
        case .standard:
            return scale.ndSteps(upToStops: remainingBudget(excludingWheelAt: index)).map { step in
                FilterWheelRowOption(
                    row: ResolvedFilterRow(selection: .standard(step), contributionStops: step.stops, registeredStops: step.stops, item: nil),
                    unavailability: nil
                )
            }
        case .filterSet(let filterSetID):
            guard let filterSet = inventory.filterSet(withID: filterSetID) else {
                return []
            }
            let budget = remainingBudget(excludingWheelAt: index)
            let mountedElsewhere = mountedItemIDs(excludingWheelAt: index)
            let current = wheel.selection
            var options = [
                FilterWheelRowOption(
                    row: ResolvedFilterRow(selection: .empty, contributionStops: 0, registeredStops: 0, item: nil),
                    unavailability: nil
                ),
            ]
            for item in filterSet.items {
                for row in Self.rows(for: item) {
                    let unavailability: FilterStackRejection?
                    if row.selection == current {
                        unavailability = nil
                    } else if mountedElsewhere.contains(item.id) {
                        unavailability = .itemAlreadyMounted
                    } else if row.contributionStops > budget + ExposureCalculator.stabilityEpsilon {
                        unavailability = .exceedsTotalLimit
                    } else {
                        unavailability = nil
                    }
                    options.append(FilterWheelRowOption(row: row, unavailability: unavailability))
                }
            }
            return options
        }
    }

    // MARK: Adding wheels

    public var canAddWheel: Bool {
        wheels.count < Self.maximumWheelCount
    }

    /// Why `source` cannot add a usable wheel right now, or `nil` when
    /// it can. A Record-only row keeps a Filter Set addable at a
    /// 30-stop total as long as a slot and an unmounted item remain.
    public func addUnavailability(for source: FilterSource, inventory: FilterInventory, scale: ExposureScale) -> FilterAddUnavailability? {
        guard canAddWheel else {
            return .stackFull
        }
        let budget = Self.totalLimit - effectiveStep.stops
        switch source {
        case .standard:
            let hasValue = scale.ndSteps(upToStops: budget).contains { $0.stops > 0 }
            return hasValue ? nil : .noSelectableValue
        case .filterSet(let filterSetID):
            guard let filterSet = inventory.filterSet(withID: filterSetID) else {
                return .unknownFilterSet
            }
            guard !filterSet.items.isEmpty else {
                return .filterSetHasNoItems
            }
            let mounted = mountedItemIDs(excludingWheelAt: nil)
            let unmounted = filterSet.items.filter { !mounted.contains($0.id) }
            guard !unmounted.isEmpty else {
                return .allItemsMounted
            }
            let fits = unmounted.contains { item in
                Self.rows(for: item).contains { $0.contributionStops <= budget + ExposureCalculator.stabilityEpsilon }
            }
            return fits ? nil : .exceedsTotalLimit
        }
    }

    /// Appends a Standard 0-stop wheel or a Filter Set Empty wheel for
    /// `source`. Never changes the effective value. No-op at the
    /// maximum or for an unknown Filter Set.
    public func addingWheel(for source: FilterSource, inventory: FilterInventory) -> FilterStack {
        guard canAddWheel, inventory.contains(source) else {
            return self
        }
        var copy = self
        switch source {
        case .standard:
            copy.wheels.append(.standard(NDStep(stops: 0)))
            copy.rows.append(ResolvedFilterRow(selection: .standard(NDStep(stops: 0)), contributionStops: 0, registeredStops: 0, item: nil))
        case .filterSet(let filterSetID):
            copy.wheels.append(.empty(in: filterSetID))
            copy.rows.append(ResolvedFilterRow(selection: .empty, contributionStops: 0, registeredStops: 0, item: nil))
        }
        return copy
    }

    // MARK: Removing cleanable wheels

    /// More than one wheel AND at least one cleanable wheel (Standard 0
    /// or Empty). Mounted items are never removed.
    public var canRemoveEmptyWheel: Bool {
        wheels.count > 1 && wheels.contains(where: \.isCleanable)
    }

    public func removingEmptyWheel(at index: Int) -> FilterStack {
        guard wheels.count > 1,
              wheels.indices.contains(index),
              wheels[index].isCleanable else {
            return self
        }
        var copy = self
        copy.wheels.remove(at: index)
        copy.rows.remove(at: index)
        return copy
    }

    public func removingRightmostEmptyWheel() -> FilterStack {
        guard let index = wheels.lastIndex(where: \.isCleanable) else {
            return self
        }
        return removingEmptyWheel(at: index)
    }

    // MARK: Replacing a wheel's selection

    /// Writes one wheel's selection. Rejected — leaving the stack
    /// unchanged — when the selection does not resolve for the wheel's
    /// source, the item is already mounted on another wheel, or the
    /// active contributions would exceed 30 stops.
    public func replacingWheel(at index: Int, with selection: FilterWheelSelection, inventory: FilterInventory) -> Result<FilterStack, FilterStackRejection> {
        guard wheels.indices.contains(index) else {
            return .failure(.unresolvedSelection)
        }
        let wheel = FilterWheel(source: wheels[index].source, selection: selection)
        guard let row = Self.resolvedRow(for: wheel, inventory: inventory) else {
            return .failure(.unresolvedSelection)
        }
        if let itemID = row.selection.itemID,
           mountedItemIDs(excludingWheelAt: index).contains(itemID) {
            return .failure(.itemAlreadyMounted)
        }
        guard row.contributionStops <= remainingBudget(excludingWheelAt: index) + ExposureCalculator.stabilityEpsilon else {
            return .failure(.exceedsTotalLimit)
        }
        var copy = self
        copy.wheels[index] = FilterWheel(source: wheel.source, selection: row.selection)
        copy.rows[index] = row
        return .success(copy)
    }

    // MARK: Post-commit ordering

    /// Permutation of the current indices in commit order: sources in
    /// Standard-first, then user-defined Filter Set order; within one
    /// source, non-empty rows by canonical registered value descending
    /// with stable ties; Empty (and Standard 0) last.
    public func commitSortPermutation(inventory: FilterInventory) -> [Int] {
        wheels.indices.sorted { lhs, rhs in
            let lhsSource = inventory.sourceOrderIndex(of: wheels[lhs].source)
            let rhsSource = inventory.sourceOrderIndex(of: wheels[rhs].source)
            if lhsSource != rhsSource {
                return lhsSource < rhsSource
            }
            let lhsEmpty = wheels[lhs].isCleanable
            let rhsEmpty = wheels[rhs].isCleanable
            if lhsEmpty != rhsEmpty {
                return !lhsEmpty
            }
            let lhsKey = lhsEmpty ? 0 : rows[lhs].registeredStops
            let rhsKey = rhsEmpty ? 0 : rows[rhs].registeredStops
            if abs(lhsKey - rhsKey) > ExposureCalculator.stabilityEpsilon {
                return lhsKey > rhsKey
            }
            return lhs < rhs
        }
    }

    public func sortedForCommit(inventory: FilterInventory) -> FilterStack {
        let permutation = commitSortPermutation(inventory: inventory)
        return FilterStack(
            wheels: permutation.map { wheels[$0] },
            rows: permutation.map { rows[$0] }
        )
    }
}
