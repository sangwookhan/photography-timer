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
    /// The slot's last settled Filter Source for the Plus wheel.
    public var lastFilterSource: FilterSource
    /// Effective ND value — the sum of every wheel's contribution in
    /// canonical stops. Computed so the snapshot keeps a single source
    /// of truth; calculation-oriented readers (inactive-page results,
    /// basis summaries) consume this.
    public var ndStep: NDStep {
        NDStep(stops: ndFilterSteps.reduce(0) { $0 + $1.stops })
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

    public init(baseShutterSeconds: Double, filterWheels: [FilterWheel], ndFilterSteps: [NDStep], lastFilterSource: FilterSource, scaleMode: ExposureScaleMode, selectedPresetFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, targetShutterSeconds: TimeInterval? = nil) {
        self.baseShutterSeconds = baseShutterSeconds
        self.filterWheels = filterWheels
        self.ndFilterSteps = ndFilterSteps
        self.lastFilterSource = lastFilterSource
        self.scaleMode = scaleMode
        self.selectedPresetFilm = selectedPresetFilm
        self.selectedProfileOverride = selectedProfileOverride
        self.targetShutterSeconds = targetShutterSeconds
    }

    /// Mixed-stack convenience from a resolved `FilterStack`.
    public init(baseShutterSeconds: Double, filterStack: FilterStack, lastFilterSource: FilterSource, scaleMode: ExposureScaleMode, selectedPresetFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, targetShutterSeconds: TimeInterval? = nil) {
        self.init(
            baseShutterSeconds: baseShutterSeconds,
            filterWheels: filterStack.wheels,
            ndFilterSteps: filterStack.contributions.map(NDStep.init(stops:)),
            lastFilterSource: lastFilterSource,
            scaleMode: scaleMode,
            selectedPresetFilm: selectedPresetFilm,
            selectedProfileOverride: selectedProfileOverride,
            targetShutterSeconds: targetShutterSeconds
        )
    }

    /// Re-resolves the stored wheels against `inventory` after an
    /// inventory edit: stale references normalize (unknown set → wheel
    /// dropped, unknown item → Empty), contributions refresh, and a
    /// vanished last source falls back to Standard. Returns `nil` when
    /// the normalized wheels no longer fit the cap — the caller
    /// decides whether that blocks the edit.
    public func reresolvingFilterStack(against inventory: FilterInventory) -> CameraSlotCalculatorSnapshot? {
        guard let wheels = FilterStack.normalizedWheels(filterWheels, inventory: inventory),
              let stack = FilterStack.validated(wheels: wheels, inventory: inventory) else {
            return nil
        }
        var copy = self
        copy.filterWheels = stack.wheels
        copy.ndFilterSteps = stack.contributions.map(NDStep.init(stops:))
        if !inventory.contains(lastFilterSource) {
            copy.lastFilterSource = .standard
        }
        return copy
    }

    /// Last-resort re-resolution when the normalized wheels no longer
    /// fit the cap (the facade blocks such edits up front): every
    /// mounted item reads Empty so nothing is ever clamped. Standard
    /// wheels are untouched.
    public func emptyingMountedItems(against inventory: FilterInventory) -> CameraSlotCalculatorSnapshot {
        let emptied = (FilterStack.normalizedWheels(filterWheels, inventory: inventory) ?? [.standard(CalculatorDefaults.ndStep)])
            .map { wheel -> FilterWheel in
                wheel.isStandard ? wheel : FilterWheel(source: wheel.source, selection: .empty)
            }
        var copy = self
        if let stack = FilterStack.validated(wheels: emptied, inventory: inventory) {
            copy.filterWheels = stack.wheels
            copy.ndFilterSteps = stack.contributions.map(NDStep.init(stops:))
        } else {
            copy.filterWheels = [.standard(CalculatorDefaults.ndStep)]
            copy.ndFilterSteps = [CalculatorDefaults.ndStep]
        }
        if !inventory.contains(lastFilterSource) {
            copy.lastFilterSource = .standard
        }
        return copy
    }
}
