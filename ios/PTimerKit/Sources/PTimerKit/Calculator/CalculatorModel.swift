// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import PTimerCore

/// `CalculatorModel` owns the calculator slice: the pure ND exposure
/// math engine, the user's calculation inputs (`baseShutterSeconds`,
/// `ndStop`), the live preview overlays for in-flight wheel gestures,
/// and the `calculationResult` derived from those inputs.
@MainActor
@Observable
public final class CalculatorModel {
    /// Full-stop shutter ladder kept as a stable legacy static so
    /// existing callers (persistence sanitizers, snap-to-full-stop
    /// logic, regression suites) keep reading the 19-value ladder
    /// regardless of which scale the shipping calculator currently
    /// uses. Sourced explicitly from `.fullStop` rather than
    /// `.default` so a future flip of `.default` does not silently
    /// reshape this static.
    public nonisolated static let shutterSpeeds = ExposureScale.fullStop.shutterSteps.map(\.seconds)

    /// The pure calculation engine, shared with the view-model facade
    /// so direct call sites (`calculator.formatShutter`, etc.) reach
    /// the same instance.
    public let calculator: ExposureCalculator

    /// Active exposure-scale mode. The shipping calculator runs on
    /// `.oneThirdStop`; the field is mutable so tests and the future
    /// Settings preference can flip the active scale without
    /// redesigning the model. The shipping UI does not surface a
    /// runtime selector for this field.
    public var scaleMode: ExposureScaleMode {
        didSet {
            // Re-snap committed and live ND values onto the new scale's
            // ladder so a scale flip does not leave stale fractional
            // or whole values that are illegal on the active scale.
            // All stacked wheels re-snap, not just wheel 0
            // (PTIMER-199).
            //
            // Nearest-snapping can round several wheels UP and push a
            // legal sum past the 30-stop cap (reserved fractional
            // path, e.g. 10⅔+10⅔+8⅔ = 30 → 11+11+9 = 31), which the
            // stack's invariant treats as a programmer error.
            // Deterministic overflow policy: downgrade wheels to
            // their FLOOR-snapped value from the RIGHTMOST side until
            // the sum fits. Flooring every wheel bounds the sum by
            // the original (legal) sum, so this always terminates
            // within the cap — no crash, no clamp of the whole stack.
            //
            // Filter Set wheels are untouched: their values are
            // user-registered, never ladder values (Filter Set
            // contract), so only Standard wheels re-snap.
            let originals = filterStack.wheels
            var snapped = originals.map { wheel -> FilterWheel in
                guard let step = wheel.standardStep else { return wheel }
                return .standard(sanitizedNDStep(step, for: scaleMode))
            }
            if FilterStack.validated(wheels: snapped, inventory: filterInventory) == nil {
                for index in snapped.indices.reversed() {
                    guard FilterStack.validated(wheels: snapped, inventory: filterInventory) == nil,
                          let original = originals[index].standardStep else {
                        continue
                    }
                    snapped[index] = .standard(sanitizedNDStepRoundingDown(original, for: scaleMode))
                }
            }
            if let restacked = FilterStack.validated(wheels: snapped, inventory: filterInventory) {
                filterStack = restacked
            }
            liveSelections = liveSelections.mapValues { selection in
                guard case .standard(let step) = selection else { return selection }
                return .standard(sanitizedNDStep(step, for: scaleMode))
            }

            // Same reasoning for the shutter ladder: a scale flip
            // away from the active ladder must collapse the committed
            // shutter value onto the nearest entry on the new ladder,
            // otherwise the wheel index would point at a value the
            // picker no longer enumerates.
            baseShutterSeconds = sanitizedShutter(baseShutterSeconds, for: scaleMode)
            if let live = liveBaseShutter {
                liveBaseShutter = sanitizedShutter(live, for: scaleMode)
            }
        }
    }

    /// Active exposure scale derived from `scaleMode`. Reading the
    /// scale registers an observation on `scaleMode`, so the picker
    /// data sources (`pickerShutterStepSeconds` / `pickerWholeNDStops`)
    /// flip atomically when the mode changes.
    public var exposureScale: ExposureScale {
        ExposureScale.scale(for: scaleMode)
    }

    /// Shutter ladder shown by the picker. Reads from the active
    /// scale so swapping `scaleMode` flips the picker without any
    /// view-side conditional.
    public var pickerShutterStepSeconds: [Double] {
        exposureScale.shutterSteps.map(\.seconds)
    }

    /// Whole-stop subset of the ND ladder, for callers still bound to
    /// `Int`. The shipping ND ladder is whole stops plus the three
    /// commercial fractional presets (per `docs/specs/Calculator.md`
    /// §2.2); this helper drops the presets and returns only the
    /// whole-stop values. The fractional-aware `pickerNDSteps` surface
    /// is the canonical source for the SwiftUI picker; both views are
    /// kept for the legacy integer binding compatibility.
    public var pickerWholeNDStops: [Int] {
        exposureScale.ndSteps.compactMap(\.wholeStops)
    }

    /// Working base shutter in seconds. Persisted committed value;
    /// the live preview overlay (`liveBaseShutter`) takes precedence
    /// for `effectiveBaseShutter` while the user is dragging the wheel.
    public var baseShutterSeconds: Double

    /// The mixed Filter Stack (Filter Set contract, generalizing the
    /// PTIMER-199 Standard stack): 1–4 committed wheels drawn from
    /// Standard and Filter Set sources in display order, collapsing to
    /// one effective summed value. Shape rules (add/remove/sort/budget/
    /// exclusivity) live on the domain type; the model owns lifecycle
    /// and observation.
    public private(set) var filterStack = FilterStack(single: NDStep(stops: 0))

    /// Resolution input for Filter Set wheels — a read-only mirror of
    /// the inventory owned by `FilterInventoryModel`, refreshed by the
    /// facade through `applyFilterInventory(_:)`. Never mutated here.
    public private(set) var filterInventory: FilterInventory = .empty

    /// The active slot's last settled Filter Source — what the Plus
    /// wheel adds next. Per camera; the facade carries it through slot
    /// snapshots.
    public private(set) var lastFilterSource: FilterSource = .standard

    /// Stable per-wheel identity (PTIMER-199 §4.3): `ndFilterWheelIDs[i]`
    /// names the wheel at `filterWheels[i]` and follows it through
    /// the commit sort, so the UI can render a reorder as wheels
    /// MOVING rather than values teleporting between columns.
    /// Presentation-side bookkeeping only — never persisted, never
    /// part of the calculation. IDs start at 101 and increase
    /// monotonically (user rule, PTIMER-199 v2): a value ≥ 101 can
    /// never be mistaken for a position index, IDs are never derived
    /// from positions, and a removed ID is never reused within a
    /// generation (the monotonic counter guarantees it).
    public private(set) var ndFilterWheelIDs: [Int] = [101]
    private var nextNDFilterWheelID = 102

    private func makeNDFilterWheelID() -> Int {
        defer { nextNDFilterWheelID += 1 }
        return nextNDFilterWheelID
    }

    private func regenerateNDFilterWheelIDs() {
        ndFilterWheelIDs = filterStack.wheels.map { _ in makeNDFilterWheelID() }
    }

    /// Per-wheel active contributions in display order (1–4): a
    /// Standard wheel's value, or a Filter Set row's contribution (0
    /// for Empty and Record only). Convenience projection of
    /// `filterStack`.
    public var ndFilterSteps: [NDStep] {
        filterStack.contributions.map(NDStep.init(stops:))
    }

    /// The wheels themselves — source and selection per wheel.
    public var filterWheels: [FilterWheel] {
        filterStack.wheels
    }

    /// Resolved rows parallel to `filterWheels`.
    public var filterRows: [ResolvedFilterRow] {
        filterStack.rows
    }

    /// Canonical ND input as a fractional-aware `NDStep`. ONE meaning
    /// for every caller (PTIMER-199): reading returns the stack's
    /// EFFECTIVE (summed) value — the value the calc engine consumes.
    /// Writing is the single-filter assignment surface kept for
    /// compatibility (legacy `ndStop` mirror, persistence restore,
    /// tests): it replaces the whole stack with one Standard wheel
    /// holding the value. Per-wheel writes go through
    /// `setWheelSelection(_:at:)`.
    public var ndStep: NDStep {
        get { filterStack.effectiveStep }
        set {
            filterStack = FilterStack(single: newValue)
            regenerateNDFilterWheelIDs()
        }
    }

    /// Replaces the resolution inventory and re-resolves the committed
    /// stack against it: a wheel whose Filter Set vanished is dropped
    /// (its identity with it), an item that vanished reads Empty, a
    /// stale last source falls back to Standard. Should the resolved
    /// contributions no longer fit the cap — the facade blocks such
    /// edits up front — every mounted item reads Empty instead of
    /// clamping any value.
    public func applyFilterInventory(_ inventory: FilterInventory) {
        filterInventory = inventory
        var wheels: [FilterWheel] = []
        var ids: [Int] = []
        for (index, wheel) in filterStack.wheels.enumerated() {
            guard let normalized = FilterStack.normalizedWheel(wheel, inventory: inventory) else {
                continue
            }
            wheels.append(normalized)
            ids.append(ndFilterWheelIDs.indices.contains(index) ? ndFilterWheelIDs[index] : makeNDFilterWheelID())
        }
        if wheels.isEmpty {
            wheels = [.standard(NDStep(stops: 0))]
            ids = [makeNDFilterWheelID()]
        }
        var mounted: Set<FilterItemID> = []
        wheels = wheels.map { wheel in
            guard let itemID = wheel.mountedItemID, !mounted.insert(itemID).inserted else { return wheel }
            return FilterWheel(source: wheel.source, selection: .empty)
        }
        if let stack = FilterStack.validated(wheels: wheels, inventory: inventory) {
            filterStack = stack
        } else {
            let emptied = wheels.map { wheel -> FilterWheel in
                wheel.isStandard ? wheel : FilterWheel(source: wheel.source, selection: .empty)
            }
            filterStack = FilterStack.validated(wheels: emptied, inventory: inventory)
                ?? FilterStack(single: CalculatorDefaults.ndStep)
            if filterStack.wheels.count != ids.count {
                ids = filterStack.wheels.map { _ in makeNDFilterWheelID() }
            }
        }
        ndFilterWheelIDs = ids
        liveSelections = liveSelections.filter { ndFilterWheelIDs.contains($0.key) }
        if !inventory.contains(lastFilterSource) {
            lastFilterSource = .standard
        }
    }

    /// Settles the Plus wheel on `source`. Unknown Filter Sets are
    /// refused; merely changing the source never touches the stack.
    public func selectFilterSource(_ source: FilterSource) {
        guard filterInventory.contains(source) else {
            return
        }
        lastFilterSource = source
    }

    /// Commits one wheel of the stack, then applies the agreed
    /// post-commit ordering (Standard first, Filter Sets in user order;
    /// descending within a source, Empty last, stable). Commits only
    /// happen once a wheel has settled, so sorting here never reorders
    /// mid-scroll. Returns the rejection when the domain refuses the
    /// write (over the cap, item mounted elsewhere, unresolved row) —
    /// the stack is unchanged in that case. Out-of-range indices are
    /// ignored (defensive: the UI only offers existing wheels).
    @discardableResult
    public func setWheelSelection(_ selection: FilterWheelSelection, at index: Int) -> FilterStackRejection? {
        guard filterStack.wheels.indices.contains(index) else {
            return nil
        }
        switch filterStack.replacingWheel(at: index, with: selection, inventory: filterInventory) {
        case .success(let replaced):
            let permutation = replaced.commitSortPermutation(inventory: filterInventory)
            filterStack = replaced.sortedForCommit(inventory: filterInventory)
            ndFilterWheelIDs = permutation.map { ndFilterWheelIDs[$0] }
            return nil
        case .failure(let rejection):
            return rejection
        }
    }

    /// Standard-wheel commit (legacy surface, tests): the same write
    /// path as `setWheelSelection(.standard(step), at:)`.
    public func setNDFilterStep(_ step: NDStep, at index: Int) {
        setWheelSelection(.standard(step), at: index)
    }

    /// Why `source` cannot add a usable wheel right now (`nil` when it
    /// can): below four wheels AND the new wheel could hold a usable
    /// row — for Standard a ladder value above 0 (PTIMER-199 C1), for a
    /// Filter Set an unmounted item whose row fits the remaining
    /// budget (a Record-only row fits even at the 30-stop total).
    public func filterAddUnavailability(for source: FilterSource) -> FilterAddUnavailability? {
        filterStack.addUnavailability(for: source, inventory: filterInventory, scale: exposureScale)
    }

    /// Whether another wheel can be added for the settled last source
    /// (PTIMER-199 C1 generalized). Drives the Plus control and the
    /// "Add filter" accessibility action.
    public var canAddFilterWheel: Bool {
        filterAddUnavailability(for: lastFilterSource) == nil
    }

    /// Whether a wheel can be removed: more than one wheel AND at
    /// least one cleanable wheel (Standard 0 or Empty; a mounted
    /// Record-only item is never removed).
    public var canRemoveEmptyFilterWheel: Bool {
        filterStack.canRemoveEmptyWheel
    }

    /// Appends one wheel for the settled last source — Standard 0 or
    /// Filter Set Empty. The availability rule is enforced HERE, not
    /// just on the Plus affordance: a direct command call is refused
    /// (no-op) whenever the new wheel could not hold a usable row.
    public func addFilterWheel() {
        addFilterWheel(for: lastFilterSource)
    }

    public func addFilterWheel(for source: FilterSource) {
        guard filterAddUnavailability(for: source) == nil else {
            return
        }
        filterStack = filterStack.addingWheel(for: source, inventory: filterInventory)
        ndFilterWheelIDs.append(makeNDFilterWheelID())
    }

    /// A2 cleanup (PTIMER-199 §4.2.2): removes every CLEANABLE wheel
    /// — all Standard 0 / Empty wheels while a non-cleanable wheel
    /// exists; all but one when every wheel is cleanable.
    public func cleanupEmptyFilterWheels() {
        while canRemoveEmptyFilterWheel {
            removeEmptyFilterWheel()
        }
    }

    /// Whether the cleanable wheel at `index` could still accept a
    /// usable row: a Standard 0 wheel needs a ladder value above 0 in
    /// its remaining budget; an Empty Filter Set wheel needs any
    /// selectable item row (a Record-only row counts, so an Empty
    /// wheel stays usable even at the 30-stop total — FILTER-PLUS-005).
    public func cleanableWheelIsUsable(at index: Int) -> Bool {
        guard filterStack.wheels.indices.contains(index), filterStack.wheels[index].isCleanable else {
            return false
        }
        return rowOptions(forWheel: index).contains { option in
            guard option.isAvailable else { return false }
            switch option.selection {
            case .standard(let step): return step.stops > 0
            case .empty: return false
            case .item: return true
            }
        }
    }

    /// Whether an immediately removable wheel exists: cleanable AND
    /// unable to accept any usable row (ND-CLEANUP-003 at budget
    /// saturation), while keeping at least one wheel.
    public var canRemoveUnusableEmptyFilterWheel: Bool {
        filterStack.wheels.count > 1
            && filterStack.wheels.indices.contains { filterStack.wheels[$0].isCleanable && !cleanableWheelIsUsable(at: $0) }
    }

    /// A0 cleanup (ND-CLEANUP-003 generalized): removes every cleanable
    /// wheel that could not hold a usable row, keeping at least one
    /// wheel. An Empty Filter Set wheel with a fitting row (e.g. a
    /// Record-only item at the cap) is left to the idle cleanup rule.
    public func cleanupUnusableEmptyFilterWheels() {
        while canRemoveUnusableEmptyFilterWheel,
              let index = filterStack.wheels.indices.last(where: {
                  filterStack.wheels[$0].isCleanable && !cleanableWheelIsUsable(at: $0)
              }) {
            removeEmptyFilterWheel(at: index)
        }
    }

    /// Removes the cleanable wheel at `index` — the overscroll
    /// gesture's target (§4.2.3): exactly the wheel the photographer
    /// pulled, not the rightmost one. No-op when the index is not a
    /// removable cleanable wheel.
    public func removeEmptyFilterWheel(at index: Int) {
        let countBefore = filterStack.wheels.count
        filterStack = filterStack.removingEmptyWheel(at: index)
        if filterStack.wheels.count < countBefore {
            ndFilterWheelIDs.remove(at: index)
        }
    }

    /// Removes the rightmost cleanable wheel (no-op when unavailable).
    public func removeEmptyFilterWheel() {
        let removedIndex = filterStack.wheels.lastIndex(where: \.isCleanable)
        let countBefore = filterStack.wheels.count
        filterStack = filterStack.removingRightmostEmptyWheel()
        if filterStack.wheels.count < countBefore, let removedIndex {
            ndFilterWheelIDs.remove(at: removedIndex)
        }
    }

    /// Restores a Standard-only wheel stack (legacy restore surface).
    public func restoreNDFilterSteps(_ steps: [NDStep]) {
        restoreFilterWheels(steps.map(FilterWheel.standard), lastFilterSource: .standard)
    }

    /// Restores a mixed wheel stack from persistence or a slot switch.
    /// The caller supplies pre-validated wheels; this guard is the
    /// last defensive shield so corrupted input can never trip the
    /// domain type's programmer-error preconditions — a violating
    /// stack restores as the default single wheel instead (reject,
    /// never clamp). A last source the inventory no longer knows
    /// falls back to Standard.
    public func restoreFilterWheels(_ wheels: [FilterWheel], lastFilterSource source: FilterSource) {
        clearLiveNDStopPreview()
        if let normalized = FilterStack.normalizedWheels(wheels, inventory: filterInventory),
           let stack = FilterStack.validated(wheels: normalized, inventory: filterInventory) {
            filterStack = stack
        } else {
            filterStack = FilterStack(single: CalculatorDefaults.ndStep)
        }
        regenerateNDFilterWheelIDs()
        lastFilterSource = filterInventory.contains(source) ? source : .standard
    }

    /// Picker rows for one wheel — the single source for what a wheel
    /// can select. Standard wheels get the active scale's ND ladder
    /// truncated from the top to the remaining budget; Filter Set
    /// wheels get Empty plus the set's item rows with per-row
    /// unavailability. Derives from COMMITTED values only, so sibling
    /// rows never reload while another wheel is being dragged.
    public func rowOptions(forWheel index: Int) -> [FilterWheelRowOption] {
        filterStack.rowOptions(forWheelAt: index, inventory: filterInventory, scale: exposureScale)
    }

    /// Standard ladder for a Standard wheel (legacy surface). Returns
    /// the full ladder for an out-of-range index and an empty list for
    /// a Filter Set wheel.
    public func pickerNDSteps(forWheel index: Int) -> [NDStep] {
        guard filterStack.wheels.indices.contains(index) else {
            return exposureScale.ndSteps
        }
        guard filterStack.wheels[index].isStandard else {
            return []
        }
        return rowOptions(forWheel: index).compactMap { option in
            if case .standard(let step) = option.selection {
                return step
            }
            return nil
        }
    }

    /// Working ND stop, integer-binding compatibility wrapper around
    /// `ndStep`. Setting writes a whole-stop `NDStep`; reading
    /// returns the whole-stop equivalent (rounded for any fractional
    /// value). The wrapper is kept for the integer binding
    /// compatibility surface; the canonical `ndStep` is the
    /// fractional-aware source of truth.
    public var ndStop: Int {
        get { ndStep.wholeStops ?? Int(ndStep.stops.rounded()) }
        set { ndStep = NDStep(stops: Double(newValue)) }
    }

    /// Transient base shutter shown while the user drags the wheel,
    /// before the gesture commits to `baseShutterSeconds`. Cleared by
    /// `clearLiveBaseShutterPreview()` or implicitly when the preview
    /// equals the committed value.
    public var liveBaseShutter: Double?

    /// Transient per-wheel selections shown while wheels are in
    /// motion, before the epoch's set commit (PTIMER-199 §4.5).
    /// Several wheels can be live at once (multi-touch / overlapping
    /// flings): each entry overlays that wheel's committed selection
    /// in `effectiveNDStep`. Keys are WHEEL IDENTITY values
    /// (`ndFilterWheelIDs` entries), never positions (PTIMER-199 v2
    /// 계약 3): entries survive the commit sort untouched because
    /// identity moves with the wheel.
    public private(set) var liveSelections: [Int: FilterWheelSelection] = [:]

    /// Legacy projection of `liveSelections`: each live wheel's
    /// contribution in stops, keyed by wheel identity.
    public var liveNDSteps: [Int: NDStep] {
        var result: [Int: NDStep] = [:]
        for (wheelID, selection) in liveSelections {
            if let contribution = liveContribution(of: selection, forWheelID: wheelID) {
                result[wheelID] = NDStep(stops: contribution)
            }
        }
        return result
    }

    /// Which wheel the LAST live update touched. Backs the legacy
    /// single-overlay projection below; wheel 0 for the
    /// single-filter workflow and all legacy callers.
    private var liveNDWheelID = 0

    /// Legacy single-overlay view of the live preview: the most
    /// recently updated wheel's live Standard value. Kept so pre-stack
    /// callers and the integer wrapper keep compiling; multi-wheel-
    /// aware callers read `liveSelections` directly.
    public var liveNDStep: NDStep? {
        get {
            guard case .standard(let step)? = liveSelections[liveNDWheelID] else {
                return nil
            }
            return step
        }
        set {
            if let newValue {
                liveSelections[liveNDWheelID] = .standard(newValue)
            } else {
                liveSelections.removeValue(forKey: liveNDWheelID)
            }
        }
    }

    /// Integer-binding compatibility wrapper around `liveNDStep` for
    /// the existing whole-stop drag gesture. Setting writes a
    /// whole-stop `NDStep`; reading returns the whole-stop equivalent.
    public var liveNDStop: Int? {
        get { liveNDStep?.wholeStops ?? liveNDStep.map { Int($0.stops.rounded()) } }
        set { liveNDStep = newValue.map { NDStep(stops: Double($0)) } }
    }

    /// Effective base shutter — the value the calculator actually uses.
    /// Returns the live preview when set, otherwise the committed value.
    public var effectiveBaseShutter: Double {
        liveBaseShutter ?? baseShutterSeconds
    }

    /// Contribution of a live (uncommitted) selection on the wheel
    /// `wheelID`, resolved against the wheel's source. `nil` when the
    /// selection does not belong to that wheel.
    private func liveContribution(of selection: FilterWheelSelection, forWheelID wheelID: Int) -> Double? {
        guard let index = ndFilterWheelIDs.firstIndex(of: wheelID),
              filterStack.wheels.indices.contains(index) else {
            return nil
        }
        let wheel = FilterWheel(source: filterStack.wheels[index].source, selection: selection)
        return FilterStack.resolvedRow(for: wheel, inventory: filterInventory)?.contributionStops
    }

    /// Effective ND step — the value the calculator actually uses:
    /// the stack's sum, with each moving wheel's live contribution
    /// substituted for its committed one while a preview is active
    /// (PTIMER-199 §4.5: live wheel + committed others).
    public var effectiveNDStep: NDStep {
        guard !liveSelections.isEmpty else {
            return filterStack.effectiveStep
        }
        // Sum of every wheel's current value: live overlay when the
        // wheel is in motion, committed value otherwise. During a
        // multi-wheel epoch the frozen rows can transiently allow a
        // combined sum above the 30-stop cap; the display shows the
        // actual transient sum and the set commit resolves it by
        // rejection (§4.5).
        let total = filterStack.rows.enumerated().reduce(0.0) { sum, entry in
            let wheelID = ndFilterWheelIDs.indices.contains(entry.offset)
                ? ndFilterWheelIDs[entry.offset] : -1
            let live = liveSelections[wheelID].flatMap { liveContribution(of: $0, forWheelID: wheelID) }
            return sum + (live ?? entry.element.contributionStops)
        }
        return NDStep(stops: total)
    }

    /// Whole-stop view of `effectiveNDStep`, kept for callers still
    /// bound to the legacy `Int` ND surface. Exact for whole-stop
    /// selections; the three commercial presets and any reserved-path
    /// third-stop value round to the nearest integer here, so callers
    /// that need the true fractional value must read `effectiveNDStep`.
    public var effectiveNDStop: Int {
        effectiveNDStep.wholeStops ?? Int(effectiveNDStep.stops.rounded())
    }

    public init(
        calculator: ExposureCalculator,
        baseShutterSeconds: Double = 1.0 / 30.0,
        ndStep: NDStep = NDStep(stops: 0),
        scaleMode: ExposureScaleMode = .oneThirdStop
    ) {
        self.calculator = calculator
        self.baseShutterSeconds = baseShutterSeconds
        self.filterStack = FilterStack(single: ndStep)
        self.scaleMode = scaleMode
    }

    /// Convenience init for the legacy `(ndStop: Int, exposureScale:
    /// ExposureScale)` shape. Wraps `ndStop` in a whole-stop `NDStep`
    /// and derives `scaleMode` from the supplied scale so PTIMER-79
    /// call sites compile without changes.
    public convenience init(
        calculator: ExposureCalculator,
        baseShutterSeconds: Double = 1.0 / 30.0,
        ndStop: Int,
        exposureScale: ExposureScale = .default
    ) {
        self.init(
            calculator: calculator,
            baseShutterSeconds: baseShutterSeconds,
            ndStep: NDStep(stops: Double(ndStop)),
            scaleMode: exposureScale.mode
        )
    }

    /// Variant of the convenience init that accepts an explicit
    /// `exposureScale` while keeping `ndStep` zero. Lets PTIMER-79
    /// tests construct a one-third-stop model with a single argument.
    public convenience init(
        calculator: ExposureCalculator,
        exposureScale: ExposureScale
    ) {
        self.init(
            calculator: calculator,
            baseShutterSeconds: 1.0 / 30.0,
            ndStep: NDStep(stops: 0),
            scaleMode: exposureScale.mode
        )
    }

    /// Sets the live preview value. If the preview equals the committed
    /// value the overlay is cleared instead, so a wheel gesture that
    /// settles on the committed value leaves no transient state.
    public func updateLiveBaseShutter(_ value: Double) {
        liveBaseShutter = value == baseShutterSeconds ? nil : value
    }

    /// Sets the live ND-stop preview, with the same
    /// equal-clears-preview rule as `updateLiveBaseShutter`.
    /// Integer-binding compatibility wrapper around
    /// `updateLiveNDStep(_:)` for callers on the legacy `Int` surface.
    public func updateLiveNDStop(_ value: Int) {
        updateLiveNDStep(NDStep(stops: Double(value)))
    }

    /// Fractional-aware preview update for wheel 0 — the
    /// single-filter compatibility surface. Equal-clears-preview
    /// keeps the same idle-state rule as the integer overload.
    public func updateLiveNDStep(_ value: NDStep) {
        updateLiveNDFilterStep(value, forWheel: 0)
    }

    /// Per-wheel live preview (PTIMER-199): the dragging wheel's live
    /// value overlays its committed entry in `effectiveNDStep` while
    /// every other wheel keeps its committed value. A preview equal
    /// to the wheel's committed value clears the overlay, matching
    /// the single-wheel idle-state rule.
    public func updateLiveNDFilterStep(_ value: NDStep, forWheel index: Int) {
        guard filterStack.wheels.indices.contains(index),
              ndFilterWheelIDs.indices.contains(index) else {
            return
        }
        updateLiveNDStep(value, forWheelID: ndFilterWheelIDs[index])
    }

    /// Identity-keyed live Standard write (PTIMER-199 v2 계약 3) —
    /// legacy shim over `updateLiveSelection(_:forWheelID:)`.
    public func updateLiveNDStep(_ value: NDStep, forWheelID wheelID: Int) {
        updateLiveSelection(.standard(value), forWheelID: wheelID)
    }

    /// Identity-keyed live preview write — the canonical entry point
    /// for every wheel kind. A selection that does not belong to the
    /// wheel's source is ignored; a preview equal to the committed
    /// selection clears the overlay.
    public func updateLiveSelection(_ selection: FilterWheelSelection, forWheelID wheelID: Int) {
        guard let index = ndFilterWheelIDs.firstIndex(of: wheelID),
              liveContribution(of: selection, forWheelID: wheelID) != nil else {
            return
        }
        liveNDWheelID = wheelID
        if selection == filterStack.wheels[index].selection {
            liveSelections.removeValue(forKey: wheelID)
        } else {
            liveSelections[wheelID] = selection
        }
    }

    public func clearLiveBaseShutterPreview() {
        liveBaseShutter = nil
    }

    public func clearLiveNDStopPreview() {
        liveSelections.removeAll()
    }

    /// Computes the calculation result from the current inputs with the
    /// stable contract: same `Result` shape, same error mapping, same
    /// payload.
    public var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
        calculate(baseShutterSeconds: baseShutterSeconds, ndStep: ndStep)
    }

    /// Whole-stop overload of `calculate(baseShutterSeconds:ndStep:)`.
    /// Wraps `ndStop` in a whole-stop `NDStep`; preserves the byte-for-
    /// byte legacy behavior (snap-to-full-stop) for whole-stop callers.
    public func calculate(
        baseShutterSeconds: Double,
        ndStop: Int
    ) -> Result<ExposureCalculationResult, ExposureCalculatorError> {
        calculate(
            baseShutterSeconds: baseShutterSeconds,
            ndStep: NDStep(stops: Double(ndStop))
        )
    }

    /// Computes a calculation result for an arbitrary input pair using
    /// the model's current `scaleMode`. Used when callers need to
    /// evaluate `effectiveBaseShutter` / `effectiveNDStep` (the live
    /// preview overlay) without mutating the model's stored inputs.
    /// Routes through the scale-aware engine so a 1/3-stop shutter
    /// value with whole-stop ND keeps its fractional precision instead
    /// of snapping back to the full-stop ladder.
    public func calculate(
        baseShutterSeconds: Double,
        ndStep: NDStep
    ) -> Result<ExposureCalculationResult, ExposureCalculatorError> {
        do {
            let resultShutter = try calculator.calculate(
                baseShutterSeconds: baseShutterSeconds,
                ndStep: ndStep,
                scaleMode: scaleMode
            )

            return .success(
                ExposureCalculationResult(
                    baseShutterSeconds: baseShutterSeconds,
                    ndStep: ndStep,
                    resultShutterSeconds: resultShutter
                )
            )
        } catch let error as ExposureCalculatorError {
            return .failure(error)
        } catch {
            return .failure(.overflow)
        }
    }

    /// Re-snaps an `NDStep` onto the ladder for `mode`. For full-stop
    /// mode any fractional component is dropped to the nearest whole;
    /// for one-third-stop mode any value is snapped onto the third-stop
    /// grid. Centralized here so a `scaleMode` flip can keep committed
    /// and live ND values legal on the active scale.
    private func sanitizedNDStep(
        _ step: NDStep,
        for mode: ExposureScaleMode
    ) -> NDStep {
        // A value at or near an entry on the target scale's ND ladder
        // snaps to that canonical entry. This preserves the PTIMER-209
        // commercial presets (6.6, 7.6, 16.6) — which are neither whole
        // nor third-stop and would otherwise be forced off the ladder —
        // and normalizes any drift to the canonical value rather than
        // keeping a near-match double.
        let ladder = ExposureScale.scale(for: mode).ndSteps
        if let match = ladder.first(where: {
            abs($0.stops - step.stops) <= ExposureCalculator.stabilityEpsilon
        }) {
            return match
        }

        switch mode {
        case .fullStop:
            return NDStep(stops: step.stops.rounded())
        case .oneThirdStop:
            return NDStep(stops: Double((step.stops * 3).rounded()) / 3.0)
        }
    }

    /// Floor variant of `sanitizedNDStep(_:for:)`, used by the
    /// scale-flip overflow policy (PTIMER-199): rounds DOWN to the
    /// target grid so a downgraded wheel never exceeds its original
    /// value. Ladder near-matches still normalize to the canonical
    /// entry (a preset is already ≤ itself).
    private func sanitizedNDStepRoundingDown(
        _ step: NDStep,
        for mode: ExposureScaleMode
    ) -> NDStep {
        let ladder = ExposureScale.scale(for: mode).ndSteps
        if let match = ladder.first(where: {
            abs($0.stops - step.stops) <= ExposureCalculator.stabilityEpsilon
        }) {
            return match
        }

        switch mode {
        case .fullStop:
            return NDStep(stops: step.stops.rounded(.down))
        case .oneThirdStop:
            return NDStep(stops: (step.stops * 3).rounded(.down) / 3.0)
        }
    }

    /// Re-snaps a shutter value onto the ladder for `mode`. Looks up
    /// the nearest entry on the active scale's shutter ladder by
    /// absolute distance in seconds. If the ladder is empty (which
    /// should never happen for a real scale) the original value is
    /// returned unchanged.
    private func sanitizedShutter(
        _ seconds: Double,
        for mode: ExposureScaleMode
    ) -> Double {
        // Preserve non-positive / non-finite values verbatim so the
        // calc engine can surface them as `nonPositiveBaseShutter` /
        // `overflow` failures. Snapping zero to the nearest ladder
        // entry would silently rewrite a zero input into `1/8000` and
        // mask the typed failure.
        guard seconds > 0, seconds.isFinite else {
            return seconds
        }
        let ladder = ExposureScale.scale(for: mode).shutterSteps
        guard let nearest = ladder.min(
            by: { abs($0.seconds - seconds) < abs($1.seconds - seconds) }
        ) else {
            return seconds
        }
        return nearest.seconds
    }
}
