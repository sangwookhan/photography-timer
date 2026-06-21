// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Pure projection helper that assembles per-page display state for
/// the workspace TabView. Holds no child model references; receives
/// every fact through method-scoped input structs. The active/
/// inactive dispatch and any model calls live in the ViewModel,
/// which feeds pre-computed values into this helper for final
/// struct assembly.
public struct CameraSlotPageStateBuilder {
    public init() {}

    /// Effective slot values resolved by the caller. The active
    /// slot's caller passes live `CalculatorModel` /
    /// `FilmSelectionModel` / `TargetShutterModel` reads; an
    /// inactive slot's caller passes the corresponding
    /// `CameraSlotCalculatorSnapshot` fields.
    public struct PageStateInputs {
        public let slotID: CameraSlotID
        public let cameraDisplayName: String
        public let isActive: Bool
        public let baseShutter: Double
        public let ndStep: NDStep
        public let scaleMode: ExposureScaleMode
        public let selectedFilm: FilmIdentity?
        public let selectedProfileOverride: ReciprocityProfile?
        public let targetShutterSeconds: TimeInterval?
        public init(slotID: CameraSlotID, cameraDisplayName: String, isActive: Bool, baseShutter: Double, ndStep: NDStep, scaleMode: ExposureScaleMode, selectedFilm: FilmIdentity?, selectedProfileOverride: ReciprocityProfile?, targetShutterSeconds: TimeInterval?) {
            self.slotID = slotID
            self.cameraDisplayName = cameraDisplayName
            self.isActive = isActive
            self.baseShutter = baseShutter
            self.ndStep = ndStep
            self.scaleMode = scaleMode
            self.selectedFilm = selectedFilm
            self.selectedProfileOverride = selectedProfileOverride
            self.targetShutterSeconds = targetShutterSeconds
        }
    }

    public func pageState(_ inputs: PageStateInputs) -> CameraSlotPageState {
        let filmDisplay: FilmSelectionDisplayState = {
            guard let film = inputs.selectedFilm else {
                return FilmSelectionDisplayState(primaryText: "No film", secondaryText: nil)
            }
            let activeProfile = inputs.selectedProfileOverride ?? film.profiles.first
            return FilmSelectionDisplayState(
                primaryText: film.canonicalStockName,
                secondaryText: FilmSelectionModel.filmRowAuthorityLabel(for: activeProfile)
            )
        }()

        return CameraSlotPageState(
            slotID: inputs.slotID,
            cameraDisplayName: inputs.cameraDisplayName,
            baseShutter: inputs.baseShutter,
            ndStep: inputs.ndStep,
            scaleMode: inputs.scaleMode,
            selectedFilm: inputs.selectedFilm,
            selectedProfileOverride: inputs.selectedProfileOverride,
            filmSelectionDisplayState: filmDisplay,
            isFilmWorkflowActive: inputs.selectedFilm != nil,
            isActive: inputs.isActive,
            targetShutterSeconds: inputs.targetShutterSeconds
        )
    }

    /// Pre-computed model outputs the inactive page assembler needs.
    /// All four pieces are obtained from `ReciprocityModel` by the
    /// caller; this helper only packages them into the final state
    /// with the inactive-page action overrides.
    public struct InactiveFilmModeInputs {
        public let adjustedShutterSeconds: TimeInterval
        public let reciprocityState: FilmModeReciprocityStateDisplayState
        public let correctedExposure: FilmModeCorrectedExposureDisplayState
        /// The live (active-page) corrected-exposure action that
        /// supplies the `targetSeconds` and `accessibilityLabel` the
        /// inactive corrected action needs to mirror; the inactive
        /// state replaces `canStartTimer` and the accessibility hint.
        public let liveCorrectedActionState: FilmModeTimerActionState
        public init(adjustedShutterSeconds: TimeInterval, reciprocityState: FilmModeReciprocityStateDisplayState, correctedExposure: FilmModeCorrectedExposureDisplayState, liveCorrectedActionState: FilmModeTimerActionState) {
            self.adjustedShutterSeconds = adjustedShutterSeconds
            self.reciprocityState = reciprocityState
            self.correctedExposure = correctedExposure
            self.liveCorrectedActionState = liveCorrectedActionState
        }
    }

    public func inactiveFilmModeResult(_ inputs: InactiveFilmModeInputs) -> FilmModeExposureResultState {
        FilmModeExposureResultState(
            adjustedShutterSeconds: inputs.adjustedShutterSeconds,
            reciprocityState: inputs.reciprocityState,
            adjustedShutterAction: Self.inactiveTimerActionState(
                targetSeconds: inputs.adjustedShutterSeconds,
                accessibilityLabel: "Start timer from adjusted shutter"
            ),
            correctedExposure: inputs.correctedExposure,
            correctedExposureAction: Self.inactiveTimerActionState(
                targetSeconds: inputs.liveCorrectedActionState.targetSeconds,
                accessibilityLabel: inputs.liveCorrectedActionState.accessibilityLabel
            )
        )
    }

    /// Disabled timer-action state for an inactive page. Centralised
    /// so both the adjusted and corrected actions emit the same
    /// "page to this slot first" hint and the same `canStartTimer`
    /// policy.
    public static func inactiveTimerActionState(
        targetSeconds: TimeInterval?,
        accessibilityLabel: String
    ) -> FilmModeTimerActionState {
        FilmModeTimerActionState(
            targetSeconds: targetSeconds,
            canStartTimer: false,
            accessibilityLabel: accessibilityLabel,
            accessibilityHint: "Inactive camera slot — page to this slot to start a timer"
        )
    }

    public func pickerShutterStepSeconds(forPage pageState: CameraSlotPageState) -> [Double] {
        ExposureScale.scale(for: pageState.scaleMode).shutterSteps.map(\.seconds)
    }

    public func pickerNDSteps(forPage pageState: CameraSlotPageState) -> [NDStep] {
        ExposureScale.scale(for: pageState.scaleMode).ndSteps
    }

    /// Comparison source the Target Shutter presenter consumes for a
    /// given page. Routes the page's film vs digital workflow choice
    /// against the caller-supplied `filmModeResult` /
    /// `calculationResult` — both pre-computed by the ViewModel so
    /// this helper stays free of model dependencies.
    public func targetShutterComparisonSource(
        forPage pageState: CameraSlotPageState,
        filmModeResult: FilmModeExposureResultState?,
        calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    ) -> TargetShutterPresenter.ComparisonSource {
        if pageState.isFilmWorkflowActive {
            if let filmModeResult,
               filmModeResult.hasQuantifiedCorrectedExposure,
               let correctedSeconds = filmModeResult.correctedExposure.correctedExposureSeconds,
               correctedSeconds.isFinite,
               correctedSeconds > 0 {
                return .correctedExposure(correctedSeconds)
            }
            return .unavailable
        }

        guard case .success(let result) = calculationResult,
              result.resultShutterSeconds.isFinite,
              result.resultShutterSeconds > 0 else {
            return .unavailable
        }
        return .adjustedShutter(result.resultShutterSeconds)
    }
}
