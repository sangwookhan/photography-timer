// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Per-slot snapshot of the calculator working state. This carries the
/// fields the active slot would otherwise hold on `CalculatorModel` and
/// `FilmSelectionModel`; inactive slots keep their snapshot here so a
/// switch can restore the slot's exposure inputs and film selection
/// without touching reciprocity policy or preset data.
///
/// The snapshot deliberately does not include live preview overlays
/// (`liveBaseShutter` / `liveNDStep`). A live preview only exists while
/// the user is dragging a wheel on the active slot, so the inactive
/// snapshot stays clean.
public struct CameraSlotCalculatorSnapshot: Equatable {
    public var baseShutterSeconds: Double
    /// Per-wheel active contributions in display order (1–4). For a
    /// Standard wheel this is its value; for a Filter Set wheel it is
    /// the mounted row's contribution (0 for Empty and Record only).
    /// Kept parallel to `filterWheels` so calculation-oriented readers
    /// never need the inventory.
    public var ndFilterSteps: [NDStep]
    /// The mixed Filter Stack's wheels — source and selection per
    /// wheel, parallel to `ndFilterSteps`. A slot switch must restore
    /// the photographer's wheel layout, not just the collapsed sum.
    public var filterWheels: [FilterWheel]
    /// The slot's mounted auxiliary filters (FILTER-AUX-001) in mount
    /// order; empty when none is mounted.
    public var auxiliaryFilters: [MountedAuxiliaryFilter]
    /// Active contribution of each auxiliary filter, parallel to
    /// `auxiliaryFilters`, so calculation-oriented readers never need
    /// the inventory.
    public var auxiliaryContributions: [Double]
    /// The slot's candidate Filter Sets (FILTER-CAMERA-001), in
    /// user-defined set order. Standard is always available and is
    /// not listed.
    public var candidateFilterSetIDs: [FilterSetID]
    /// The slot's last settled Filter Source for the Plus wheel.
    public var lastFilterSource: FilterSource
    /// Effective ND value — the sum of every wheel's and every
    /// auxiliary filter's contribution in canonical stops. Computed so
    /// the snapshot keeps a single source of truth; calculation-
    /// oriented readers (inactive-page results, basis summaries)
    /// consume this.
    public var ndStep: NDStep {
        NDStep(stops: ndFilterSteps.reduce(0) { $0 + $1.stops } + auxiliaryContributions.reduce(0, +))
    }
    public var scaleMode: ExposureScaleMode
    public var selectedPresetFilm: FilmIdentity?
    public var selectedProfileOverride: ReciprocityProfile?
    /// Optional Target Shutter duration captured per slot. `nil` means
    /// the photographer has not set a target on this slot — Target
    /// Shutter is part of each slot's shooting context (the same axis
    /// as base shutter / ND / film), not a global ViewModel concern,
    /// so a target set on Camera 1 must not bleed into Camera 2.
    public var targetShutterSeconds: TimeInterval?

    /// Default snapshot used when a slot is initialized without prior
    /// state. Reads through `CalculatorDefaults` so a fresh slot is
    /// indistinguishable from a fresh app — one source of truth for
    /// shipping defaults across the ViewModel and slot snapshots.
    public static let initial = CameraSlotCalculatorSnapshot(
        baseShutterSeconds: CalculatorDefaults.baseShutterSeconds,
        ndStep: CalculatorDefaults.ndStep,
        scaleMode: CalculatorDefaults.scaleMode,
        selectedPresetFilm: nil,
        selectedProfileOverride: nil,
        targetShutterSeconds: nil
    )

    /// Single-wheel convenience kept for the legacy restore path and
    /// pre-stack call sites: one Standard wheel holding `ndStep`.
    public init(baseShutterSeconds: Double, ndStep: NDStep, scaleMode: ExposureScaleMode, selectedPresetFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, targetShutterSeconds: TimeInterval? = nil) {
        self.init(
            baseShutterSeconds: baseShutterSeconds,
            ndFilterSteps: [ndStep],
            scaleMode: scaleMode,
            selectedPresetFilm: selectedPresetFilm,
            selectedProfileOverride: selectedProfileOverride,
            targetShutterSeconds: targetShutterSeconds
        )
    }

    /// Standard-only stack convenience: every step becomes a Standard
    /// wheel and the last source is Standard.
    public init(baseShutterSeconds: Double, ndFilterSteps: [NDStep], scaleMode: ExposureScaleMode, selectedPresetFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, targetShutterSeconds: TimeInterval? = nil) {
        self.init(
            baseShutterSeconds: baseShutterSeconds,
            filterWheels: ndFilterSteps.map(FilterWheel.standard),
            ndFilterSteps: ndFilterSteps,
            lastFilterSource: .standard,
            scaleMode: scaleMode,
            selectedPresetFilm: selectedPresetFilm,
            selectedProfileOverride: selectedProfileOverride,
            targetShutterSeconds: targetShutterSeconds
        )
    }

    public init(baseShutterSeconds: Double, filterWheels: [FilterWheel], ndFilterSteps: [NDStep], auxiliaryFilters: [MountedAuxiliaryFilter] = [], auxiliaryContributions: [Double] = [], candidateFilterSetIDs: [FilterSetID] = [], lastFilterSource: FilterSource, scaleMode: ExposureScaleMode, selectedPresetFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, targetShutterSeconds: TimeInterval? = nil) {
        self.baseShutterSeconds = baseShutterSeconds
        self.filterWheels = filterWheels
        self.ndFilterSteps = ndFilterSteps
        self.auxiliaryFilters = auxiliaryFilters
        self.auxiliaryContributions = auxiliaryContributions
        self.candidateFilterSetIDs = candidateFilterSetIDs
        self.lastFilterSource = lastFilterSource
        self.scaleMode = scaleMode
        self.selectedPresetFilm = selectedPresetFilm
        self.selectedProfileOverride = selectedProfileOverride
        self.targetShutterSeconds = targetShutterSeconds
    }

    /// Convenience from a resolved `FilterStack` (wheels and mounted
    /// auxiliary filters).
    public init(baseShutterSeconds: Double, filterStack: FilterStack, candidateFilterSetIDs: [FilterSetID] = [], lastFilterSource: FilterSource, scaleMode: ExposureScaleMode, selectedPresetFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, targetShutterSeconds: TimeInterval? = nil) {
        self.init(
            baseShutterSeconds: baseShutterSeconds,
            filterWheels: filterStack.wheels,
            ndFilterSteps: filterStack.contributions.map(NDStep.init(stops:)),
            auxiliaryFilters: filterStack.auxiliaryFilters,
            auxiliaryContributions: filterStack.auxiliaryContributions,
            candidateFilterSetIDs: candidateFilterSetIDs,
            lastFilterSource: lastFilterSource,
            scaleMode: scaleMode,
            selectedPresetFilm: selectedPresetFilm,
            selectedProfileOverride: selectedProfileOverride,
            targetShutterSeconds: targetShutterSeconds
        )
    }

    /// Re-resolves the stored wheels and auxiliary filters against
    /// `inventory` after an inventory edit: stale references normalize
    /// (unknown set → wheel dropped, unknown item → Empty, an
    /// unresolvable auxiliary filter → unmounted), contributions
    /// refresh, candidates follow the inventory, and a vanished last
    /// source falls back to Standard. Returns `nil` when the normalized
    /// state no longer fits the cap — the caller decides whether that
    /// blocks the edit.
    public func reresolvingFilterStack(against inventory: FilterInventory) -> CameraSlotCalculatorSnapshot? {
        let auxiliary = FilterStack.normalizedAuxiliaryFilters(auxiliaryFilters, inventory: inventory)
        guard let wheels = FilterStack.normalizedWheels(filterWheels, inventory: inventory),
              let stack = FilterStack.validated(wheels: wheels, auxiliaryFilters: auxiliary, inventory: inventory) else {
            return nil
        }
        return replacing(stack: stack, inventory: inventory)
    }

    /// Last-resort re-resolution when the normalized state no longer
    /// fits the cap (the facade blocks such edits up front): every
    /// mounted wheel item reads Empty and, if that still does not fit,
    /// the auxiliary filters are unmounted, so nothing is ever
    /// clamped. Standard wheels are untouched.
    public func emptyingMountedItems(against inventory: FilterInventory) -> CameraSlotCalculatorSnapshot {
        let emptied = (FilterStack.normalizedWheels(filterWheels, inventory: inventory) ?? [.standard(CalculatorDefaults.ndStep)])
            .map { wheel -> FilterWheel in
                wheel.isStandard ? wheel : FilterWheel(source: wheel.source, selection: .empty)
            }
        let auxiliary = FilterStack.normalizedAuxiliaryFilters(auxiliaryFilters, inventory: inventory)
        let stack = FilterStack.validated(wheels: emptied, auxiliaryFilters: auxiliary, inventory: inventory)
            ?? FilterStack.validated(wheels: emptied, inventory: inventory)
            ?? FilterStack(single: CalculatorDefaults.ndStep)
        return replacing(stack: stack, inventory: inventory)
    }

    private func replacing(stack: FilterStack, inventory: FilterInventory) -> CameraSlotCalculatorSnapshot {
        var copy = self
        copy.filterWheels = stack.wheels
        copy.ndFilterSteps = stack.contributions.map(NDStep.init(stops:))
        copy.auxiliaryFilters = stack.auxiliaryFilters
        copy.auxiliaryContributions = stack.auxiliaryContributions
        copy.candidateFilterSetIDs = inventory.normalizedCandidateFilterSetIDs(
            candidateFilterSetIDs,
            referencedBy: stack.wheels,
            auxiliaryFilters: stack.auxiliaryFilters
        )
        if !inventory.contains(lastFilterSource) {
            copy.lastFilterSource = .standard
        }
        return copy
    }
}
