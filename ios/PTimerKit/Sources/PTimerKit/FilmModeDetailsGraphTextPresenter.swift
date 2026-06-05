import Foundation

/// State-aware text for the formula graph: caption, unsupported
/// explanation, description lines, plus the persistent
/// beyond-source-range and unsupported-region seconds values that
/// drive shaded overlays. Pure value presenter: no state, branches
/// on `FilmModeReciprocityBindingState` plus a handful of plain
/// inputs.
public struct FilmModeDetailsGraphTextPresenter {

    public init() {}

    /// Returns at most one short, state-aware note for the formula
    /// graph. The marker/region legend already names each visible
    /// element, so the note is reserved for the cases that need a
    /// brief sentence: outside the visible range, and the formula
    /// prediction outside the published source range.
    public func descriptionLines(
        for bindingState: FilmModeReciprocityBindingState,
        isBeyondVisibleRange: Bool,
        isBelowVisibleRange: Bool
    ) -> [String] {
        if isBeyondVisibleRange {
            return ["Current result is beyond the visible graph range."]
        }
        if isBelowVisibleRange {
            return ["Current result is below the visible graph range."]
        }
        if bindingState.presentation.category == .unsupported,
           bindingState.profile.presentsBeyondSourceRange {
            let line = bindingState.profile.usesTableInterpolation
                ? "Table value beyond the published source range."
                : "Formula-derived result outside published source range."
            return [line]
        }
        return []
    }

    /// Metered-exposure x at which the published manufacturer source
    /// range ends for a converted formula profile. Drives the
    /// persistent pink shading on the formula graph so the user can
    /// always see which region of the curve is the formula prediction
    /// outside the published source range.
    public func beyondSourceRangeStartSeconds(
        profile: ReciprocityProfile,
        supportedUpperBoundSeconds: Double?
    ) -> Double? {
        guard profile.presentsBeyondSourceRange else {
            return nil
        }
        return supportedUpperBoundSeconds
    }

    /// State-aware caption for the formula graph. Branches on the
    /// current basis so the headline matches the shaded region the
    /// user sees: no-correction inputs read as identity-line guidance,
    /// numeric outside-guidance reads as a formula prediction outside
    /// the source range, supported formula inputs read as on the
    /// active curve.
    ///
    /// Caption strings omit a trailing period to match the rest of
    /// the graph caption surface, which renders as banner text.
    public func caption(
        for bindingState: FilmModeReciprocityBindingState,
        noCorrectionRangeUpperBoundSeconds: Double?
    ) -> String {
        let basis = bindingState.policyResult.metadata.basis
        if basis == .officialThresholdNoCorrection,
           noCorrectionRangeUpperBoundSeconds != nil {
            return "Adjusted shutter equals corrected exposure within the no-correction range"
        }

        if bindingState.presentation.category == .unsupported,
           bindingState.policyResult.correctedExposureSeconds != nil {
            return bindingState.profile.usesTableInterpolation
                ? "Beyond the published source table"
                : "Formula prediction outside the manufacturer-supported boundary"
        }

        return "Adjusted shutter vs corrected exposure on the active calculation curve"
    }

    /// Long-form explanation rendered on unsupported inputs.
    /// Distinguishes "outside guidance with a numeric formula
    /// prediction available" from "outside guidance with no value
    /// at all"; identical copy in both cases would mask the
    /// timer-start affordance for the numeric path.
    public func unsupportedExplanation(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        guard bindingState.presentation.category == .unsupported else {
            return nil
        }

        if bindingState.policyResult.correctedExposureSeconds != nil {
            if bindingState.profile.usesTableInterpolation {
                return "Current input is beyond the published source table. The plotted value is extrapolated past the official anchors and should be verified."
            }
            if bindingState.profile.isConvertedFormulaProfile {
                return "Current input is beyond the manufacturer source range. The plotted value is a formula prediction past the published reference and should be verified."
            }
            return "Current input is outside manufacturer guidance. The plotted value is a formula prediction outside the supported range and should be verified."
        }

        return "Current input is outside the supported range. No quantified corrected point is available."
    }

    /// Metered-exposure x at which the per-input unsupported region
    /// begins. Returns `nil` when the current input is inside the
    /// supported range or when the profile is not flagged as
    /// unsupported.
    public func unsupportedRegionStartSeconds(
        supportedUpperBoundSeconds: Double?,
        currentMeteredExposureSeconds: Double,
        isUnsupported: Bool
    ) -> Double? {
        guard isUnsupported,
              let supportedUpperBoundSeconds,
              currentMeteredExposureSeconds > supportedUpperBoundSeconds else {
            return nil
        }
        return supportedUpperBoundSeconds
    }
}
