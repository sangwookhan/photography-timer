import Foundation

/// Renders the user-facing equation text shown next to a formula
/// graph for the shared guarded formula model.
///
/// Modified Schwarzschild display form:
///
/// ```
/// Tc = a × (Tm / Tref)^p + b
/// ```
///
/// - `a` is the scale coefficient (always rendered as a numeric
///   multiplier — never confused with `p`).
/// - Neutral values are omitted so simple formulas stay compact:
///   - `a = 1`      → drop the leading `a ×`.
///   - `Tref = 1s`  → drop the `(Tm / Tref)` rescaling, render `Tm`.
///   - `b = 0s`     → drop the trailing `+ b`.
///   - `p = 1`      → drop the `^1` exponent (constant-multiplier
///     form like `Tc = 1.4142 × Tm`).
///
/// Examples:
///
/// ```
/// Tc = Tm^1.31
/// Tc = 2.2457 × Tm^1.4515
/// Tc = 2 × (Tm / 10s)^1.45
/// Tc = 2 × (Tm / 10s)^1.45 + 0.3s
/// ```
enum FormulaEquationFormatter {

    static func userFacingText(for formula: ReciprocityFormula) -> String {
        // Exhaustive switch on the formula family. PTIMER-162's
        // `.kronHalmContinuous` family will need its own display
        // surface; the compiler enforces that addition rather than
        // silently rendering a Kron-Halm formula with Modified
        // Schwarzschild syntax.
        switch formula.formulaFamily {
        case .modifiedSchwarzschild:
            return modifiedSchwarzschildText(for: formula)
        }
    }

    private static func modifiedSchwarzschildText(for formula: ReciprocityFormula) -> String {
        // `coefficient` here is the scale coefficient `a` from the
        // Modified Schwarzschild display form — never the exponent
        // `p`. The two are kept verbally distinct so a future custom
        // editor cannot mislabel one as the other.
        let scaleCoefficient = formula.coefficientSeconds
        let reference = formula.referenceMeteredTimeSeconds
        let exponent = formula.exponent
        let offset = formula.offsetSeconds

        let exponentText = formatNumber(exponent)

        let baseToken: String
        if isNeutralReference(reference) {
            baseToken = "Tm"
        } else {
            baseToken = "(Tm / \(formatSecondsValue(reference)))"
        }

        let poweredTerm: String
        if isNeutralExponent(exponent) {
            // `Tm^1` adds visual noise without information; drop it
            // so constant-multiplier formulas (e.g. `Tc = √2 × Tm`)
            // render cleanly.
            poweredTerm = baseToken
        } else {
            poweredTerm = "\(baseToken)^\(exponentText)"
        }

        var rightHandSide = poweredTerm
        if !isNeutralCoefficient(scaleCoefficient) {
            rightHandSide = "\(formatNumber(scaleCoefficient)) × \(poweredTerm)"
        }
        if !isNeutralOffset(offset) {
            let sign = offset >= 0 ? "+" : "-"
            rightHandSide += " \(sign) \(formatSecondsValue(abs(offset)))"
        }
        return "Tc = \(rightHandSide)"
    }

    // MARK: - Neutral-value detection

    /// Tolerance used when deciding whether a published value lands
    /// on its neutral default. Catalogs commonly store the neutral
    /// values as exact integers (1 for coefficient and reference, 0
    /// for offset); the tolerance covers a future custom-profile
    /// editor that snaps to slider increments without sacrificing the
    /// exact equality check on stored values.
    private static let neutralValueTolerance: Double = 1e-9

    private static func isNeutralCoefficient(_ value: Double) -> Bool {
        abs(value - 1) <= neutralValueTolerance
    }

    private static func isNeutralReference(_ value: Double) -> Bool {
        abs(value - 1) <= neutralValueTolerance
    }

    private static func isNeutralOffset(_ value: Double) -> Bool {
        abs(value) <= neutralValueTolerance
    }

    private static func isNeutralExponent(_ value: Double) -> Bool {
        abs(value - 1) <= neutralValueTolerance
    }

    // MARK: - Number formatting

    /// Formats a coefficient / exponent value with up to four
    /// fractional digits so published precision is preserved
    /// (`1.4515`, `1.3676`), trimming trailing zeros for compact
    /// formulas (`1.31`).
    private static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%g", value)
    }

    /// Formats a value that represents a seconds quantity (`Tref`,
    /// offset) by appending the `s` unit. Whole seconds render as
    /// `10s`; fractional values render with the same precision as
    /// `formatNumber`.
    private static func formatSecondsValue(_ value: Double) -> String {
        "\(formatNumber(value))s"
    }
}
