import Foundation

/// Shared correctness helpers for
/// the custom-film formula model. The previous validator only
/// sampled the no-correction boundary, which let `exponent < 1`
/// formulas slip through even though they would shorten metered
/// exposures at longer times. This helper centralises the usable-
/// range check so the editor validate path, the persistence
/// sanitation path, and the preview presenter all enforce the
/// same rule.
enum CustomFilmFormulaGuard {
    /// Upper sample horizon for `Unlimited` valid-through. 3
    /// hours is enough to catch any sub-1 exponent that would
    /// shorten realistic photographic exposures while avoiding
    /// floating-point overflow at extreme metered values.
    static let unlimitedSampleHorizonSeconds: Double = 10800

    /// Sample count for the log-spaced range scan. 24 samples
    /// across [noCorrectionThrough, upper] gives sub-stop
    /// resolution while keeping validation cheap on every
    /// keystroke.
    static let sampleCount: Int = 24

    /// Returns `true` when `Tc(T_m) = baseTc · (T_m / baseTm)^e + offset`
    /// stays at or above `T_m` everywhere in the formula's usable
    /// range. The check is sample-based with a 1 ms tolerance so a
    /// perfectly flat boundary (T_c = T_m at the lower edge) is
    /// not rejected by rounding noise.
    ///
    /// `Unlimited` (`validThrough == nil`) with `exponent < 1` is
    /// rejected outright because the formula will eventually
    /// shorten any metered value past the chosen sample horizon —
    /// trying to draw the line elsewhere produces fragile
    /// edge cases. The same Unlimited case with `exponent == 1`
    /// is caught by the sample at the horizon when
    /// `baseTc < baseTm` (the limit of T_c/T_m is `baseTc / baseTm`).
    /// Parameter bundle for `passesUsableRangeCheck` — kept as a
    /// struct so the helper stays under the swiftlint parameter
    /// limit and call sites can name fields without positional
    /// ambiguity.
    /// Parameter bundle for `passesUsableRangeCheck`. Field names
    /// mirror the shared `ReciprocityFormula` so custom
    /// and preset profiles speak the same vocabulary at the
    /// authoring layer.
    struct UsableRangeInput {
        let exponent: Double
        let referenceMeteredTimeSeconds: Double
        let coefficientSeconds: Double
        let offsetSeconds: Double
        let noCorrectionThroughSeconds: Double
        let sourceRangeThroughSeconds: Double?
    }

    static func passesUsableRangeCheck(_ input: UsableRangeInput) -> Bool {
        let exponent = input.exponent
        let referenceMeteredTime = input.referenceMeteredTimeSeconds
        let coefficient = input.coefficientSeconds
        let offset = input.offsetSeconds
        let noCorrectionThrough = input.noCorrectionThroughSeconds
        let sourceRangeThrough = input.sourceRangeThroughSeconds
        // Defensive: the validator parses for finiteness already,
        // but guard against pathological inputs the sanitation
        // path may receive directly.
        guard exponent.isFinite, referenceMeteredTime.isFinite, referenceMeteredTime > 0,
              coefficient.isFinite, coefficient > 0,
              offset.isFinite,
              noCorrectionThrough.isFinite, noCorrectionThrough >= 0 else {
            return false
        }

        if exponent < 1, sourceRangeThrough == nil {
            return false
        }

        let upper = sourceRangeThrough ?? unlimitedSampleHorizonSeconds
        let lower = max(noCorrectionThrough, 1e-3)
        guard upper > lower else {
            // Range collapses to a single point — only the
            // boundary check matters and `Tc(lower) >= lower` is
            // the right test.
            let tc = coefficient * pow(lower / referenceMeteredTime, exponent) + offset
            return tc + 0.001 >= lower
        }

        let logLower = log(lower)
        let logUpper = log(upper)
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            let metered = exp(logLower + (logUpper - logLower) * t)
            let tc = coefficient * pow(metered / referenceMeteredTime, exponent) + offset
            if tc + 0.001 < metered {
                return false
            }
        }
        return true
    }
}

/// Parser for the duration-style
/// strings the editor accepts in the application-range fields
/// (`No correction up to`, `Source range through`).
///
/// Accepted shapes:
/// - empty string → `nil` (caller decides default / Unlimited)
/// - plain decimal `"100"` → 100s
/// - suffixed `"100s"`, `"5m"`, `"1h"` → 100s / 300s / 3600s
/// - case-insensitive `"unlimited"` → returns `.unlimited`
/// - anything else → returns `nil`
enum CustomFilmDurationParser {
    enum ParsedDuration: Equatable {
        case seconds(Double)
        case unlimited
        case empty
    }

    static func parse(_ text: String) -> ParsedDuration? {
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
