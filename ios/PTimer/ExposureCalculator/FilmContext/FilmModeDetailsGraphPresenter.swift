import Foundation

/// Pure presenter for the Film Details reciprocity graph.
///
/// Owns every aspect of the formula graph that does not belong with
/// the table of source references or with the per-state wording:
/// curve sampling, viewport / scale-tier selection, current-marker
/// placement, source-evidence markers, the not-recommended boundary,
/// the persistent beyond-source-range shading, the formula equation
/// text, axis ticks, and the state-aware caption / description /
/// unsupported explanation.
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

        return formulaDetailsGraphDisplayState(
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

    /// Pre-computed values shared between the geometry builder and the
    /// final display-state assembly. Lives next to the helper so the
    /// graph constructor stays under the function-body-length limit.
    private struct FormulaGraphGeometry {
        let formulaRule: FormulaReciprocityRule
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
        let formulaDisplayText: String
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
        let sourceReferenceMarkers = formulaGraphSourceReferenceMarkers(
            for: bindingState.profile,
            formatDuration: formatDuration
        )
        let notRecommendedBoundarySeconds = formulaGraphNotRecommendedBoundarySeconds(
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

        let supportedUpperBoundSeconds = formulaRule.meteredRange?.maximumSeconds
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
        let descriptionLines = formulaGraphDescriptionLines(
            for: bindingState,
            isBeyondVisibleRange: tierSelection.isBeyondVisibleRange,
            isBelowVisibleRange: isBelowVisibleRange
        )
        let formulaDisplayText = FormulaEquationFormatter.userFacingText(for: formulaRule.formula)
        let beyondSourceRangeStartSeconds = formulaGraphBeyondSourceRangeStartSeconds(
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
        FilmModeDetailsGraphDisplayState(
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
            caption: formulaGraphCaption(
                for: bindingState,
                noCorrectionRangeUpperBoundSeconds: geometry.noCorrectionRangeUpperBoundSeconds
            ),
            unsupportedExplanation: graphUnsupportedExplanation(for: bindingState),
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
            unsupportedRegionStartSeconds: unsupportedRegionStartSeconds(
                supportedUpperBoundSeconds: geometry.supportedUpperBoundSeconds,
                currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                isUnsupported: bindingState.presentation.category == .unsupported
            ),
            noCorrectionRangeUpperBoundSeconds: geometry.noCorrectionRangeUpperBoundSeconds,
            sourceReferenceMarkers: geometry.sourceReferenceMarkers,
            notRecommendedBoundarySeconds: geometry.notRecommendedBoundarySeconds,
            beyondSourceRangeStartSeconds: geometry.beyondSourceRangeStartSeconds,
            formulaDisplayText: geometry.formulaDisplayText,
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
    /// graph overlay. Combines explicit threshold rules with the
    /// policy's default formula no-correction handoff (1 s) so
    /// formula-only profiles like Portra 400 unofficial still show
    /// a visible no-correction band on the graph instead of
    /// implying no policy structure exists below 1 s.
    private func effectiveNoCorrectionUpperBoundSeconds(
        for bindingState: FilmModeReciprocityBindingState
    ) -> Double? {
        let explicitMax = FilmModeDetailsGraphCurveSampler.profileThresholdUpperBounds(in: bindingState.profile)
            .filter { $0 > 0 }
            .max()
        let formulaOnly = FilmModeDetailsGraphCurveSampler.profileUsesFormula(bindingState.profile)
            && FilmModeDetailsGraphCurveSampler.profileThresholdUpperBounds(in: bindingState.profile).isEmpty
        let synthesizedDefault: Double? = formulaOnly ? policyDefaultFormulaNoCorrectionUpperBoundSeconds : nil
        switch (explicitMax, synthesizedDefault) {
        case let (explicit?, default_?):
            return max(explicit, default_)
        case let (explicit?, nil):
            return explicit
        case let (nil, default_?):
            return default_
        case (nil, nil):
            return nil
        }
    }

    /// Mirrors the policy evaluator's default formula no-correction
    /// upper bound so the graph overlay agrees with the calculation
    /// result. Kept as a single literal in both places (the policy
    /// evaluator owns the authoritative constant); a contract test
    /// in the policy suite ties the two so they cannot drift apart.
    private var policyDefaultFormulaNoCorrectionUpperBoundSeconds: Double { 1.0 }

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
            formulaRule.meteredRange?.maximumSeconds,
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

    // MARK: - Source-reference markers and boundary

    /// Produces open-ring markers for manufacturer source-evidence
    /// rows that publish a quantified exposure adjustment (e.g.
    /// Provia 100F's 240 s +1/3 stop reference). Rows whose only
    /// adjustment is a `notRecommended` warning are intentionally
    /// excluded so a stop-signal boundary never reads as a formula
    /// fitting point. Each marker carries an adjacent text label
    /// (e.g. "240s") so the user reads the published metered value
    /// directly off the graph.
    private func formulaGraphSourceReferenceMarkers(
        for profile: ReciprocityProfile,
        formatDuration: (Double) -> String
    ) -> [FilmModeDetailsGraphSourceReference] {
        profile.sourceEvidence.compactMap { row -> FilmModeDetailsGraphSourceReference? in
            guard case let .exactSeconds(meteredExposureSeconds) = row.meteredExposure,
                  meteredExposureSeconds > 0,
                  !ReciprocitySourceEvidenceClassifier.isGuidanceBoundary(row),
                  !row.isSourceEvidenceOnly else {
                return nil
            }
            guard let correctedExposureSeconds = sourceEvidenceCorrectedExposureSeconds(
                meteredExposureSeconds: meteredExposureSeconds,
                adjustments: row.adjustments
            ), correctedExposureSeconds > 0 else {
                return nil
            }
            return FilmModeDetailsGraphSourceReference(
                point: FilmModeDetailsGraphPoint(
                    meteredExposureSeconds: meteredExposureSeconds,
                    correctedExposureSeconds: correctedExposureSeconds
                ),
                label: sourceReferenceMarkerLabel(
                    meteredExposureSeconds: meteredExposureSeconds,
                    formatDuration: formatDuration
                )
            )
        }
    }

    /// Marker label for a source-reference point. Prefers the bare
    /// "{seconds}s" form for whole-second values so Provia 100F's
    /// 240 s reference reads as "240s" on the graph; falls back to
    /// the standard duration formatter for fractional values.
    private func sourceReferenceMarkerLabel(
        meteredExposureSeconds: Double,
        formatDuration: (Double) -> String
    ) -> String {
        let rounded = meteredExposureSeconds.rounded()
        if abs(meteredExposureSeconds - rounded) < 1e-6, rounded > 0, rounded < 1e9 {
            return "\(Int(rounded))s"
        }
        return formatDuration(meteredExposureSeconds)
    }

    private func formulaGraphNotRecommendedBoundarySeconds(
        for profile: ReciprocityProfile
    ) -> Double? {
        for row in profile.sourceEvidence {
            guard case let .exactSeconds(seconds) = row.meteredExposure,
                  seconds > 0,
                  ReciprocitySourceEvidenceClassifier.isGuidanceBoundary(row) else {
                continue
            }
            return seconds
        }
        return nil
    }

    private func sourceEvidenceCorrectedExposureSeconds(
        meteredExposureSeconds: Double,
        adjustments: [ReciprocityAdjustment]
    ) -> Double? {
        // Prefer the published correctedTime when the row carries
        // both forms: Kodak (and several other manufacturers) publish
        // the stop delta as a rounded quick-reference alongside a
        // separately-published corrected time, and those two values
        // can disagree by up to a third of a stop (e.g. Tri-X 400's
        // 10 sec row publishes "+2 stops" and "50 sec" even though
        // +2 stops literally derives to 40 sec). Returning the
        // stop-delta derivation here would plot the source-reference
        // marker at the wrong y-coordinate.
        var stopAdjustment: StopDeltaAdjustment?
        var multiplierAdjustment: MultiplierAdjustment?
        for adjustment in adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else {
                continue
            }
            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return mapping.correctedSeconds
            case .stopDelta(let value):
                if stopAdjustment == nil { stopAdjustment = value }
            case .multiplier(let value):
                if multiplierAdjustment == nil { multiplierAdjustment = value }
            }
        }
        if let stopAdjustment {
            return meteredExposureSeconds * pow(2, stopAdjustment.stopDelta)
        }
        if let multiplierAdjustment {
            return meteredExposureSeconds * multiplierAdjustment.factor
        }
        return nil
    }

    // MARK: - State-aware text

    /// Returns at most one short, state-aware note for the formula
    /// graph. The marker/region legend already names each visible
    /// element, so the note is reserved for the cases that need a
    /// brief sentence: outside the visible range, and the formula
    /// prediction outside the published source range.
    private func formulaGraphDescriptionLines(
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
           bindingState.profile.isConvertedFormulaProfile {
            return ["Formula-derived result outside published source range."]
        }
        return []
    }

    /// Metered-exposure x at which the published manufacturer source
    /// range ends for a converted formula profile. Drives the
    /// persistent pink shading on the formula graph so the user can
    /// always see which region of the curve is the formula prediction
    /// outside the published source range.
    private func formulaGraphBeyondSourceRangeStartSeconds(
        profile: ReciprocityProfile,
        supportedUpperBoundSeconds: Double?
    ) -> Double? {
        guard profile.isConvertedFormulaProfile else {
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
    private func formulaGraphCaption(
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
            return "Formula prediction outside the manufacturer-supported boundary"
        }

        return "Adjusted shutter vs corrected exposure on the active calculation curve"
    }

    private func graphUnsupportedExplanation(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        guard bindingState.presentation.category == .unsupported else {
            return nil
        }

        // Distinguish "outside guidance with a numeric formula
        // prediction available" from "outside guidance with no value
        // at all". Same copy in both cases would mask the timer-start
        // affordance for the numeric path.
        if bindingState.policyResult.correctedExposureSeconds != nil {
            if bindingState.profile.isConvertedFormulaProfile {
                return "Current input is beyond the manufacturer source range. The plotted value is a formula prediction past the published reference and should be verified."
            }
            return "Current input is outside manufacturer guidance. The plotted value is a formula prediction outside the supported range and should be verified."
        }

        return "Current input is outside the supported range. No quantified corrected point is available."
    }

    private func unsupportedRegionStartSeconds(
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
