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
            let originals = ndFilterStack.entries
            var snapped = originals.map { sanitizedNDStep($0, for: scaleMode) }
            if !NDFilterStack.isWithinTotalLimit(snapped) {
                for index in snapped.indices.reversed() {
                    guard !NDFilterStack.isWithinTotalLimit(snapped) else {
                        break
                    }
                    snapped[index] = sanitizedNDStepRoundingDown(originals[index], for: scaleMode)
                }
            }
            ndFilterStack = NDFilterStack(entries: snapped)
            liveNDSteps = liveNDSteps.mapValues { sanitizedNDStep($0, for: scaleMode) }

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

    /// The ND filter wheel stack (PTIMER-199): 1–4 committed wheel
    /// values in display order, collapsing to one effective summed
    /// value. Shape rules (add/remove/sort/budget) live on the
    /// domain type; the model owns lifecycle and observation.
    public private(set) var ndFilterStack = NDFilterStack(single: NDStep(stops: 0))

    /// Stable per-wheel identity (PTIMER-199 §4.3): `ndFilterWheelIDs[i]`
    /// names the wheel at `ndFilterSteps[i]` and follows it through
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
        ndFilterWheelIDs = ndFilterStack.entries.map { _ in makeNDFilterWheelID() }
    }

    /// Individual ND filter wheel values in display order (1–4).
    /// Convenience projection of `ndFilterStack`.
    public var ndFilterSteps: [NDStep] {
        ndFilterStack.entries
    }

    /// Canonical ND input as a fractional-aware `NDStep`. ONE meaning
    /// for every caller (PTIMER-199): reading returns the stack's
    /// EFFECTIVE (summed) value — the value the calc engine consumes.
    /// Writing is the single-filter assignment surface kept for
    /// compatibility (legacy `ndStop` mirror, persistence restore,
    /// tests): it replaces the whole stack with one wheel holding the
    /// value. Per-wheel writes go through `setNDFilterStep(_:at:)`.
    public var ndStep: NDStep {
        get { ndFilterStack.effectiveStep }
        set {
            ndFilterStack = NDFilterStack(single: newValue)
            regenerateNDFilterWheelIDs()
        }
    }

    /// Commits one wheel of the stack, then applies the agreed
    /// post-commit ordering (descending, zeros rightmost, stable).
    /// Commits only happen once a wheel has settled, so sorting here
    /// never reorders mid-scroll. Out-of-range indices are ignored
    /// (defensive: the UI only offers existing wheels).
    public func setNDFilterStep(_ step: NDStep, at index: Int) {
        let replaced = ndFilterStack.replacingWheel(at: index, with: step)
        let permutation = replaced.commitSortPermutation()
        ndFilterStack = replaced.sortedForCommit()
        ndFilterWheelIDs = permutation.map { ndFilterWheelIDs[$0] }
    }

    /// Whether another wheel can be added (PTIMER-199 C1): below
    /// four wheels AND the NEW wheel's allowed ladder must contain
    /// at least one value greater than 0. A remaining budget above
    /// zero is not sufficient — if the ladder truncated to the
    /// remaining budget is [0] only (e.g. a 29.6-stop sum leaves
    /// 0.4, below every integer and preset), a new wheel could never
    /// hold a value, so the Add affordance hides.
    public var canAddFilterWheel: Bool {
        guard ndFilterStack.canAddWheel else {
            return false
        }
        let newWheelBudget = Double(ExposureScale.maximumWholeNDStops)
            - ndFilterStack.effectiveStep.stops
        return exposureScale.ndSteps(upToStops: newWheelBudget)
            .contains { $0.stops > 0 }
    }

    /// Whether a wheel can be removed: more than one wheel AND at
    /// least one wheel sitting at 0 stops (wheels holding a value are
    /// never removed).
    public var canRemoveEmptyFilterWheel: Bool {
        ndFilterStack.canRemoveEmptyWheel
    }

    /// Appends one wheel at 0 stops. The C1 rule is enforced HERE,
    /// not just on the Add affordance: a direct command call is
    /// refused (no-op) at the 4-wheel maximum and whenever the new
    /// wheel's ladder could not hold a value above 0 — the same
    /// condition that hides the UI control.
    public func addFilterWheel() {
        guard canAddFilterWheel else {
            return
        }
        ndFilterStack = ndFilterStack.addingWheel()
        ndFilterWheelIDs.append(makeNDFilterWheelID())
    }

    /// A2 cleanup (PTIMER-199 §4.2.2): removes every CLEANABLE
    /// 0-stop wheel — all zeros while a non-zero wheel exists; all
    /// but one when every wheel is 0-stop.
    public func cleanupEmptyFilterWheels() {
        while canRemoveEmptyFilterWheel {
            removeEmptyFilterWheel()
        }
    }

    /// Removes the 0-stop wheel at `index` — the overscroll
    /// gesture's target (§4.2.3): exactly the wheel the photographer
    /// pulled, not the rightmost zero. No-op when the index is not a
    /// removable zero.
    public func removeEmptyFilterWheel(at index: Int) {
        let countBefore = ndFilterStack.entries.count
        ndFilterStack = ndFilterStack.removingEmptyWheel(at: index)
        if ndFilterStack.entries.count < countBefore {
            ndFilterWheelIDs.remove(at: index)
        }
    }

    /// Removes the rightmost 0-stop wheel (no-op when unavailable).
    public func removeEmptyFilterWheel() {
        let removedIndex = ndFilterStack.entries.lastIndex { $0.stops == 0 }
        let countBefore = ndFilterStack.entries.count
        ndFilterStack = ndFilterStack.removingRightmostEmptyWheel()
        if ndFilterStack.entries.count < countBefore, let removedIndex {
            ndFilterWheelIDs.remove(at: removedIndex)
        }
    }

    /// Restores a wheel stack from persistence or a slot switch. The
    /// caller (persistence validation, slot snapshots) supplies
    /// pre-validated values; this guard is the last defensive shield
    /// so corrupted input can never trip the domain type's
    /// programmer-error preconditions — a violating stack restores
    /// as the default single wheel instead (reject, never clamp).
    public func restoreNDFilterSteps(_ steps: [NDStep]) {
        guard (1...NDFilterStack.maximumWheelCount).contains(steps.count),
              steps.allSatisfy({ $0.stops >= 0 && $0.stops.isFinite }),
              NDFilterStack.isWithinTotalLimit(steps) else {
            ndFilterStack = NDFilterStack(single: CalculatorDefaults.ndStep)
            regenerateNDFilterWheelIDs()
            return
        }
        clearLiveNDStopPreview()
        ndFilterStack = NDFilterStack(entries: steps)
        regenerateNDFilterWheelIDs()
    }

    /// Picker ladder for one wheel: the active scale's ND ladder
    /// truncated from the top to that wheel's remaining budget under
    /// the 30-stop total limit. Derives from COMMITTED values only,
    /// so sibling ladders never reload while another wheel is being
    /// dragged.
    public func pickerNDSteps(forWheel index: Int) -> [NDStep] {
        guard ndFilterStack.entries.indices.contains(index) else {
            return exposureScale.ndSteps
        }
        return exposureScale.ndSteps(
            upToStops: ndFilterStack.remainingBudget(excludingWheelAt: index)
        )
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
    /// flings): each key is a wheel index whose value overlays that
    /// wheel's committed entry in `effectiveNDStep`. Values are
    /// `NDStep` so the reserved fractional path never loses
    /// precision through this preview.
    /// Keys are WHEEL IDENTITY values (`ndFilterWheelIDs` entries),
    /// never positions (PTIMER-199 v2 계약 3): entries survive the
    /// commit sort untouched because identity moves with the wheel.
    public private(set) var liveNDSteps: [Int: NDStep] = [:]

    /// Which wheel the LAST live update touched. Backs the legacy
    /// single-overlay projection below; wheel 0 for the
    /// single-filter workflow and all legacy callers.
    private var liveNDWheelID = 0

    /// Legacy single-overlay view of `liveNDSteps`: the most recently
    /// updated wheel's live value. Kept so pre-stack callers and the
    /// integer wrapper keep compiling; multi-wheel-aware callers read
    /// `liveNDSteps` directly.
    public var liveNDStep: NDStep? {
        get { liveNDSteps[liveNDWheelID] }
        set {
            if let newValue {
                liveNDSteps[liveNDWheelID] = newValue
            } else {
                liveNDSteps.removeValue(forKey: liveNDWheelID)
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

    /// Effective ND step — the value the calculator actually uses:
    /// the stack's sum, with the dragging wheel's live value
    /// substituted for its committed value while a preview is active
    /// (PTIMER-199 §4.5: live wheel + committed others).
    public var effectiveNDStep: NDStep {
        guard !liveNDSteps.isEmpty else {
            return ndFilterStack.effectiveStep
        }
        // Sum of every wheel's current value: live overlay when the
        // wheel is in motion, committed value otherwise. During a
        // multi-wheel epoch the frozen ladders can transiently allow
        // a combined sum above the 30-stop cap; the display shows
        // the actual transient sum and the set commit resolves it by
        // rejection (§4.5).
        let total = ndFilterStack.entries.enumerated().reduce(0.0) { sum, entry in
            let wheelID = ndFilterWheelIDs.indices.contains(entry.offset)
                ? ndFilterWheelIDs[entry.offset] : -1
            return sum + (liveNDSteps[wheelID]?.stops ?? entry.element.stops)
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
        self.ndFilterStack = NDFilterStack(single: ndStep)
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
        guard ndFilterStack.entries.indices.contains(index),
              ndFilterWheelIDs.indices.contains(index) else {
            return
        }
        updateLiveNDStep(value, forWheelID: ndFilterWheelIDs[index])
    }

    /// Identity-keyed live preview write (PTIMER-199 v2 계약 3): the
    /// canonical entry point — the index overload above is a legacy
    /// shim that derives the id at call time.
    public func updateLiveNDStep(_ value: NDStep, forWheelID wheelID: Int) {
        guard let index = ndFilterWheelIDs.firstIndex(of: wheelID) else {
            return
        }
        liveNDWheelID = wheelID
        if value == ndFilterStack.entries[index] {
            liveNDSteps.removeValue(forKey: wheelID)
        } else {
            liveNDSteps[wheelID] = value
        }
    }

    public func clearLiveBaseShutterPreview() {
        liveBaseShutter = nil
    }

    public func clearLiveNDStopPreview() {
        liveNDSteps.removeAll()
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
