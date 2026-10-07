// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Which source a filter wheel draws its rows from: the built-in
/// Standard ND ladder, or one user-owned Filter Set.
public enum FilterSource: Hashable, Sendable {
    case standard
    case filterSet(FilterSetID)

    public var filterSetID: FilterSetID? {
        if case .filterSet(let id) = self {
            return id
        }
        return nil
    }
}

/// Which shooting row of a physical item is selected on an ND wheel.
/// Only `fixed` resolves on a wheel today (FILTER-STACK-003); the CPL
/// and GND cases survive as legacy wheel selections so a persisted
/// mixed stack can be migrated into auxiliary filters
/// (`FilterStack.migratingLegacyWheels`).
public enum FilterRowChoice: Hashable, Sendable {
    /// The single row of a Fixed (ND) item.
    case fixed
    /// Legacy: one of a CPL item's exposure-loss choices, in stops.
    case cplLoss(Double)
    /// Legacy: a GND item's per-shot calculation mode.
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

/// Per-shot choice for a mounted auxiliary filter (FILTER-AUX-003):
/// a CPL's selected exposure-loss choice, a GND's calculation mode,
/// or — for Color and Effect items — their registered loss.
public enum AuxiliaryFilterChoice: Hashable, Sendable {
    case cplLoss(Double)
    case gnd(GNDCalculationMode)
    case registeredLoss
}

/// One physical auxiliary filter mounted on the active camera, with
/// the choice made for the current shot. Auxiliary filters share one
/// summary space on Main; they are not wheels.
public struct MountedAuxiliaryFilter: Hashable, Sendable {
    public let filterSetID: FilterSetID
    public let itemID: FilterItemID
    public let choice: AuxiliaryFilterChoice

    public init(filterSetID: FilterSetID, itemID: FilterItemID, choice: AuxiliaryFilterChoice) {
        self.filterSetID = filterSetID
        self.itemID = itemID
        self.choice = choice
    }

    /// The default choice when an item is first mounted: a CPL's
    /// first configured choice, Record only for a GND
    /// (FILTER-GND-002), and the registered loss otherwise. `nil`
    /// for an ND item, which is never an auxiliary filter.
    public static func initialChoice(for item: FilterItem) -> AuxiliaryFilterChoice? {
        switch item.behavior {
        case .fixed:
            return nil
        case .cpl(let choices):
            return choices.shootingChoices.first.map(AuxiliaryFilterChoice.cplLoss)
        case .gnd:
            return .gnd(.recordOnly)
        case .color, .effect:
            return .registeredLoss
        }
    }
}

/// A mounted auxiliary filter resolved against the inventory: the
/// item it names, its owning set's presentation metadata, what it
/// contributes now, and its registered value (a GND's full density, a
/// CPL's selected choice, a Color / Effect item's loss).
public struct ResolvedAuxiliaryFilter: Hashable, Sendable {
    public let mount: MountedAuxiliaryFilter
    public let item: FilterItem
    public let filterSetName: String
    public let filterSetColor: FilterSetColor
    /// Active contribution in canonical stops (0 for Record only).
    public let contributionStops: Double
    /// Registered value in canonical stops.
    public let registeredStops: Double

    public init(mount: MountedAuxiliaryFilter, item: FilterItem, filterSetName: String, filterSetColor: FilterSetColor, contributionStops: Double, registeredStops: Double) {
        self.mount = mount
        self.item = item
        self.filterSetName = filterSetName
        self.filterSetColor = filterSetColor
        self.contributionStops = contributionStops
        self.registeredStops = registeredStops
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
    var isConsistent: Bool {
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
    /// Mounting an auxiliary filter while four ND wheels exist: the
    /// wheels are never removed or merged automatically
    /// (FILTER-STACK-001, FILTER-AUX-003).
    case tooManyNDWheels
}

/// Why the selected source cannot currently add a usable wheel.
public enum FilterAddUnavailability: Hashable, Sendable {
    /// The applicable ND-wheel limit is reached: four without
    /// auxiliary filters, three with them (FILTER-STACK-001).
    case stackFull
    /// Standard: the budget-truncated ladder holds no value above 0.
    case noSelectableValue
    case unknownFilterSet
    /// The Filter Set has no ND item; auxiliary items never make a
    /// wheel (FILTER-STACK-003).
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

/// The active camera's Filter Stack: its ND wheels — drawn from
/// Standard and Filter Set sources — together with its mounted
/// auxiliary filters, all resolved against the inventory
/// (FILTER-STACK-001). One to four wheels are allowed without
/// auxiliary filters, one to three with them. The 30-stop cap on the
/// combined active contributions and the one-item-per-camera rule
/// across wheels and auxiliary filters are invariants of this type:
/// `init` treats violations as programmer errors, and every mutation
/// returns either a valid stack or a rejection.
public struct FilterStack: Equatable, Sendable {
    /// Absolute ND-wheel maximum, reached only without auxiliary
    /// filters.
    public static let maximumWheelCount = NDFilterStack.maximumWheelCount
    /// ND-wheel maximum while any auxiliary filter is mounted: the
    /// summary occupies one of the four spaces.
    public static let maximumWheelCountWithAuxiliaryFilters = 3
    static let totalLimit = Double(ExposureScale.maximumWholeNDStops)

    public private(set) var wheels: [FilterWheel]
    public private(set) var rows: [ResolvedFilterRow]
    /// Mounted auxiliary filters in display order (Color, Effect, CPL,
    /// GND; then set order, then item order), never mount order; empty
    /// when the summary is hidden.
    public private(set) var auxiliaryFilters: [MountedAuxiliaryFilter]
    /// Resolved auxiliary filters parallel to `auxiliaryFilters`.
    public private(set) var auxiliaryRows: [ResolvedAuxiliaryFilter]

    /// The ND-wheel limit that applies with or without auxiliary
    /// filters (FILTER-STACK-001).
    public static func wheelLimit(hasAuxiliaryFilters: Bool) -> Int {
        hasAuxiliaryFilters ? maximumWheelCountWithAuxiliaryFilters : maximumWheelCount
    }

    /// Module-internal construction for wheel sets known to resolve
    /// (the Standard-only shapes). Everything else goes through
    /// `validated(wheels:inventory:)`, which reports failure as `nil`.
    init(wheels: [FilterWheel], inventory: FilterInventory) {
        guard let stack = FilterStack.validated(wheels: wheels, inventory: inventory) else {
            preconditionFailure("A Filter Stack holds 1...\(Self.maximumWheelCount) resolvable wheels within \(Self.totalLimit) stops.")
        }
        self = stack
    }

    private init(wheels: [FilterWheel], rows: [ResolvedFilterRow], auxiliaryFilters: [MountedAuxiliaryFilter] = [], auxiliaryRows: [ResolvedAuxiliaryFilter] = []) {
        self.wheels = wheels
        self.rows = rows
        self.auxiliaryFilters = auxiliaryFilters
        self.auxiliaryRows = auxiliaryRows
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

    /// Validating construction without auxiliary filters.
    public static func validated(wheels: [FilterWheel], inventory: FilterInventory) -> FilterStack? {
        validated(wheels: wheels, auxiliaryFilters: [], inventory: inventory)
    }

    /// Validating construction: `nil` when any wheel or auxiliary
    /// filter fails to resolve, the wheel count is outside the
    /// applicable limit, a physical item appears twice, or the combined
    /// contributions exceed the cap. Any number of auxiliary filters
    /// may be mounted; they are kept in display order.
    public static func validated(wheels: [FilterWheel], auxiliaryFilters: [MountedAuxiliaryFilter], inventory: FilterInventory) -> FilterStack? {
        guard (1...wheelLimit(hasAuxiliaryFilters: !auxiliaryFilters.isEmpty)).contains(wheels.count) else {
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
        var auxiliaryRows: [ResolvedAuxiliaryFilter] = []
        for mount in auxiliaryFilters {
            guard let resolved = resolvedAuxiliaryFilter(mount, inventory: inventory),
                  mounted.insert(mount.itemID).inserted else {
                return nil
            }
            auxiliaryRows.append(resolved)
        }
        guard isWithinTotalLimit(rows.map(\.contributionStops) + auxiliaryRows.map(\.contributionStops)) else {
            return nil
        }
        let ordered = displayOrdered(auxiliaryRows, inventory: inventory)
        return FilterStack(wheels: wheels, rows: rows, auxiliaryFilters: ordered.map(\.mount), auxiliaryRows: ordered)
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

    /// An ND wheel resolves ND items only (FILTER-STACK-003): a CPL,
    /// GND, Color, or Effect selection on a wheel is unresolvable.
    static func resolvedRow(item: FilterItem, choice: FilterRowChoice) -> ResolvedFilterRow? {
        guard case .fixed(let value) = item.behavior, choice == .fixed,
              let stops = value.canonicalStops else {
            return nil
        }
        let selection = FilterWheelSelection.item(FilterRowSelection(itemID: item.id, choice: .fixed))
        return ResolvedFilterRow(selection: selection, contributionStops: stops, registeredStops: stops, item: item)
    }

    /// The single wheel row an ND item offers; auxiliary items never
    /// appear on a wheel (FILTER-ITEM-003, FILTER-STACK-003).
    static func rows(for item: FilterItem) -> [ResolvedFilterRow] {
        [resolvedRow(item: item, choice: .fixed)].compactMap { $0 }
    }

    /// Resolves one mounted auxiliary filter against the inventory:
    /// `nil` when its set or item no longer exists, the item is not
    /// an auxiliary kind, or the choice does not fit the item — a CPL
    /// choice that is no longer configured is never replaced by
    /// another (FILTER-PERSIST-002). A CPL choice resolves to the
    /// configured value it matches.
    public static func resolvedAuxiliaryFilter(_ mount: MountedAuxiliaryFilter, inventory: FilterInventory) -> ResolvedAuxiliaryFilter? {
        guard let filterSet = inventory.filterSet(withID: mount.filterSetID),
              let item = filterSet.item(withID: mount.itemID) else {
            return nil
        }
        let contribution: Double
        let registered: Double
        var choice = mount.choice
        switch (item.behavior, mount.choice) {
        case (.cpl(let choices), .cplLoss(let loss)):
            guard let matched = choices.shootingChoices.first(where: {
                abs($0 - loss) <= ExposureCalculator.stabilityEpsilon
            }) else { return nil }
            choice = .cplLoss(matched)
            contribution = matched
            registered = matched
        case (.gnd(let value), .gnd(let mode)):
            guard let stops = value.canonicalStops else { return nil }
            contribution = mode == .applyFullValue ? stops : 0
            registered = stops
        case (.color(let loss, _), .registeredLoss), (.effect(let loss), .registeredLoss):
            guard loss.isValid else { return nil }
            contribution = loss.stops
            registered = loss.stops
        default:
            return nil
        }
        return ResolvedAuxiliaryFilter(
            mount: MountedAuxiliaryFilter(filterSetID: mount.filterSetID, itemID: mount.itemID, choice: choice),
            item: item,
            filterSetName: filterSet.name,
            filterSetColor: filterSet.color,
            contributionStops: contribution,
            registeredStops: registered
        )
    }

    /// Safe re-resolution of persisted or previously valid auxiliary
    /// filters (FILTER-PERSIST-002): an unresolvable mount — unknown
    /// set or item, a CPL choice that no longer exists, a kind change
    /// — is unmounted rather than substituted, a later duplicate of a
    /// physical item is dropped, and the rest are put in display order.
    public static func normalizedAuxiliaryFilters(_ mounts: [MountedAuxiliaryFilter], inventory: FilterInventory) -> [MountedAuxiliaryFilter] {
        var seen: Set<FilterItemID> = []
        var normalized: [ResolvedAuxiliaryFilter] = []
        for mount in mounts {
            guard let resolved = resolvedAuxiliaryFilter(mount, inventory: inventory),
                  seen.insert(mount.itemID).inserted else {
                continue
            }
            normalized.append(resolved)
        }
        return displayOrdered(normalized, inventory: inventory).map(\.mount)
    }

    /// The stable display order of mounted auxiliary filters
    /// (FILTER-AUX-002): Color, Effect, CPL, GND; within one kind the
    /// inventory's Filter Set order, then the item order inside the
    /// set. Mount order never matters.
    public static func displayOrdered(_ rows: [ResolvedAuxiliaryFilter], inventory: FilterInventory) -> [ResolvedAuxiliaryFilter] {
        func kindRank(_ kind: FilterItemKind) -> Int {
            switch kind {
            case .color: return 0
            case .effect: return 1
            case .cpl: return 2
            case .gnd: return 3
            case .fixed: return 4
            }
        }
        // Kind rank, set index, item index — compared in that order.
        func key(_ row: ResolvedAuxiliaryFilter) -> [Int] {
            let setIndex = inventory.filterSets.firstIndex { $0.id == row.mount.filterSetID } ?? Int.max
            let itemIndex = inventory.filterSets.indices.contains(setIndex)
                ? inventory.filterSets[setIndex].items.firstIndex { $0.id == row.mount.itemID } ?? Int.max
                : Int.max
            return [kindRank(row.item.behavior.kind), setIndex, itemIndex]
        }
        return rows.sorted { key($0).lexicographicallyPrecedes(key($1)) }
    }

    /// Splits a legacy mixed stack into its two halves
    /// (FILTER-PERSIST-002): a wheel mounting a CPL or GND row becomes
    /// an auxiliary filter with the same item, choice, and mode, and
    /// that wheel is dropped; every other wheel stays. A stack that
    /// held only auxiliary rows receives one Standard 0 wheel. The
    /// result is not yet validated against the inventory.
    public static func migratingLegacyWheels(_ wheels: [FilterWheel]) -> (wheels: [FilterWheel], auxiliaryFilters: [MountedAuxiliaryFilter]) {
        var remaining: [FilterWheel] = []
        var auxiliary: [MountedAuxiliaryFilter] = []
        for wheel in wheels {
            if case .item(let selection) = wheel.selection,
               let filterSetID = wheel.source.filterSetID {
                switch selection.choice {
                case .cplLoss(let loss):
                    auxiliary.append(MountedAuxiliaryFilter(filterSetID: filterSetID, itemID: selection.itemID, choice: .cplLoss(loss)))
                    continue
                case .gnd(let mode):
                    auxiliary.append(MountedAuxiliaryFilter(filterSetID: filterSetID, itemID: selection.itemID, choice: .gnd(mode)))
                    continue
                case .fixed:
                    break
                }
            }
            remaining.append(wheel)
        }
        if remaining.isEmpty {
            remaining = [.standard(NDStep(stops: 0))]
        }
        return (remaining, auxiliary)
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

    /// Per-wheel active contributions in wheel order.
    public var contributions: [Double] {
        rows.map(\.contributionStops)
    }

    /// Per-item active contributions of the mounted auxiliary filters.
    public var auxiliaryContributions: [Double] {
        auxiliaryRows.map(\.contributionStops)
    }

    public var hasAuxiliaryFilters: Bool {
        !auxiliaryFilters.isEmpty
    }

    /// The ND-wheel limit currently in force (FILTER-STACK-001).
    public var wheelLimit: Int {
        Self.wheelLimit(hasAuxiliaryFilters: hasAuxiliaryFilters)
    }

    /// The one effective value the calculation consumes: the sum of
    /// every wheel's and every auxiliary filter's active contribution
    /// in canonical stops (FILTER-STACK-004).
    public var effectiveStep: NDStep {
        NDStep(stops: (contributions + auxiliaryContributions).reduce(0, +))
    }

    /// Remaining budget for the wheel at `index`: the cap minus every
    /// OTHER wheel's and every auxiliary filter's active contribution.
    public func remainingBudget(excludingWheelAt index: Int) -> Double {
        precondition(wheels.indices.contains(index), "Wheel index out of range.")
        let others = rows.enumerated()
            .filter { $0.offset != index }
            .reduce(0.0) { $0 + $1.element.contributionStops }
        return Self.totalLimit - others - auxiliaryContributions.reduce(0, +)
    }

    /// Every physical item mounted on this camera — on a wheel other
    /// than `index`, or as an auxiliary filter (FILTER-AUX-004).
    func mountedItemIDs(excludingWheelAt index: Int?) -> Set<FilterItemID> {
        Set(wheels.enumerated().compactMap { offset, wheel in
            offset == index ? nil : wheel.mountedItemID
        }).union(auxiliaryFilters.map(\.itemID))
    }

    // MARK: Row options

    /// Picker rows for the wheel at `index`. Standard wheels get the
    /// active scale's ladder truncated from the top to the remaining
    /// budget (every row selectable), plus the wheel's own value when it
    /// is a fractional value saved before the ladder became whole stops
    /// (ND-PERSIST-005); Filter Set wheels get Empty plus
    /// the set's ND items (FILTER-STACK-003), each marked unavailable
    /// when its item is mounted elsewhere on this camera — on another
    /// wheel or as an auxiliary filter — or its contribution would
    /// exceed the cap. The wheel's own current row is always
    /// available.
    public func rowOptions(forWheelAt index: Int, inventory: FilterInventory, scale: ExposureScale) -> [FilterWheelRowOption] {
        guard wheels.indices.contains(index) else {
            return []
        }
        let wheel = wheels[index]
        switch wheel.source {
        case .standard:
            var steps = scale.ndSteps(upToStops: remainingBudget(excludingWheelAt: index))
            if let current = wheel.standardStep,
               !steps.contains(where: { abs($0.stops - current.stops) <= ExposureCalculator.stabilityEpsilon }) {
                steps.append(current)
                steps.sort { $0.stops < $1.stops }
            }
            return steps.map { step in
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
            for item in Self.wheelOrder(filterSet.ndItems) {
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

    /// An ND wheel's item rows, weakest to strongest by canonical stops
    /// (FILTER-STACK-003), independent of the Filter Set list order;
    /// equal stops fall back to the locale-aware name, then the id.
    static func wheelOrder(_ items: [FilterItem]) -> [FilterItem] {
        items.sorted { lhs, rhs in
            let lhsStops = lhs.behavior.registeredValue?.canonicalStops ?? 0
            let rhsStops = rhs.behavior.registeredValue?.canonicalStops ?? 0
            if lhsStops != rhsStops {
                return lhsStops < rhsStops
            }
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            case .orderedSame:
                return lhs.id.rawValue < rhs.id.rawValue
            }
        }
    }

    // MARK: Adding wheels

    /// Whether another ND wheel fits under the applicable limit
    /// (FILTER-STACK-001).
    public var canAddWheel: Bool {
        wheels.count < wheelLimit
    }

    /// Why `source` cannot add a usable wheel right now, or `nil` when
    /// it can: the applicable wheel limit, or no unmounted ND item of
    /// the set whose value fits the remaining budget.
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
            let ndItems = filterSet.ndItems
            guard !ndItems.isEmpty else {
                return .filterSetHasNoItems
            }
            let mounted = mountedItemIDs(excludingWheelAt: nil)
            let unmounted = ndItems.filter { !mounted.contains($0.id) }
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

    // MARK: Replacing the mounted auxiliary filters

    /// Writes the complete mounted auxiliary selection at once
    /// (FILTER-AUX-003 Apply). Rejected — leaving the stack unchanged —
    /// when a mount does not resolve, a physical item would be mounted
    /// twice (across auxiliary filters and wheels), the current ND
    /// wheels exceed the limit that applies with auxiliary filters, or
    /// the combined contributions would exceed 30 stops. Any number of
    /// auxiliary filters may be mounted; they are kept in display
    /// order. Existing ND wheels are never removed or merged to make
    /// room.
    public func replacingAuxiliaryFilters(with mounts: [MountedAuxiliaryFilter], inventory: FilterInventory) -> Result<FilterStack, FilterStackRejection> {
        var resolved: [ResolvedAuxiliaryFilter] = []
        var mounted = Set(wheels.compactMap(\.mountedItemID))
        for mount in mounts {
            guard let row = Self.resolvedAuxiliaryFilter(mount, inventory: inventory) else {
                return .failure(.unresolvedSelection)
            }
            guard mounted.insert(mount.itemID).inserted else {
                return .failure(.itemAlreadyMounted)
            }
            resolved.append(row)
        }
        guard wheels.count <= Self.wheelLimit(hasAuxiliaryFilters: !mounts.isEmpty) else {
            return .failure(.tooManyNDWheels)
        }
        guard Self.isWithinTotalLimit(contributions + resolved.map(\.contributionStops)) else {
            return .failure(.exceedsTotalLimit)
        }
        let ordered = Self.displayOrdered(resolved, inventory: inventory)
        var copy = self
        copy.auxiliaryFilters = ordered.map(\.mount)
        copy.auxiliaryRows = ordered
        return .success(copy)
    }

    // MARK: Post-commit ordering

    /// A row's sort value (FILTER-STACK-005): a Standard row's selected
    /// stops, a Fixed row's registered canonical stops, a CPL row's
    /// selected exposure-loss choice, a GND row's registered full
    /// density in BOTH modes (so a mode change never moves it), and
    /// zero for Empty and Standard 0.
    func sortValue(forWheelAt index: Int) -> Double {
        wheels[index].isCleanable ? 0 : rows[index].registeredStops
    }

    /// Registered subtotal of one source group: the sum of the sort
    /// values of every wheel from `source`. Zero for a source with no
    /// wheel in the stack.
    func registeredSubtotal(of source: FilterSource) -> Double {
        wheels.indices.reduce(0.0) { partial, index in
            wheels[index].source == source ? partial + sortValue(forWheelAt: index) : partial
        }
    }

    /// Permutation of the current indices in commit order
    /// (FILTER-STACK-005): wheels from one source stay contiguous and
    /// source groups sort by registered subtotal descending; equal
    /// subtotals put Standard first and then follow the user-defined
    /// Filter Set order. Within one group, non-empty rows sort by the
    /// same row value descending with stable ties; Empty (and Standard
    /// 0) last.
    public func commitSortPermutation(inventory: FilterInventory) -> [Int] {
        var subtotals: [FilterSource: Double] = [:]
        for source in Set(wheels.map(\.source)) {
            subtotals[source] = registeredSubtotal(of: source)
        }
        return wheels.indices.sorted { lhs, rhs in
            let lhsSource = wheels[lhs].source
            let rhsSource = wheels[rhs].source
            if lhsSource != rhsSource {
                let lhsSubtotal = subtotals[lhsSource] ?? 0
                let rhsSubtotal = subtotals[rhsSource] ?? 0
                if abs(lhsSubtotal - rhsSubtotal) > ExposureCalculator.stabilityEpsilon {
                    return lhsSubtotal > rhsSubtotal
                }
                return inventory.sourceOrderIndex(of: lhsSource) < inventory.sourceOrderIndex(of: rhsSource)
            }
            let lhsEmpty = wheels[lhs].isCleanable
            let rhsEmpty = wheels[rhs].isCleanable
            if lhsEmpty != rhsEmpty {
                return !lhsEmpty
            }
            let lhsKey = sortValue(forWheelAt: lhs)
            let rhsKey = sortValue(forWheelAt: rhs)
            if abs(lhsKey - rhsKey) > ExposureCalculator.stabilityEpsilon {
                return lhsKey > rhsKey
            }
            return lhs < rhs
        }
    }

    /// Wheels in commit order; the auxiliary filters stay as they are
    /// (FILTER-STACK-005: they never take part in ND ordering).
    public func sortedForCommit(inventory: FilterInventory) -> FilterStack {
        let permutation = commitSortPermutation(inventory: inventory)
        return FilterStack(
            wheels: permutation.map { wheels[$0] },
            rows: permutation.map { rows[$0] },
            auxiliaryFilters: auxiliaryFilters,
            auxiliaryRows: auxiliaryRows
        )
    }
}

/// The stack after `FilterStack.reassigningRoles`: wheels and mounted
/// auxiliary filters with every selection in its item's current role,
/// plus, per returned wheel, the index of the input wheel it came from
/// (`nil` for a wheel created from an auxiliary mount).
public struct RoleReassignment: Equatable, Sendable {
    public let wheels: [FilterWheel]
    public let auxiliaryFilters: [MountedAuxiliaryFilter]
    public let wheelOrigins: [Int?]
}

extension FilterStack {
    /// Role correction after an item's kind changes (FILTER-ITEM-003,
    /// FILTER-ITEM-005): a selection follows its physical item into the
    /// item's new role instead of being dropped. A wheel mounting an
    /// item that is now auxiliary leaves the ND row and the item is
    /// mounted as an auxiliary filter with its default choice (a legacy
    /// CPL / GND wheel row keeps its choice); an auxiliary mount whose
    /// item is now ND becomes a Filter Set ND wheel at the end of the
    /// row; an auxiliary mount whose item changed to another auxiliary
    /// kind takes that kind's default choice. A moved item is judged
    /// against the camera's selected Filter Sets (`selectedFilterSetIDs`)
    /// before the move: into a selected Set, a wheel keeps the item under
    /// that Set and an auxiliary mount follows it; into a Set the camera
    /// does not select, the ND wheel becomes Empty under its original
    /// source in the same position and the auxiliary mount is unmounted,
    /// so the move never selects the destination (FILTER-ITEM-005/009). Mounts of unknown sets or items
    /// are left for normal re-resolution. A result with no wheel gets
    /// one Standard 0 wheel. `wheelOrigins` gives, per returned wheel,
    /// the index of the input wheel it came from (`nil` for a new
    /// wheel). Limits are not checked here; callers validate.
    public static func reassigningRoles(
        wheels inputWheels: [FilterWheel],
        auxiliaryFilters inputAuxiliaryFilters: [MountedAuxiliaryFilter],
        selectedFilterSetIDs: [FilterSetID],
        inventory: FilterInventory
    ) -> RoleReassignment {
        func item(_ itemID: FilterItemID, in filterSetID: FilterSetID) -> FilterItem? {
            inventory.filterSet(withID: filterSetID)?.item(withID: itemID)
        }
        let wheels = inputWheels.map { rehomed($0, inventory: inventory) }
        let selected = Set(selectedFilterSetIDs)
        // A mount whose item moved to a Set the camera does not select is
        // unchecked, whatever its kind is now; the Set is not selected.
        let auxiliaryFilters = inputAuxiliaryFilters.compactMap { input -> MountedAuxiliaryFilter? in
            let mount = rehomed(input, inventory: inventory)
            guard mount.filterSetID != input.filterSetID, !selected.contains(mount.filterSetID) else {
                return mount
            }
            return nil
        }
        var keptWheels: [FilterWheel] = []
        var origins: [Int?] = []
        var mounts = auxiliaryFilters
        for (index, wheel) in wheels.enumerated() {
            let moved = inputWheels[index].source != wheel.source
            // An ND item moved to a Set the camera does not select leaves
            // its wheel Empty under the original source, with the same
            // identity; the destination is not selected (FILTER-ITEM-005).
            if moved,
               let destination = wheel.source.filterSetID,
               !selected.contains(destination),
               case .item(let selection) = wheel.selection,
               item(selection.itemID, in: destination)?.behavior.kind.isAuxiliary == false {
                keptWheels.append(FilterWheel(source: inputWheels[index].source, selection: .empty))
                origins.append(index)
                continue
            }
            if case .item(let selection) = wheel.selection,
               let filterSetID = wheel.source.filterSetID,
               let mountedItem = item(selection.itemID, in: filterSetID),
               mountedItem.behavior.kind.isAuxiliary {
                // Now auxiliary and moved to a Set the camera does not select:
                // unchecked like any moved auxiliary item (FILTER-ITEM-009).
                if !(moved && !selected.contains(filterSetID)),
                   !mounts.contains(where: { $0.itemID == selection.itemID }),
                   let choice = carriedChoice(selection.choice, for: mountedItem) ?? MountedAuxiliaryFilter.initialChoice(for: mountedItem) {
                    mounts.append(MountedAuxiliaryFilter(filterSetID: filterSetID, itemID: selection.itemID, choice: choice))
                }
                continue
            }
            keptWheels.append(wheel)
            origins.append(index)
        }
        var keptMounts: [MountedAuxiliaryFilter] = []
        for mount in mounts {
            guard let mountedItem = item(mount.itemID, in: mount.filterSetID) else {
                keptMounts.append(mount)
                continue
            }
            if !mountedItem.behavior.kind.isAuxiliary {
                keptWheels.append(FilterWheel(
                    source: .filterSet(mount.filterSetID),
                    selection: .item(FilterRowSelection(itemID: mount.itemID, choice: .fixed))
                ))
                origins.append(nil)
            } else if !choice(mount.choice, fitsKindOf: mountedItem),
                      let choice = MountedAuxiliaryFilter.initialChoice(for: mountedItem) {
                keptMounts.append(MountedAuxiliaryFilter(filterSetID: mount.filterSetID, itemID: mount.itemID, choice: choice))
            } else {
                keptMounts.append(mount)
            }
        }
        if keptWheels.isEmpty {
            keptWheels = [.standard(NDStep(stops: 0))]
            origins = [nil]
        }
        return RoleReassignment(wheels: keptWheels, auxiliaryFilters: keptMounts, wheelOrigins: origins)
    }

    /// A wheel mounting an item that now lives in another Filter Set,
    /// moved to that set with the same selection (FILTER-ITEM-009).
    private static func rehomed(_ wheel: FilterWheel, inventory: FilterInventory) -> FilterWheel {
        guard case .item(let selection) = wheel.selection,
              let filterSetID = wheel.source.filterSetID,
              inventory.filterSet(withID: filterSetID)?.item(withID: selection.itemID) == nil,
              let owner = inventory.item(withID: selection.itemID)?.filterSet else {
            return wheel
        }
        return FilterWheel(source: .filterSet(owner.id), selection: wheel.selection)
    }

    /// A mount of an item that now lives in another Filter Set, moved
    /// to that set with the same choice (FILTER-ITEM-009).
    private static func rehomed(_ mount: MountedAuxiliaryFilter, inventory: FilterInventory) -> MountedAuxiliaryFilter {
        guard inventory.filterSet(withID: mount.filterSetID)?.item(withID: mount.itemID) == nil,
              let owner = inventory.item(withID: mount.itemID)?.filterSet else {
            return mount
        }
        return MountedAuxiliaryFilter(filterSetID: owner.id, itemID: mount.itemID, choice: mount.choice)
    }

    /// A legacy wheel row's CPL or GND choice, when it matches the
    /// item's current kind.
    private static func carriedChoice(_ choice: FilterRowChoice, for item: FilterItem) -> AuxiliaryFilterChoice? {
        switch (choice, item.behavior) {
        case (.cplLoss(let loss), .cpl):
            return .cplLoss(loss)
        case (.gnd(let mode), .gnd):
            return .gnd(mode)
        default:
            return nil
        }
    }

    /// Whether an auxiliary choice belongs to the item's kind; a CPL
    /// value that is no longer configured still counts as the CPL kind,
    /// so it is reported by re-resolution instead of being replaced.
    private static func choice(_ choice: AuxiliaryFilterChoice, fitsKindOf item: FilterItem) -> Bool {
        switch (choice, item.behavior) {
        case (.cplLoss, .cpl), (.gnd, .gnd), (.registeredLoss, .color), (.registeredLoss, .effect):
            return true
        default:
            return false
        }
    }
}
