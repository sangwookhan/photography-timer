import Foundation

/// Renders the user-facing equation text shown next to a formula
/// graph. Pure value formatter: no state, callers reach the
/// entry point through the static method.
enum FormulaEquationFormatter {

    /// Returns the human-readable equation text for `formula`.
    /// Substitutes the profile-published equation's `P` placeholder
    /// with the rendered exponent when present; otherwise falls
    /// back to the verbatim equation, or to `Tc = Tm^<exponent>`
    /// when the profile carries no equation text.
    static func userFacingText(for formula: ReciprocityFormula) -> String {
        let formattedExponent = formatExponent(formula.exponent)

        switch formula.kind {
        case .exponentPower:
            if let equation = normalizedDetailText(formula.equation) {
                if let substitutedEquation = substitutePlaceholder(
                    in: equation,
                    placeholder: "P",
                    replacement: formattedExponent
                ) {
                    return substitutedEquation
                }
                // Profiles whose equation does not parameterize the
                // exponent (e.g. constant-multiplier forms) render
                // verbatim. Falling through to "Tc = Tm^N" here would
                // misrepresent a formula like "Tc = √2 × Tm" as
                // "Tc = Tm^1".
                return equation
            }

            return "Tc = Tm^\(formattedExponent)"
        }
    }

    private static func substitutePlaceholder(
        in equation: String,
        placeholder: String,
        replacement: String
    ) -> String? {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: placeholder) + "\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(equation.startIndex..., in: equation)
        guard regex.firstMatch(in: equation, range: range) != nil else {
            return nil
        }

        return regex.stringByReplacingMatches(
            in: equation,
            range: range,
            withTemplate: replacement
        )
    }

    /// Formats an exponent with up to four decimal digits so
    /// graph-displayed equations preserve the published precision
    /// (e.g. Provia 100F's `1.3676`). Compact decimals — like
    /// HP5 Plus's `1.31` — stay short because trailing zeros are
    /// stripped by `minimumFractionDigits = 0`.
    private static func formatExponent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }

    private static func normalizedDetailText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
