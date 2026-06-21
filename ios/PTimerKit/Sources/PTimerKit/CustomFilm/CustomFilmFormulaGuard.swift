// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Shared correctness helpers for the custom-film formula model.
/// The editor validate path, the persistence sanitation path, and
/// the preview presenter all enforce the same `Tc >= Tm` invariant
/// through this guard.
///
/// Field names mirror the shared `ReciprocityFormula`
/// (`coefficientSeconds`, `referenceMeteredTimeSeconds`,
/// `noCorrectionThroughSeconds`, `sourceRangeThroughSeconds`) so
/// custom and preset profiles speak the same vocabulary at the
/// authoring layer.
///
/// The check is **analytic**, not sample-based. Reparameterising
/// `Tc(t) = a · (t / Tref)^e + b` as `f(t) = c · t^e + b - t` with
/// `c = a / Tref^e` gives a function with at most one interior
/// critical point on `(0, ∞)`. Verifying f at the two endpoints
/// plus the critical point — when it falls inside the usable
/// range — therefore covers the whole interval. A sparse
/// log-spaced scan could silently miss between samples; the
/// analytic check cannot.
public enum CustomFilmFormulaGuard {
    /// Non-shortening slack matching the runtime evaluator's safety
    /// net (`ReciprocityFormula.evaluate` rejects
    /// `Tc < Tm - 1e-6`), so a formula this guard approves can never
    /// trip the runtime clamp — and the per-anchor preview comparison
    /// can never contradict the guard. Still generous enough that a
    /// flat `Tc = Tm` boundary stays valid under floating-point
    /// rounding (~1e-12 absolute at hour-scale magnitudes).
    private static let slackSeconds: Double = 1e-6

    /// Parameter bundle for `passesUsableRangeCheck` — kept as a
    /// struct so the helper stays under the swiftlint parameter
    /// limit and call sites can name fields without positional
    /// ambiguity. Names match the shared `ReciprocityFormula`.
    public struct UsableRangeInput {
        public let exponent: Double
        public let referenceMeteredTimeSeconds: Double
        public let coefficientSeconds: Double
        public let offsetSeconds: Double
        public let noCorrectionThroughSeconds: Double
        public let sourceRangeThroughSeconds: Double?
        public init(exponent: Double, referenceMeteredTimeSeconds: Double, coefficientSeconds: Double, offsetSeconds: Double, noCorrectionThroughSeconds: Double, sourceRangeThroughSeconds: Double?) {
            self.exponent = exponent
            self.referenceMeteredTimeSeconds = referenceMeteredTimeSeconds
            self.coefficientSeconds = coefficientSeconds
            self.offsetSeconds = offsetSeconds
            self.noCorrectionThroughSeconds = noCorrectionThroughSeconds
            self.sourceRangeThroughSeconds = sourceRangeThroughSeconds
        }
    }

    /// Returns `true` when no `Tm` in the usable formula range
    /// produces `Tc < Tm`.
    public static func passesUsableRangeCheck(_ input: UsableRangeInput) -> Bool {
        let exponent = input.exponent
        let referenceMeteredTime = input.referenceMeteredTimeSeconds
        let coefficient = input.coefficientSeconds
        let offset = input.offsetSeconds
        let noCorrectionThrough = input.noCorrectionThroughSeconds
        let sourceRangeThrough = input.sourceRangeThroughSeconds

        // Defensive: the validator parses for finiteness already,
        // but guard against pathological inputs the sanitation
        // path may receive directly.
        guard exponent.isFinite, exponent > 0,
              referenceMeteredTime.isFinite, referenceMeteredTime > 0,
              coefficient.isFinite, coefficient > 0,
              offset.isFinite,
              noCorrectionThrough.isFinite, noCorrectionThrough >= 0 else {
            return false
        }
        if let sourceRangeThrough,
           !(sourceRangeThrough.isFinite && sourceRangeThrough > noCorrectionThrough) {
            return false
        }

        // Reparameterise to `f(t) = c · t^e + offset - t` so the
        // endpoints + critical point analysis works in a single
        // closed-form variable.
        let scaledCoefficient = coefficient / pow(referenceMeteredTime, exponent)
        let lower = max(noCorrectionThrough, 1e-9)

        let formula = ShorteningFormula(
            coefficient: scaledCoefficient,
            exponent: exponent,
            offset: offset
        )

        // exponent == 1: f is linear (slope = c - 1). Behaviour
        // determined entirely by `c` and (for finite ranges) the
        // endpoints.
        if abs(exponent - 1.0) < 1e-9 {
            return passesLinearCase(
                formula: formula,
                lower: lower,
                sourceRangeThrough: sourceRangeThrough
            )
        }

        // exponent < 1: f is concave on `(0, ∞)` (second
        // derivative c·e·(e-1)·t^(e-2) < 0), so the minimum on a
        // closed interval sits at an endpoint. With Unlimited the
        // formula eventually shortens regardless of `c`, so
        // reject outright.
        if exponent < 1 {
            guard let upper = sourceRangeThrough else { return false }
            return formula.fIsNonNegative(at: lower)
                && formula.fIsNonNegative(at: upper)
        }

        // exponent > 1: f is convex on `(0, ∞)`. Endpoints handle
        // the boundary case; an interior critical point — when it
        // exists and falls inside the usable range — is the only
        // other place the minimum can live.
        guard formula.fIsNonNegative(at: lower) else { return false }
        if let upper = sourceRangeThrough, !formula.fIsNonNegative(at: upper) {
            return false
        }
        // Critical point: solve f'(t*) = c·e·t*^(e-1) - 1 = 0
        // → t* = (1 / (c·e))^(1/(e-1)).
        let denominator = scaledCoefficient * exponent
        guard denominator > 0 else {
            // No real critical point with positive `t*` — the
            // endpoint checks already covered the range.
            return true
        }
        let critical = pow(1.0 / denominator, 1.0 / (exponent - 1.0))
        let upperBound = sourceRangeThrough ?? .infinity
        if critical.isFinite, critical > lower, critical < upperBound {
            return formula.fIsNonNegative(at: critical)
        }
        return true
    }

    private static func passesLinearCase(
        formula: ShorteningFormula,
        lower: Double,
        sourceRangeThrough: Double?
    ) -> Bool {
        let slope = formula.coefficient - 1.0
        if slope > 1e-9 {
            // Monotonically increasing — lower endpoint suffices.
            return formula.fIsNonNegative(at: lower)
        }
        if slope < -1e-9 {
            // Monotonically decreasing — Unlimited eventually
            // shortens, finite ranges must clear the upper bound.
            guard let upper = sourceRangeThrough else { return false }
            return formula.fIsNonNegative(at: lower)
                && formula.fIsNonNegative(at: upper)
        }
        // c == 1 → f(t) = offset, constant. Need offset >= 0.
        return formula.offset >= -slackSeconds
    }

    /// Internal compact view of the shortening function used by
    /// the analytic checks. Kept private to this enum so the
    /// invariant (slackSeconds tolerance) stays in one place.
    private struct ShorteningFormula {
        let coefficient: Double
        let exponent: Double
        let offset: Double

        /// Returns `Tc(t) >= t - slack`, written in the same form as
        /// the runtime evaluator's safety net
        /// (`corrected >= metered - 1e-6`) so the two checks agree
        /// bit-for-bit when the arithmetic matches.
        func fIsNonNegative(at t: Double) -> Bool {
            guard t > 0 else { return offset >= -slackSeconds }
            let tc = coefficient * pow(t, exponent) + offset
            return tc >= t - slackSeconds
        }
    }
}

/// Parser for the duration-style strings the editor accepts in
/// the application-range fields (`No correction until`,
/// `Source data through`).
///
/// Accepted shapes:
/// - empty string → `nil` (caller decides default / Unlimited)
/// - plain decimal `"100"` → 100s
/// - suffixed `"100s"`, `"5m"`, `"1h"` → 100s / 300s / 3600s
/// - case-insensitive `"unlimited"` → returns `.unlimited`
/// - anything else → returns `nil`
public enum CustomFilmDurationParser {
    public enum ParsedDuration: Equatable {
        case seconds(Double)
        case unlimited
        case empty
    }

    public static func parse(_ text: String) -> ParsedDuration? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if trimmed.caseInsensitiveCompare("unlimited") == .orderedSame {
            return .unlimited
        }
        let lowered = trimmed.lowercased()
        if let plain = Double(lowered), plain.isFinite {
            return .seconds(plain)
        }
        if let unit = lowered.last {
            let body = String(lowered.dropLast())
            guard let value = Double(body), value.isFinite else { return nil }
            switch unit {
            case "s": return .seconds(value)
            case "m": return .seconds(value * 60)
            case "h": return .seconds(value * 3600)
            default: return nil
            }
        }
        return nil
    }
}
