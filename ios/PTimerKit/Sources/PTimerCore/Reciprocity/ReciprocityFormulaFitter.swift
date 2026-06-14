import Foundation

/// PTIMER-179 runtime fit of a narrow two-parameter power law
/// `Tc = a × Tm^p` to a set of reciprocity table anchors, by free
/// least-squares in log–log space.
///
/// This is the production home of the fit previously implemented
/// only inside `AppDerivedFormulaEvaluationTests.freeLogLogFit`: the
/// same closed-form ordinary least squares on `(ln Tm, ln Tc)`. It is
/// deterministic, Foundation-only, and has no dependency on UI, the
/// exposure calculator, the timer runtime, or persistence. The
/// PTIMER-170 evaluation fixture continues to recompute its decisions
/// from the catalog anchors independently; this type does not change
/// that contract.
///
/// The fit deliberately omits the `offsetSeconds` (`b`) and reference
/// (`Tref`) degrees of freedom of the shared `ReciprocityFormula`:
/// every shipped app-derived alternate uses this `b = 0`, `Tref = 1`
/// power-law shape, and offset fitting was intentionally left for a
/// later formula family (PTIMER-170 follow-up). Mapping the result
/// into the guarded formula shape is the caller's responsibility.
public enum ReciprocityFormulaFitter {

    /// Fitted two-parameter power law `Tc = coefficient × Tm^exponent`.
    public struct PowerLawFit: Equatable {
        /// Scale coefficient `a`. Maps to `coefficientSeconds` with
        /// `referenceMeteredTimeSeconds = 1`, `offsetSeconds = 0`.
        public let coefficient: Double
        /// Exponent `p`.
        public let exponent: Double

        public init(coefficient: Double, exponent: Double) {
            self.coefficient = coefficient
            self.exponent = exponent
        }
    }

    /// Why a fit could not be produced. The fit is a pure function of
    /// the anchors, so every failure is an input property — never a
    /// transient runtime condition.
    public enum UnavailableReason: Error, Equatable {
        /// Fewer than two anchors were supplied; a power law needs at
        /// least two points.
        case insufficientAnchors
        /// An anchor carried a non-finite or non-positive metered or
        /// corrected time, so its logarithm is undefined.
        case nonPositiveAnchors
        /// Every anchor shares the same metered time, so the log–log
        /// slope is indeterminate (zero denominator). Cannot arise for
        /// a validated `TableInterpolationReciprocityRule` (its
        /// anchors are strictly ascending) but guarded for raw input.
        case degenerateAnchors
        /// The closed-form solution produced a non-finite coefficient
        /// or exponent.
        case nonFiniteResult
    }

    /// Fits `Tc = a × Tm^p` to `anchors` by ordinary least squares on
    /// `(ln Tm, ln Tc)`. Returns the fitted parameters or the reason
    /// no fit is defined. Never throws and never crashes on bad input.
    public static func fit(
        anchors: [TableAnchor]
    ) -> Result<PowerLawFit, UnavailableReason> {
        guard anchors.count >= 2 else {
            return .failure(.insufficientAnchors)
        }
        for anchor in anchors {
            guard anchor.meteredSeconds.isFinite, anchor.meteredSeconds > 0,
                  anchor.correctedSeconds.isFinite, anchor.correctedSeconds > 0 else {
                return .failure(.nonPositiveAnchors)
            }
        }

        let xs = anchors.map { log($0.meteredSeconds) }
        let ys = anchors.map { log($0.correctedSeconds) }
        let n = Double(anchors.count)
        let sx = xs.reduce(0, +)
        let sy = ys.reduce(0, +)
        let sxx = xs.map { $0 * $0 }.reduce(0, +)
        let sxy = zip(xs, ys).map(*).reduce(0, +)

        let denominator = n * sxx - sx * sx
        guard abs(denominator) > .ulpOfOne else {
            return .failure(.degenerateAnchors)
        }
        let exponent = (n * sxy - sx * sy) / denominator
        let coefficient = exp((sy - exponent * sx) / n)

        guard exponent.isFinite, coefficient.isFinite else {
            return .failure(.nonFiniteResult)
        }
        return .success(PowerLawFit(coefficient: coefficient, exponent: exponent))
    }
}
