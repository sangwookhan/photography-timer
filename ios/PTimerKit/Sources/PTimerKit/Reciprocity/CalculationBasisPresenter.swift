// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Pure-value presenter that produces the photographer-facing
/// **Calculation basis** wording rendered between the reciprocity
/// graph and the textual interpretation (preview checkpoint table
/// in the editor, custom-profile metadata in Details).
///
/// The presenter is intentionally named after the concept rather
/// than its current implementation: today the only profiles that
/// expose a calculation basis are formula-based custom profiles,
/// so the rendered string is always a single equation. Future
/// graph types (table-derived, fitted, piecewise) will surface
/// their own basis here without forcing a callsite rename.
///
/// `nil` means "no calculation basis to display" — callers omit
/// the block entirely rather than rendering a placeholder.
public enum CalculationBasisPresenter {

    /// Renders the formula directly. Single entry point routed
    /// through `FormulaEquationFormatter.userFacingText` so the
    /// editor preview, the Details surface, and any future
    /// surface read the exact same string for the same model.
    public static func calculationBasisText(for formula: ReciprocityFormula) -> String {
        return FormulaEquationFormatter.userFacingText(for: formula)
    }

    /// Resolves the first formula rule on the profile and renders
    /// its equation text. Returns `nil` when the profile carries
    /// no formula rule — limited-guidance / threshold-only
    /// profiles have no equation-shaped basis to display.
    public static func calculationBasisText(for profile: ReciprocityProfile) -> String? {
        for rule in profile.rules {
            if case let .formula(formulaRule) = rule {
                return calculationBasisText(for: formulaRule.formula)
            }
        }
        return nil
    }

    /// Editor-preview convenience: parses the photographer's
    /// in-progress form into a `ReciprocityFormula` and renders
    /// the calculation-basis text. Returns `nil` when the form
    /// cannot be parsed, in which case the preview surface
    /// suppresses the Calculation Basis block (the unparseable
    /// state already has its own recovery panel inside the
    /// Preview card).
    public static func calculationBasisText(for form: CustomFilmEditorFormState) -> String? {
        guard let formula = form.parsedReciprocityFormula() else { return nil }
        return calculationBasisText(for: formula)
    }
}
