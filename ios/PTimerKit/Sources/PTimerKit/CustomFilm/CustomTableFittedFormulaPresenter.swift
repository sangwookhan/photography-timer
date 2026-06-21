// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// PTIMER-179 pure presenter that turns a custom **table** profile's
/// source anchors into an inspection-only, app-derived fitted-formula
/// view model.
///
/// Inspection-only: this produces a preview the photographer can
/// judge, never an active shooting calculation. The custom table keeps
/// driving corrected exposure (Table / App-formula selection is
/// PTIMER-180). The fitted formula is an app-derived candidate, not
/// source evidence, and is derived deterministically from the rule's
/// calculation anchors — `sourceEvidence` is never read here.
///
/// Pipeline: fit `Tc = a × Tm^p` (`ReciprocityFormulaFitter`) → map
/// into the guarded `ReciprocityFormula` shape (`b = 0`, `Tref = 1`,
/// inheriting the table's no-correction and source-range boundaries) →
/// reject any fit that fails the shared non-shortening guard
/// (`CustomFilmFormulaGuard`) → compare the fitted output against each
/// source anchor and classify the worst residual by the PTIMER-170
/// stop-error thresholds.
public enum CustomTableFittedFormulaPresenter {

    // MARK: - Stable copy

    public static let appDerivedLabel = "App-derived formula"
    public static let formulaFamilyLabel = "Power-law fit"

    /// Two-anchor power-law fits pass through both points exactly, so a
    /// zero residual says nothing about curve quality between them.
    public static let twoAnchorNote =
        "Fit passes through the two source anchors. "
        + "Add more anchors to judge curve quality between points."

    /// Disclaimer mirroring the Details "App-derived comparison"
    /// wording so the editor and the runtime sheet read the same.
    public static let notManufacturerNote =
        "App-derived from your table anchors. Not manufacturer-published guidance."

    /// Short, actionable hint shown in the table row area when the
    /// fitted preview is unavailable solely because the fit would
    /// shorten exposure (`.unavailable(.unusableShorteningFit)`). Names
    /// the two fixes the photographer can actually make; it never
    /// implies the table itself is invalid.
    public static let unusableShorteningRowMessage =
        "Fitted formula unavailable. Raise no correction or add a lower-range anchor."

    /// Heading the preview card shows in place of a fit-quality label
    /// when no formula can be produced.
    public static let unavailableTitle = "Unavailable fit"

    /// Reassurance that the unavailable formula does not affect the
    /// active calculation. Shared by the structured guidance and the
    /// flattened `displayMessage`.
    public static let tableRemainsReliableNote =
        "The table remains your reliable calculation."

    // MARK: - Fit quality (PTIMER-170 thresholds)

    /// Worst absolute anchor residual, in stops, at or below which the
    /// fit is a good match.
    public static let goodFitMaxStopError = 0.1
    /// Upper bound (in stops) of the borderline band; above it the fit
    /// is poor.
    public static let borderlineFitMaxStopError = 0.25

    public enum FitQuality: Equatable {
        case good
        case borderline
        case poor

        public var displayLabel: String {
            switch self {
            case .good: return "Good fit"
            case .borderline: return "Borderline fit"
            case .poor: return "Poor fit"
            }
        }
    }

    // MARK: - View model

    /// One source-anchor-vs-fitted comparison. Raw values; the view
    /// formats them with its own duration policy.
    public struct ComparisonRow: Equatable {
        public let meteredSeconds: Double
        /// The photographer's entered corrected time at this anchor.
        public let sourceCorrectedSeconds: Double
        /// The fitted formula's corrected time at the same metered
        /// input, via the shared evaluator.
        public let fittedCorrectedSeconds: Double
        /// `(fitted - source) / source × 100`.
        public let percentError: Double
        /// `log2(fitted / source)`.
        public let stopError: Double

        public init(
            meteredSeconds: Double,
            sourceCorrectedSeconds: Double,
            fittedCorrectedSeconds: Double,
            percentError: Double,
            stopError: Double
        ) {
            self.meteredSeconds = meteredSeconds
            self.sourceCorrectedSeconds = sourceCorrectedSeconds
            self.fittedCorrectedSeconds = fittedCorrectedSeconds
            self.percentError = percentError
            self.stopError = stopError
        }
    }

    /// A usable fitted-formula preview.
    public struct FittedFormula: Equatable {
        /// `a` in `Tc = a × Tm^p`. Maps to `coefficientSeconds`.
        public let coefficientSeconds: Double
        /// `p`.
        public let exponent: Double
        /// Always `0` in this slice (offset fitting is out of scope).
        public let offsetSeconds: Double
        /// Always `1` in this slice.
        public let referenceMeteredTimeSeconds: Double
        /// Inherited from the table rule.
        public let noCorrectionThroughSeconds: Double
        /// Inherited from the table rule (the last anchor's metered).
        public let sourceRangeThroughSeconds: Double
        public let comparisonRows: [ComparisonRow]
        /// `max` of `abs(stopError)` across the anchors.
        public let worstAbsoluteStopError: Double
        public let quality: FitQuality
        public let anchorCount: Int

        /// A two-anchor fit reproduces both anchors exactly, so its
        /// zero residual is not evidence of a good curve. The view
        /// surfaces `twoAnchorNote` and softens the quality wording.
        public var isTwoAnchorExactFit: Bool { anchorCount == 2 }

        public init(
            coefficientSeconds: Double,
            exponent: Double,
            offsetSeconds: Double,
            referenceMeteredTimeSeconds: Double,
            noCorrectionThroughSeconds: Double,
            sourceRangeThroughSeconds: Double,
            comparisonRows: [ComparisonRow],
            worstAbsoluteStopError: Double,
            quality: FitQuality,
            anchorCount: Int
        ) {
            self.coefficientSeconds = coefficientSeconds
            self.exponent = exponent
            self.offsetSeconds = offsetSeconds
            self.referenceMeteredTimeSeconds = referenceMeteredTimeSeconds
            self.noCorrectionThroughSeconds = noCorrectionThroughSeconds
            self.sourceRangeThroughSeconds = sourceRangeThroughSeconds
            self.comparisonRows = comparisonRows
            self.worstAbsoluteStopError = worstAbsoluteStopError
            self.quality = quality
            self.anchorCount = anchorCount
        }
    }

    /// Why a fitted-formula preview cannot be shown. The table profile
    /// itself stays valid and usable in every case.
    public enum Unavailable: Equatable {
        case fit(ReciprocityFormulaFitter.UnavailableReason)
        /// The fit is finite but would shorten exposure somewhere in
        /// the usable range (fails the shared non-shortening guard) or
        /// at an anchor.
        case unusableShorteningFit
        /// The mapped formula failed the guarded-formula parameter
        /// contract (e.g. a non-positive exponent).
        case invalidParameters

        /// Structured recovery guidance the preview card renders: a
        /// one-line cause, zero or more concrete fixes the photographer
        /// can act on, and whether to reassure that the table still
        /// calculates. Keeping it structured (rather than one prose
        /// blob) lets the card lay the parts out and lets tests assert
        /// each part is present.
        public struct Guidance: Equatable {
            public let cause: String
            public let recoveryActions: [String]
            public let tableRemainsReliable: Bool

            public init(
                cause: String,
                recoveryActions: [String],
                tableRemainsReliable: Bool
            ) {
                self.cause = cause
                self.recoveryActions = recoveryActions
                self.tableRemainsReliable = tableRemainsReliable
            }
        }

        public var guidance: Guidance {
            switch self {
            case .unusableShorteningFit:
                return Guidance(
                    cause: "The fitted formula would shorten exposure with the "
                        + "current table boundaries.",
                    recoveryActions: [
                        "Raise no correction",
                        "Add an anchor near the lower range",
                    ],
                    tableRemainsReliable: true
                )
            case .fit(.insufficientAnchors):
                return Guidance(
                    cause: "Add at least two anchors to fit a formula.",
                    recoveryActions: [],
                    tableRemainsReliable: true
                )
            case .fit(.nonPositiveAnchors):
                return Guidance(
                    cause: "Anchor times must be positive to fit a formula.",
                    recoveryActions: [],
                    tableRemainsReliable: true
                )
            case .fit(.degenerateAnchors):
                return Guidance(
                    cause: "Anchors must span more than one metered time.",
                    recoveryActions: [],
                    tableRemainsReliable: true
                )
            case .fit(.nonFiniteResult), .invalidParameters:
                return Guidance(
                    cause: "These anchors do not produce a usable formula.",
                    recoveryActions: [],
                    tableRemainsReliable: true
                )
            }
        }

        /// Flattened single-string form, composed from `guidance` so the
        /// two never drift. Used where a structured layout is not
        /// available.
        public var displayMessage: String {
            let guidance = self.guidance
            var lines = [guidance.cause]
            if !guidance.recoveryActions.isEmpty {
                lines.append(guidance.recoveryActions.joined(separator: ", ") + ".")
            }
            if guidance.tableRemainsReliable {
                lines.append(CustomTableFittedFormulaPresenter.tableRemainsReliableNote)
            }
            return lines.joined(separator: "\n")
        }
    }

    public enum Outcome: Equatable {
        case available(FittedFormula)
        case unavailable(Unavailable)
    }

    // MARK: - Derivation

    /// Derives the fitted-formula preview from a table rule's anchors.
    public static func outcome(
        for rule: TableInterpolationReciprocityRule
    ) -> Outcome {
        let anchors = rule.sortedAnchors

        let fit: ReciprocityFormulaFitter.PowerLawFit
        switch ReciprocityFormulaFitter.fit(anchors: anchors) {
        case let .success(value):
            fit = value
        case let .failure(reason):
            return .unavailable(.fit(reason))
        }

        let formula = ReciprocityFormula(
            coefficientSeconds: fit.coefficient,
            referenceMeteredTimeSeconds: 1,
            exponent: fit.exponent,
            offsetSeconds: 0,
            noCorrectionThroughSeconds: rule.noCorrectionThroughSeconds,
            sourceRangeThroughSeconds: rule.sourceRangeThroughSeconds
        )
        guard formula.hasValidParameters else {
            return .unavailable(.invalidParameters)
        }
        let guardInput = CustomFilmFormulaGuard.UsableRangeInput(
            exponent: formula.exponent,
            referenceMeteredTimeSeconds: formula.referenceMeteredTimeSeconds,
            coefficientSeconds: formula.coefficientSeconds,
            offsetSeconds: formula.offsetSeconds,
            noCorrectionThroughSeconds: formula.noCorrectionThroughSeconds,
            sourceRangeThroughSeconds: formula.sourceRangeThroughSeconds
        )
        guard CustomFilmFormulaGuard.passesUsableRangeCheck(guardInput) else {
            return .unavailable(.unusableShorteningFit)
        }

        var rows: [ComparisonRow] = []
        for anchor in anchors {
            guard let fitted = fittedCorrectedSeconds(
                formula,
                meteredSeconds: anchor.meteredSeconds
            ) else {
                return .unavailable(.unusableShorteningFit)
            }
            let source = anchor.correctedSeconds
            rows.append(ComparisonRow(
                meteredSeconds: anchor.meteredSeconds,
                sourceCorrectedSeconds: source,
                fittedCorrectedSeconds: fitted,
                percentError: (fitted - source) / source * 100,
                stopError: log2(fitted / source)
            ))
        }

        let worst = rows.map { abs($0.stopError) }.max() ?? 0
        return .available(FittedFormula(
            coefficientSeconds: formula.coefficientSeconds,
            exponent: formula.exponent,
            offsetSeconds: formula.offsetSeconds,
            referenceMeteredTimeSeconds: formula.referenceMeteredTimeSeconds,
            noCorrectionThroughSeconds: formula.noCorrectionThroughSeconds,
            sourceRangeThroughSeconds: rule.sourceRangeThroughSeconds,
            comparisonRows: rows,
            worstAbsoluteStopError: worst,
            quality: quality(forWorstAbsoluteStopError: worst),
            anchorCount: anchors.count
        ))
    }

    public static func quality(forWorstAbsoluteStopError worst: Double) -> FitQuality {
        if worst <= goodFitMaxStopError { return .good }
        if worst <= borderlineFitMaxStopError { return .borderline }
        return .poor
    }

    // MARK: - Parameter formatting

    /// Photographer-facing rendering of a fit parameter (`a`, `p`):
    /// fixed decimals at roughly four significant digits, trailing
    /// zeros trimmed — never scientific notation, so the
    /// `Tc = a × Tm^p` line always reads as a plain number.
    public static func parameterText(_ value: Double) -> String {
        let decimals = parameterDecimals(forMagnitude: abs(value))
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    private static func parameterDecimals(forMagnitude magnitude: Double) -> Int {
        if magnitude >= 1000 { return 0 }
        if magnitude >= 100 { return 1 }
        if magnitude >= 10 { return 2 }
        if magnitude >= 0.01 { return 3 }
        return 5
    }

    /// Corrected exposure the shared evaluator produces, so the
    /// comparison uses identical math to the runtime — `nil` only when
    /// the evaluator rejects the input (which the upstream guard makes
    /// unreachable for in-range anchors, handled defensively).
    private static func fittedCorrectedSeconds(
        _ formula: ReciprocityFormula,
        meteredSeconds: Double
    ) -> Double? {
        switch formula.evaluate(meteredExposureSeconds: meteredSeconds) {
        case let .withinSourceRange(corrected),
             let .beyondSourceRange(corrected):
            return corrected
        case .noCorrection:
            return meteredSeconds
        case .invalidInput, .invalidFormula, .formulaOutputUnusable, .unsafeShorteningFormula:
            return nil
        }
    }
}
