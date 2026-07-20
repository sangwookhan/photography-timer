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
    /// Individual ND filter wheel values in display order (1–4,
    /// PTIMER-199). A slot switch must restore the photographer's
    /// wheel layout, not just the collapsed sum.
    public var ndFilterSteps: [NDStep]
    /// Effective ND value — the sum of every wheel in canonical
    /// stops. Computed so the snapshot keeps a single source of
    /// truth; calculation-oriented readers (inactive-page results,
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
    /// pre-stack call sites: one wheel holding `ndStep`.
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

    public init(baseShutterSeconds: Double, ndFilterSteps: [NDStep], scaleMode: ExposureScaleMode, selectedPresetFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, targetShutterSeconds: TimeInterval? = nil) {
        self.baseShutterSeconds = baseShutterSeconds
        self.ndFilterSteps = ndFilterSteps
        self.scaleMode = scaleMode
        self.selectedPresetFilm = selectedPresetFilm
        self.selectedProfileOverride = selectedProfileOverride
        self.targetShutterSeconds = targetShutterSeconds
    }
}
