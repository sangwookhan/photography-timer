import Foundation
import PTimerCore

/// Pure-value presenter that produces a
/// `FilmModeDetailsGraphDisplayState` for the custom-film editor's
/// Preview card by synthesizing a binding state from the editor
/// form and routing it through the same
/// `FilmModeDetailsGraphPresenter` the runtime Reciprocity Details
/// sheet uses. Sharing the presenter (not just the view)
/// guarantees the editor and Details graphs agree on:
///
///   * axis labels (`Adjusted shutter` / `Corrected exposure`)
///   * viewport range (`0.01 s … tier.upperBoundSeconds`)
///   * tick policy (`formulaGraphAxisTicks` with sub-second
///     prefixes when the viewport extends below 1 s)
///   * curve sampling (identity segment in the no-correction zone
///     joined to the formula segment past the threshold)
///   * no-correction band semantics
///   * finite-valid-through "not recommended" boundary
///   * formula title formatter
///
/// The editor has no shutter-input field, so the preview marker is
/// pinned to a representative sample (`previewMeteredSeconds`) —
/// the Details presenter still requires a current input, and a
/// stable sample is more useful than rebuilding the presenter to
/// allow a missing one. The sample stays inside the photographic
/// long-exposure range where reciprocity formulas matter.
///
/// Returns `nil` when the form is not parseable.
enum CustomFilmEditorPreviewGraphPresenter {

    /// Sample metered exposure used to drive the preview marker.
    /// 4 s sits inside the formula range for every reasonable
    /// custom profile while staying far enough from the typical
    /// no-correction threshold (1 s) that the marker reads as
    /// `.formulaDerived` rather than `.noCorrection`.
    static let previewMeteredSeconds: Double = 4

    static func graphDisplayState(
        for form: CustomFilmEditorFormState
    ) -> FilmModeDetailsGraphDisplayState? {
        guard let parsed = CustomFilmEditorPreviewPresenter.parse(form: form) else {
            return nil
        }
        let bindingState = makeBindingState(parsed: parsed)
        let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> = .success(
            ExposureCalculationResult(
                baseShutterSeconds: previewMeteredSeconds,
                ndStep: NDStep(stops: 0),
                resultShutterSeconds: previewMeteredSeconds
            )
        )
        return FilmModeDetailsGraphPresenter().graphDisplayState(
            for: FilmModeDetailsGraphPresenter.Input(
                bindingState: bindingState,
                calculationResult: calculationResult,
                formatDuration: Self.formatDuration
            )
        )
    }

    /// Builds the binding state the Details graph presenter expects.
    /// The synthesized profile mirrors what
    /// `CustomFilmEditorFormState.buildFilmIdentity` produces on
    /// Save: same threshold + formula rule shape, same anchored
    /// formula encoding, same `.userDefined` authority. Running the
    /// Details presenter against this state therefore yields the
    /// exact display state the saved profile would render at the
    /// preview metered sample.
    private static func makeBindingState(
        parsed: CustomFilmEditorPreviewPresenter.ParsedFormula
    ) -> FilmModeReciprocityBindingState {
        let profile = makeProfile(parsed: parsed)
        let film = makeFilm(profile: profile)
        let policyResult = ReciprocityCalculationPolicyEvaluator().evaluate(
            profile: profile,
            meteredExposureSeconds: previewMeteredSeconds
        )
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }

    private static func makeProfile(
        parsed: CustomFilmEditorPreviewPresenter.ParsedFormula
    ) -> ReciprocityProfile {
        // The synthesized preview profile mirrors what
        // `CustomFilmEditorFormState.buildFilmIdentity` writes on
        // Save: every editor row maps directly to a field on
        // `ReciprocityFormula`. Identical inputs therefore produce
        // identical graph state for the editor preview and the
        // runtime Details sheet.
        let formula = ReciprocityFormula(
            formulaFamily: .modifiedSchwarzschild,
            coefficientSeconds: parsed.baseTc,
            referenceMeteredTimeSeconds: parsed.baseTm,
            exponent: parsed.exponent,
            offsetSeconds: parsed.offsetSeconds,
            noCorrectionThroughSeconds: parsed.noCorrectionThrough,
            sourceRangeThroughSeconds: parsed.validThrough
        )
        let formulaRule = FormulaReciprocityRule(formula: formula)
        return ReciprocityProfile(
            id: "custom-preview-profile",
            name: "Custom preview",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(formulaRule)]
        )
    }

    private static func makeFilm(profile: ReciprocityProfile) -> FilmIdentity {
        FilmIdentity(
            id: "custom-preview-film",
            kind: .custom,
            canonicalStockName: "Custom preview",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: nil
        )
    }

    /// Compact duration formatter for the graph's caption / source-
    /// reference labels. Matches the Details surface's preferred
    /// shape (`"4s"`, `"1m"`, `"1h"`) so a future caption tweak in
    /// Details does not produce a divergent editor copy.
    private static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        if seconds >= 3_600 {
            let hours = seconds / 3_600
            return hours == hours.rounded()
                ? "\(Int(hours))h"
                : String(format: "%.1fh", hours)
        }
        if seconds >= 60 {
            let minutes = seconds / 60
            return minutes == minutes.rounded()
                ? "\(Int(minutes))m"
                : String(format: "%.1fm", minutes)
        }
        if seconds < 1 {
            return String(format: "%.2fs", seconds)
        }
        return seconds == seconds.rounded()
            ? "\(Int(seconds))s"
            : String(format: "%.1fs", seconds)
    }
}
