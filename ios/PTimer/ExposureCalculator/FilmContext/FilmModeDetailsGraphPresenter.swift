import Foundation
import PTimerKit

/// Pure presenter for the Film Details reciprocity graph.
///
/// Owns the formula graph's final display-state assembly: viewport
/// / scale-tier selection, geometry orchestration, current-marker
/// placement, and axis ticks. Pure-value helpers under
/// `FilmContext/` provide the inputs:
///
///   * `FilmModeDetailsGraphCurveSampler` — calculation curve points.
///   * `FormulaEquationFormatter` — user-facing equation text.
///   * `FilmModeDetailsGraphEvidencePresenter` —
///     source-reference markers and the not-recommended boundary.
///   * `FilmModeDetailsGraphTextPresenter` — caption, unsupported
///     explanation, description lines, beyond-source-range start,
///     unsupported-region start.
///
/// Returns `nil` for profiles that cannot render a formula graph
/// (Kodak limited-guidance profiles). Returning `nil` is the same
/// signal the legacy table-graph kind used; consumers treat a `nil`
/// graph as "no graph".
struct FilmModeDetailsGraphPresenter {

    struct Input {
        let bindingState: FilmModeReciprocityBindingState
        let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
        let formatDuration: (Double) -> String
    }

    // MARK: - Public entry point

    func graphDisplayState(for input: Input) -> FilmModeDetailsGraphDisplayState? {
        guard case .success(let result) = input.calculationResult,
              result.resultShutterSeconds > 0 else {
            return nil
        }

        let currentMeteredExposureSeconds = result.resultShutterSeconds
        let currentPoint = graphCurrentPoint(
            for: input.bindingState,
            calculationResult: input.calculationResult
        )

        if let formulaState = formulaDetailsGraphDisplayState(
            for: input.bindingState,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            formatDuration: input.formatDuration
        ) {
            return formulaState
        }

        // PTIMER-159: the official log-log table model graphs too.
        return tableDetailsGraphDisplayState(
            for: input.bindingState,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            formatDuration: input.formatDuration
        )
    }

    // MARK: - Formula graph construction

    private func formulaDetailsGraphDisplayState(
        for bindingState: FilmModeReciprocityBindingState,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        formatDuration: (Double) -> String
    ) -> FilmModeDetailsGraphDisplayState? {
        // The calculation curve (identity segment in the
        // no-correction zone + formula segment past the threshold)
        // is the same reference regardless of where the current
        // input lands. The graph stays visible whenever a
        // graphable formula exists; the current-point marker style
        // and the shaded regions separate the three states
        // (no-correction, formula-derived, beyond-source-range
        // outside guidance).
        guard let formulaRule = firstFormulaRule(in: bindingState.profile) else {
            return nil
        }

        let geometry = formulaGraphGeometry(
            for: bindingState,
            formulaRule: formulaRule,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            formatDuration: formatDuration
        )
        guard let geometry else {
            return nil
        }

        return buildFormulaGraphDisplayState(
            geometry: geometry,
            bindingState: bindingState,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint
        )
    }

    private func firstFormulaRule(in profile: ReciprocityProfile) -> FormulaReciprocityRule? {
        for rule in profile.rules {
            if case let .formula(formulaRule) = rule {
                return formulaRule
            }
        }
        return nil
    }

    // MARK: - Table log-log graph construction (PTIMER-159)

    /// Builds the graph for a log-log table model (Fomapan 100's
    /// official model). Reuses the same display-state assembly, current
    /// marker, source-reference markers, no-correction band, and
    /// beyond-source region as the formula graph — only the curve
    /// sampler and tier inputs differ.
    private func tableDetailsGraphDisplayState(
        for bindingState: FilmModeReciprocityBindingState,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        formatDuration: (Double) -> String
    ) -> FilmModeDetailsGraphDisplayState? {
        guard let tableRule = firstTableRule(in: bindingState.profile) else {
            return nil
        }
        guard let geometry = tableGraphGeometry(
            for: bindingState,
            tableRule: tableRule,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            formatDuration: formatDuration
        ) else {
            return nil
        }
        return buildFormulaGraphDisplayState(
            geometry: geometry,
            bindingState: bindingState,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint
        )
    }

    private func firstTableRule(in profile: ReciprocityProfile) -> TableInterpolationReciprocityRule? {
        for rule in profile.rules {
            if case let .tableInterpolation(tableRule) = rule {
                return tableRule
            }
        }
        return nil
    }

    private func tableGraphGeometry(
        for bindingState: FilmModeReciprocityBindingState,
        tableRule: TableInterpolationReciprocityRule,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        formatDuration: (Double) -> String
    ) -> FormulaGraphGeometry? {
        let sourceEvidencePresenter = FilmModeDetailsGraphEvidencePresenter()
        let sourceReferenceMarkers = sourceEvidencePresenter.markers(
            for: bindingState.profile,
            formatDuration: formatDuration
        )
        let notRecommendedBoundarySeconds = sourceEvidencePresenter.notRecommendedBoundarySeconds(
            for: bindingState.profile
        )

        let tierSelection = selectTableGraphScaleTier(
            tableRule: tableRule,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            sourceReferenceMarkers: sourceReferenceMarkers,
            notRecommendedBoundarySeconds: notRecommendedBoundarySeconds
        )
        let tier = tierSelection.tier

        let supportedUpperBoundSeconds = tableRule.sourceRangeThroughSeconds
        let noCorrectionRangeUpperBoundSeconds = effectiveNoCorrectionUpperBoundSeconds(
            for: bindingState
        )
        let stableLowerBoundSeconds = formulaGraphStableLowerBoundSeconds

        let sourcePoints = FilmModeDetailsGraphCurveSampler().tableSourcePoints(
            FilmModeDetailsGraphCurveSampler.TableInputs(
                rule: tableRule,
                profile: bindingState.profile,
                currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                tierUpperBoundSeconds: tier.upperBoundSeconds,
                viewportLowerBoundSeconds: stableLowerBoundSeconds
            )
        )
        guard sourcePoints.count >= 2 else {
            return nil
        }

        let isBelowVisibleRange = isCurrentInputBelowVisibleLowerBound(
            viewportLowerBoundSeconds: stableLowerBoundSeconds,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint
        )
        let textPresenter = FilmModeDetailsGraphTextPresenter()
        let descriptionLines = textPresenter.descriptionLines(
            for: bindingState,
            isBeyondVisibleRange: tierSelection.isBeyondVisibleRange,
            isBelowVisibleRange: isBelowVisibleRange
        )
        let beyondSourceRangeStartSeconds = textPresenter.beyondSourceRangeStartSeconds(
            profile: bindingState.profile,
            supportedUpperBoundSeconds: supportedUpperBoundSeconds
        )
        let usesCurrentInputGuideOnly = bindingState.presentation.category == .unsupported
            && currentPoint == nil

        return FormulaGraphGeometry(
            formulaRule: nil,
            sourceReferenceMarkers: sourceReferenceMarkers,
            notRecommendedBoundarySeconds: notRecommendedBoundarySeconds,
            tier: tier,
            isBeyondVisibleRange: tierSelection.isBeyondVisibleRange,
            supportedUpperBoundSeconds: supportedUpperBoundSeconds,
            noCorrectionRangeUpperBoundSeconds: noCorrectionRangeUpperBoundSeconds,
            stableLowerBoundSeconds: stableLowerBoundSeconds,
            sourcePoints: sourcePoints,
            isBelowVisibleRange: isBelowVisibleRange,
            descriptionLines: descriptionLines,
            // No equation header for the table model — the curve plus
            // the source anchors carry the meaning.
            formulaDisplayText: nil,
            beyondSourceRangeStartSeconds: beyondSourceRangeStartSeconds,
            usesCurrentInputGuideOnly: usesCurrentInputGuideOnly
        )
    }

    private func selectTableGraphScaleTier(
        tableRule: TableInterpolationReciprocityRule,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        sourceReferenceMarkers: [FilmModeDetailsGraphSourceReference],
        notRecommendedBoundarySeconds: Double?
    ) -> (tier: FilmModeDetailsGraphScaleTier, isBeyondVisibleRange: Bool) {
        var maxValue: Double = 1

        let curveUpper = [tableRule.sourceRangeThroughSeconds, currentMeteredExposureSeconds]
            .filter { $0 > 0 }
            .max() ?? 0
        if curveUpper > 0 {
            maxValue = max(maxValue, curveUpper)
            if let curveUpperCorrected = FilmModeDetailsGraphCurveSampler.tableCorrectedExposureSeconds(
                for: tableRule,
                meteredExposureSeconds: curveUpper
            ) {
                maxValue = max(maxValue, curveUpperCorrected)
            }
        }

        if let currentPoint {
            maxValue = max(maxValue, currentPoint.point.meteredExposureSeconds)
            maxValue = max(maxValue, currentPoint.point.correctedExposureSeconds)
        }
        for marker in sourceReferenceMarkers {
            maxValue = max(maxValue, marker.point.meteredExposureSeconds)
            maxValue = max(maxValue, marker.point.correctedExposureSeconds)
        }
        if let notRecommendedBoundarySeconds {
            maxValue = max(maxValue, notRecommendedBoundarySeconds)
        }

        return (
            tier: FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: maxValue),
            isBeyondVisibleRange: FilmModeDetailsGraphScalePolicy.isBeyondVisibleRange(
                maxPlottedSeconds: maxValue
            )
        )
    }

    /// Pre-computed values shared between the geometry builder and
    /// the final display-state assembly.
    private struct FormulaGraphGeometry {
        /// `nil` for the table-log-log model, which has no formula rule.
        let formulaRule: FormulaReciprocityRule?
        let sourceReferenceMarkers: [FilmModeDetailsGraphSourceReference]
        let notRecommendedBoundarySeconds: Double?
        let tier: FilmModeDetailsGraphScaleTier
        let isBeyondVisibleRange: Bool
        let supportedUpperBoundSeconds: Double?
        let noCorrectionRangeUpperBoundSeconds: Double?
        let stableLowerBoundSeconds: Double
        let sourcePoints: [FilmModeDetailsGraphPoint]
        let isBelowVisibleRange: Bool
        let descriptionLines: [String]
        /// `nil` for the table model, which shows no equation header.
        let formulaDisplayText: String?
        let beyondSourceRangeStartSeconds: Double?
        let usesCurrentInputGuideOnly: Bool
    }

    private func formulaGraphGeometry(
        for bindingState: FilmModeReciprocityBindingState,
        formulaRule: FormulaReciprocityRule,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        formatDuration: (Double) -> String
    ) -> FormulaGraphGeometry? {
        let sourceEvidencePresenter = FilmModeDetailsGraphEvidencePresenter()
        let sourceReferenceMarkers = sourceEvidencePresenter.markers(
            for: bindingState.profile,
            formatDuration: formatDuration
        )
        let notRecommendedBoundarySeconds = sourceEvidencePresenter.notRecommendedBoundarySeconds(
            for: bindingState.profile
        )

        let tierSelection = selectFormulaGraphScaleTier(
            formulaRule: formulaRule,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            sourceReferenceMarkers: sourceReferenceMarkers,
            notRecommendedBoundarySeconds: notRecommendedBoundarySeconds
        )
        let tier = tierSelection.tier

        let supportedUpperBoundSeconds = formulaRule.formula.sourceRangeThroughSeconds
        let noCorrectionRangeUpperBoundSeconds = effectiveNoCorrectionUpperBoundSeconds(
            for: bindingState
        )

        // Profile-stable viewport: same profile + same scale tier
        // always produces the same graph frame so the user sees
        // only the current-result marker move while sweeping the
        // input.
        let stableLowerBoundSeconds = formulaGraphStableLowerBoundSeconds

        let sourcePoints = FilmModeDetailsGraphCurveSampler().sourcePoints(
            FilmModeDetailsGraphCurveSampler.Inputs(
                rule: formulaRule,
                profile: bindingState.profile,
                currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                tierUpperBoundSeconds: tier.upperBoundSeconds,
                viewportLowerBoundSeconds: stableLowerBoundSeconds,
                noCorrectionRangeUpperBoundSeconds: noCorrectionRangeUpperBoundSeconds
            )
        )
        guard sourcePoints.count >= 2 else {
            return nil
        }

        let isBelowVisibleRange = isCurrentInputBelowVisibleLowerBound(
            viewportLowerBoundSeconds: stableLowerBoundSeconds,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint
        )
        let textPresenter = FilmModeDetailsGraphTextPresenter()
        let descriptionLines = textPresenter.descriptionLines(
            for: bindingState,
            isBeyondVisibleRange: tierSelection.isBeyondVisibleRange,
            isBelowVisibleRange: isBelowVisibleRange
        )
        // Custom and preset profiles share the `ReciprocityFormula`
        // schema, so the same equation formatter renders both.
        let formulaDisplayText = FormulaEquationFormatter.userFacingText(for: formulaRule.formula)
        let beyondSourceRangeStartSeconds = textPresenter.beyondSourceRangeStartSeconds(
            profile: bindingState.profile,
            supportedUpperBoundSeconds: supportedUpperBoundSeconds
        )

        // Only fall back to the "current input as x-position only" view
        // when the unsupported result truly carries no numeric corrected
        // exposure. Formula-derived numeric results past the supported
        // boundary plot a real (x, y) point so the user can see the
        // value on the curve.
        let usesCurrentInputGuideOnly = bindingState.presentation.category == .unsupported
            && currentPoint == nil

        return FormulaGraphGeometry(
            formulaRule: formulaRule,
            sourceReferenceMarkers: sourceReferenceMarkers,
            notRecommendedBoundarySeconds: notRecommendedBoundarySeconds,
            tier: tier,
            isBeyondVisibleRange: tierSelection.isBeyondVisibleRange,
            supportedUpperBoundSeconds: supportedUpperBoundSeconds,
            noCorrectionRangeUpperBoundSeconds: noCorrectionRangeUpperBoundSeconds,
            stableLowerBoundSeconds: stableLowerBoundSeconds,
            sourcePoints: sourcePoints,
            isBelowVisibleRange: isBelowVisibleRange,
            descriptionLines: descriptionLines,
            formulaDisplayText: formulaDisplayText,
            beyondSourceRangeStartSeconds: beyondSourceRangeStartSeconds,
            usesCurrentInputGuideOnly: usesCurrentInputGuideOnly
        )
    }

    private func buildFormulaGraphDisplayState(
        geometry: FormulaGraphGeometry,
        bindingState: FilmModeReciprocityBindingState,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?
    ) -> FilmModeDetailsGraphDisplayState {
        let textPresenter = FilmModeDetailsGraphTextPresenter()
        return FilmModeDetailsGraphDisplayState(
            kind: .formula,
            // Neutral title that reads sensibly for every formula
            // profile — converted formula profiles carry source
            // reference markers, but unofficial-practical formula
            // profiles do not. "Reciprocity Graph" works for both.
            title: "Reciprocity Graph",
            sourcePoints: geometry.sourcePoints,
            currentPoint: currentPoint,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            usesCurrentInputGuideOnly: geometry.usesCurrentInputGuideOnly,
            caption: textPresenter.caption(
                for: bindingState,
                noCorrectionRangeUpperBoundSeconds: geometry.noCorrectionRangeUpperBoundSeconds
            ),
            unsupportedExplanation: textPresenter.unsupportedExplanation(for: bindingState),
            xAxisLabel: "Adjusted shutter",
            yAxisLabel: "Corrected exposure",
            xAxisTicks: formulaGraphAxisTicks(
                tier: geometry.tier,
                viewportLowerBoundSeconds: geometry.stableLowerBoundSeconds
            ),
            yAxisTicks: formulaGraphAxisTicks(
                tier: geometry.tier,
                viewportLowerBoundSeconds: geometry.stableLowerBoundSeconds
            ),
            supportedRangeUpperBoundSeconds: geometry.supportedUpperBoundSeconds,
            unsupportedRegionStartSeconds: textPresenter.unsupportedRegionStartSeconds(
                supportedUpperBoundSeconds: geometry.supportedUpperBoundSeconds,
                currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                isUnsupported: bindingState.presentation.category == .unsupported
            ),
            noCorrectionRangeUpperBoundSeconds: geometry.noCorrectionRangeUpperBoundSeconds,
            sourceReferenceMarkers: geometry.sourceReferenceMarkers,
            notRecommendedBoundarySeconds: geometry.notRecommendedBoundarySeconds,
            beyondSourceRangeStartSeconds: geometry.beyondSourceRangeStartSeconds,
            // User-defined (custom) profiles render their formula
            // text through the shared `CalculationBasisPresenter`
            // area below the graph instead of in the graph header,
            // so the same expression does not appear twice on the
            // editor preview / Details sheet. Preset profiles keep
            // the in-graph header text — the dedupe is scoped to
            // the custom path.
            formulaDisplayText: bindingState.profile.source.authority == .userDefined
                ? nil
                : geometry.formulaDisplayText,
            descriptionLines: geometry.descriptionLines,
            scaleTier: geometry.tier,
            isBeyondVisibleRange: geometry.isBeyondVisibleRange,
            isBelowVisibleRange: geometry.isBelowVisibleRange,
            xRange: geometry.stableLowerBoundSeconds...geometry.tier.upperBoundSeconds,
            yRange: geometry.stableLowerBoundSeconds...geometry.tier.upperBoundSeconds
        )
    }

    // MARK: - Viewport and tier selection

    /// Single shared lower bound for every formula-graph viewport.
    /// The value is profile-independent and input-independent so
    /// the same scale tier always produces the same graph frame —
    /// only the current-result marker moves as the user sweeps the
    /// input. The positive constant is required because a log
    /// scale cannot encode `0 s` directly; the no-correction green
    /// band still reads as starting at visual `0` because the band
    /// is drawn from the plot's leading edge (see
    /// `FilmModeDetailsGraph.noCorrectionRegion`). The chosen
    /// value sits one decade below 1 s so the green band always
    /// has visible width regardless of the profile's threshold.
    private var formulaGraphStableLowerBoundSeconds: Double { 0.01 }

    /// Axis ticks for the formula graph. Tier ticks anchor 1 s and
    /// above; sub-second labels are prepended only when they sit
    /// strictly above the viewport lower bound so the axis never
    /// exposes the lower-bound value itself as a user-visible
    /// no-correction start (visual `0` is communicated through
    /// the band drawing, not through an axis tick).
    private func formulaGraphAxisTicks(
        tier: FilmModeDetailsGraphScaleTier,
        viewportLowerBoundSeconds: Double
    ) -> [FilmModeDetailsGraphAxisTick] {
        let tierTicks = tier.axisTicks
        guard viewportLowerBoundSeconds < tier.lowerBoundSeconds else {
            return tierTicks
        }
        let subSecondCandidates: [FilmModeDetailsGraphAxisTick] = [
            FilmModeDetailsGraphAxisTick(value: 0.01, label: "1/100s"),
            FilmModeDetailsGraphAxisTick(value: 0.1, label: "1/10s"),
        ]
        let extended = subSecondCandidates.filter { $0.value > viewportLowerBoundSeconds }
        return extended + tierTicks
    }

    /// Effective no-correction upper bound used by the formula
    /// graph overlay. Reads from the formula rule's own
    /// `noCorrectionThroughSeconds` guard (formula profiles no
    /// longer carry a companion threshold rule). Falls back to
    /// threshold rules for the limited-guidance profile shape that
    /// still uses one.
    private func effectiveNoCorrectionUpperBoundSeconds(
        for bindingState: FilmModeReciprocityBindingState
    ) -> Double? {
        let formulaBounds = FilmModeDetailsGraphCurveSampler.profileFormulaNoCorrectionUpperBounds(
            in: bindingState.profile
        )
        if let formulaMax = formulaBounds.max() {
            return formulaMax
        }
        let tableBounds = FilmModeDetailsGraphCurveSampler.profileTableNoCorrectionUpperBounds(
            in: bindingState.profile
        )
        if let tableMax = tableBounds.max() {
            return tableMax
        }
        let thresholdBounds = bindingState.profile.rules.compactMap { rule -> Double? in
            guard case let .threshold(thresholdRule) = rule else { return nil }
            return thresholdRule.noCorrectionRange.maximumSeconds
        }
        return thresholdBounds.filter { $0 > 0 }.max()
    }

    /// `true` when the current input would draw at the plot's left
    /// edge instead of its real position because at least one of
    /// its coordinates is below the graph's stable viewport lower
    /// bound. Anything inside the viewport renders at its real
    /// position regardless of where it falls relative to 1 s.
    private func isCurrentInputBelowVisibleLowerBound(
        viewportLowerBoundSeconds: Double,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?
    ) -> Bool {
        let lower = viewportLowerBoundSeconds
        if currentMeteredExposureSeconds > 0,
           currentMeteredExposureSeconds < lower {
            return true
        }
        if let currentPoint {
            if currentPoint.point.meteredExposureSeconds > 0,
               currentPoint.point.meteredExposureSeconds < lower {
                return true
            }
            if currentPoint.point.correctedExposureSeconds > 0,
               currentPoint.point.correctedExposureSeconds < lower {
                return true
            }
        }
        return false
    }

    /// Picks the smallest scale tier that still contains every value
    /// the formula graph will plot: curve endpoints, current point,
    /// source-reference markers, and the not-recommended boundary.
    /// Returns the tier together with an overflow flag for the rare
    /// case where the relevant maximum exceeds the `t3` upper bound.
    private func selectFormulaGraphScaleTier(
        formulaRule: FormulaReciprocityRule,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        sourceReferenceMarkers: [FilmModeDetailsGraphSourceReference],
        notRecommendedBoundarySeconds: Double?
    ) -> (tier: FilmModeDetailsGraphScaleTier, isBeyondVisibleRange: Bool) {
        var maxValue: Double = 1

        let curveUpper = [
            formulaRule.formula.sourceRangeThroughSeconds,
            currentMeteredExposureSeconds,
        ]
        .compactMap { $0 }
        .filter { $0 > 0 }
        .max() ?? 0
        if curveUpper > 0 {
            maxValue = max(maxValue, curveUpper)
            if let curveUpperCorrected = FilmModeDetailsGraphCurveSampler.formulaCorrectedExposureSeconds(
                for: formulaRule.formula,
                meteredExposureSeconds: curveUpper
            ) {
                maxValue = max(maxValue, curveUpperCorrected)
            }
        }

        if let currentPoint {
            maxValue = max(maxValue, currentPoint.point.meteredExposureSeconds)
            maxValue = max(maxValue, currentPoint.point.correctedExposureSeconds)
        }

        for marker in sourceReferenceMarkers {
            maxValue = max(maxValue, marker.point.meteredExposureSeconds)
            maxValue = max(maxValue, marker.point.correctedExposureSeconds)
        }

        if let notRecommendedBoundarySeconds {
            maxValue = max(maxValue, notRecommendedBoundarySeconds)
        }

        return (
            tier: FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: maxValue),
            isBeyondVisibleRange: FilmModeDetailsGraphScalePolicy.isBeyondVisibleRange(
                maxPlottedSeconds: maxValue
            )
        )
    }

    // MARK: - Current point

    private func graphCurrentPoint(
        for bindingState: FilmModeReciprocityBindingState,
        calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    ) -> FilmModeDetailsGraphCurrentPoint? {
        guard case .success(let result) = calculationResult,
              result.resultShutterSeconds > 0 else {
            return nil
        }

        // In the no-correction range the corrected exposure equals
        // the adjusted shutter. Plot the identity point with the
        // dedicated `.noCorrection` style so it does not read as a
        // formula prediction. Formula-backed films land here when the
        // input drops below the no-correction threshold.
        if bindingState.policyResult.metadata.basis == .officialThresholdNoCorrection {
            return FilmModeDetailsGraphCurrentPoint(
                point: FilmModeDetailsGraphPoint(
                    meteredExposureSeconds: result.resultShutterSeconds,
                    correctedExposureSeconds: result.resultShutterSeconds
                ),
                style: .noCorrection
            )
        }

        guard let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds,
              correctedExposureSeconds > 0,
              bindingState.presentation.returnsCalculatedExposureTime else {
            return nil
        }

        let style: FilmModeDetailsGraphCurrentPointStyle
        switch bindingState.presentation.category {
        case .formulaDerived:
            style = .formulaDerived
        case .unsupported:
            // Numeric formula prediction outside the source range —
            // render with the beyond-source-range marker so the user
            // reads it as outside the supported range without losing
            // the on-curve placement.
            style = .beyondSourceRange
        case .limitedGuidance, .noCorrection:
            return nil
        }

        return FilmModeDetailsGraphCurrentPoint(
            point: FilmModeDetailsGraphPoint(
                meteredExposureSeconds: result.resultShutterSeconds,
                correctedExposureSeconds: correctedExposureSeconds
            ),
            style: style
        )
    }

}
