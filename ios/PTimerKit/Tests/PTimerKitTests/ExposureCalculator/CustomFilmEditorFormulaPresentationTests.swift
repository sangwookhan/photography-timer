// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit
import PTimerCore

/// Custom-film editor formula presentation: form-state summary vs
/// Calculation Basis agreement, neutral/offset formatter output, the
/// exponent-scope splitter, and preview gating. Pure Kit form-state /
/// formatter logic, so it runs off-simulator. The app-view row-duration
/// and ISO-chip helpers stay in `CustomFilmEditorPolishTests`.
final class CustomFilmEditorFormulaPresentationTests: XCTestCase {

    // MARK: - Formula card top summary ↔ Calculation Basis agreement

    func test_anchoredFormula_summaryAndBasis_agreeOnCoefficientUnits() {
        // The Formula card current line always renders the full
        // anchored shape (every slot visible) so the row labels
        // below have a matching token, while the Calculation
        // Basis surface collapses neutral defaults to a compact
        // saved-form expression. They differ on optional segments
        // but must agree on every non-neutral slot — coefficient,
        // anchor, and exponent — including the seconds suffix on
        // an anchored coefficient.
        let form = CustomFilmEditorFormState(
            filmLabel: "Polish",
            isoText: "100",
            exponentText: "1.29",
            baseTmText: "2",
            baseTcText: "3",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        let topSummary = form.formulaExpressionSummary()
        let basis = CalculationBasisPresenter.calculationBasisText(for: form)
        XCTAssertEqual(topSummary, "Tc = 3s × (Tm / 2s)^1.29 + 0s")
        XCTAssertEqual(basis, "Tc = 3s × (Tm / 2s)^1.29")
        // Shared core: both render the anchored coefficient with
        // seconds units so the photographer never reads `3` and
        // `3s` for the same value.
        XCTAssertTrue(topSummary.contains("3s × (Tm / 2s)^1.29"))
        XCTAssertTrue((basis ?? "").contains("3s × (Tm / 2s)^1.29"))
    }

    func test_neutralReferenceFormula_basisDropsCoefficientSuffix() {
        // Preset / neutral-reference shape: coefficient is a pure
        // multiplier (no anchor), so the seconds suffix would
        // mislead. The formatter renders without `s`.
        let formula = ReciprocityFormula(
            coefficientSeconds: 1.4142,
            exponent: 1.45,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(
            FormulaEquationFormatter.userFacingText(for: formula),
            "Tc = 1.4142 × Tm^1.45"
        )
    }

    // MARK: - Advanced offset rendering

    func test_advancedFormula_signedOffset_rendersWithSignedSegment() {
        // The formatter appends a signed seconds segment for a non-zero
        // offset, printing ASCII `+` / `-` with a leading space so the
        // expression reads as `... + 0.3s` / `... - 0.3s`.
        struct Case {
            let name: String
            let offsetSeconds: Double
            let expected: String
        }
        let cases: [Case] = [
            Case(name: "positive offset", offsetSeconds: 0.3, expected: "Tc = 10s × (Tm / 3s)^1.3 + 0.3s"),
            Case(name: "negative offset", offsetSeconds: -0.3, expected: "Tc = 10s × (Tm / 3s)^1.3 - 0.3s"),
        ]
        for c in cases {
            let formula = ReciprocityFormula(
                coefficientSeconds: 10,
                referenceMeteredTimeSeconds: 3,
                exponent: 1.30,
                offsetSeconds: c.offsetSeconds,
                noCorrectionThroughSeconds: 1
            )
            XCTAssertEqual(
                FormulaEquationFormatter.userFacingText(for: formula),
                c.expected,
                "[\(c.name)]"
            )
        }
    }

    // MARK: - Exponent superscript scope

    func test_formulaExpressionSplitter_scopesExponentTokenPerInput() {
        // The splitter stops the exponent token at the first whitespace
        // (so a trailing ` + 0.3s` renders at the baseline, not in the
        // superscript), yields an empty remainder when the expression
        // ends on the exponent, and returns nil for a plain no-caret
        // string so the caller renders it raw. Each input -> expected
        // is a case row.
        struct ExpectedParts {
            let base: String
            let exponent: String
            let remainder: String
        }
        struct Case {
            let name: String
            let input: String
            let expected: ExpectedParts?
        }
        let cases: [Case] = [
            Case(
                name: "offset suffix stays at baseline",
                input: "Tc = 10s × (Tm / 3s)^1.3 + 0.3s",
                expected: ExpectedParts(base: "Tc = 10s × (Tm / 3s)", exponent: "1.3", remainder: " + 0.3s")
            ),
            Case(
                name: "ending with exponent has empty remainder",
                input: "Tc = Tm^1.31",
                expected: ExpectedParts(base: "Tc = Tm", exponent: "1.31", remainder: "")
            ),
            Case(name: "no caret returns nil", input: "Tc = Tm", expected: nil),
        ]
        for c in cases {
            let parts = FilmModeDetailsFormulaExpressionText.split(c.input)
            guard let expected = c.expected else {
                XCTAssertNil(parts, "[\(c.name)] splitter must return nil")
                continue
            }
            guard let parts else {
                XCTFail("[\(c.name)] splitter must accept the input")
                continue
            }
            XCTAssertEqual(parts.base, expected.base, "[\(c.name)] base")
            XCTAssertEqual(parts.exponent, expected.exponent, "[\(c.name)] exponent")
            XCTAssertEqual(parts.remainder, expected.remainder, "[\(c.name)] remainder")
        }
    }

    // MARK: - Preview gating

    func test_formulaCanRenderPreview_validForm_isTrue() {
        let form = CustomFilmEditorFormState(
            filmLabel: "Polish",
            isoText: "100",
            formulaInputMode: .basic,
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertTrue(form.formulaCanRenderPreview)
    }

    func test_formulaCanRenderPreview_unparseableForm_isFalse() {
        let form = CustomFilmEditorFormState(exponentText: "abc")
        XCTAssertFalse(form.formulaCanRenderPreview)
    }

    func test_formulaCanRenderPreview_shortensExposure_isFalse() {
        // Anchor pair that would emit Tc < Tm; the form parses
        // cleanly but the stabilization guard rejects it. The
        // preview gating must treat the form as non-renderable
        // so the recovery panel surfaces the shortening reason
        // rather than the table pile-up of `.invalidFormulaResult`.
        var form = CustomFilmEditorFormState(
            filmLabel: "Shorten",
            isoText: "100",
            formulaInputMode: .scaled,
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "0.01",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertNotNil(form.parsedReciprocityFormula())
        XCTAssertFalse(form.formulaCanRenderPreview)

        // The cross-field recovery message reads as a compact
        // formula constraint (`Tc₀ must be ≥ Tm₀`) plus the
        // current values (`Current: 0.01s < 1s`). See
        // `CustomFilmEditorSaveDisabledReasonTests` for the
        // wording contract.
        let reason = form.saveDisabledReason(isEditing: false)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("Tc₀ must be ≥ Tm₀") == true)
        XCTAssertTrue(reason?.contains("Current: 0.01s < 1s") == true)

        // Sanity: the helper does not vanish for the identity-only
        // failure case (Save disabled but formula portion is fine).
        form.baseTcText = "1"
        form.filmLabel = ""
        XCTAssertTrue(form.formulaCanRenderPreview)
    }
}
