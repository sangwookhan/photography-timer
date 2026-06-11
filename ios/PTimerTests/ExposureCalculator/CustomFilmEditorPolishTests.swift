import XCTest
@testable import PTimerKit
import PTimerCore
@testable import PTimer

/// PTIMER-84 pre-smoke polish suite. Covers four small policy
/// changes:
///
/// 1. Compact row duration values render with seconds/minutes
///    units, not bare numbers.
/// 2. Formula card top summary and shared Calculation Basis agree
///    on coefficient units when the formula is anchored.
/// 3. Editor preview hides the graph (and falls through to the
///    recovery panel) when the formula passes parse but fails the
///    shorten-exposure guard, so the user never sees a misleading
///    curve plus a row pile-up of "Invalid formula result".
/// 4. Common ISO chip list now exposes 320 (and surrounding box
///    speeds) at a stable order.
final class CustomFilmEditorPolishTests: XCTestCase {

    /// rowDurationDisplayValue maps each raw input to its rendered
    /// row text and placeholder flag (seconds/minutes/sub-second units,
    /// empty -> placeholder, unparseable -> echo, and the Unlimited
    /// token honoured or echoed per allowsUnlimited). Each input ->
    /// expected is a case row.
    func test_rowDurationDisplayValue_rendersExpectedTextPerInput() {
        struct Case {
            let name: String
            let input: String
            let placeholder: String
            let allowsUnlimited: Bool
            let expectedText: String
            let expectedPlaceholder: Bool?
        }
        let cases: [Case] = [
            Case(name: "seconds", input: "2", placeholder: "1s", allowsUnlimited: false, expectedText: "2s", expectedPlaceholder: false),
            Case(name: "minutes", input: "200", placeholder: "1s", allowsUnlimited: false, expectedText: "3.3m", expectedPlaceholder: false),
            Case(name: "sub-second leading zero", input: "0.5", placeholder: "0s", allowsUnlimited: false, expectedText: "0.50s", expectedPlaceholder: nil),
            Case(name: "empty -> placeholder", input: "", placeholder: "1s", allowsUnlimited: false, expectedText: "1s", expectedPlaceholder: true),
            Case(name: "unparseable echoes raw text", input: "abc", placeholder: "1s", allowsUnlimited: false, expectedText: "abc", expectedPlaceholder: false),
            Case(name: "unlimited token when allowed", input: "Unlimited", placeholder: "Unlimited", allowsUnlimited: true, expectedText: "Unlimited", expectedPlaceholder: false),
            Case(name: "anchor row echoes unlimited (not allowed)", input: "Unlimited", placeholder: "1s", allowsUnlimited: false, expectedText: "Unlimited", expectedPlaceholder: nil),
        ]
        for c in cases {
            let value = rowDurationDisplayValue(c.input, placeholder: c.placeholder, allowsUnlimited: c.allowsUnlimited)
            XCTAssertEqual(value.text, c.expectedText, "[\(c.name)] text")
            if let expectedPlaceholder = c.expectedPlaceholder {
                XCTAssertEqual(value.isPlaceholder, expectedPlaceholder, "[\(c.name)] placeholder")
            }
        }
    }

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

    func test_advancedFormula_positiveOffset_rendersWithPlusSegment() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 10,
            referenceMeteredTimeSeconds: 3,
            exponent: 1.30,
            offsetSeconds: 0.3,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(
            FormulaEquationFormatter.userFacingText(for: formula),
            "Tc = 10s × (Tm / 3s)^1.3 + 0.3s"
        )
    }

    func test_advancedFormula_negativeOffset_rendersWithMinusSegment() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 10,
            referenceMeteredTimeSeconds: 3,
            exponent: 1.30,
            offsetSeconds: -0.3,
            noCorrectionThroughSeconds: 1
        )
        // The formatter prints `-` (ASCII) for negative offsets.
        // The leading space before the operator stays so the
        // expression reads as `... - 0.3s`.
        XCTAssertEqual(
            FormulaEquationFormatter.userFacingText(for: formula),
            "Tc = 10s × (Tm / 3s)^1.3 - 0.3s"
        )
    }

    // MARK: - Exponent superscript scope

    func test_formulaExpressionSplitter_offsetSuffixStaysAtBaseline() {
        // Splitter must stop the exponent token at the first
        // whitespace, so the trailing ` + 0.3s` renders at the
        // normal text baseline instead of bleeding into the
        // superscript.
        guard let parts = FilmModeDetailsFormulaExpressionText.split(
            "Tc = 10s × (Tm / 3s)^1.3 + 0.3s"
        ) else {
            return XCTFail("Splitter must accept anchored formula with offset.")
        }
        XCTAssertEqual(parts.base, "Tc = 10s × (Tm / 3s)")
        XCTAssertEqual(parts.exponent, "1.3")
        XCTAssertEqual(parts.remainder, " + 0.3s")
    }

    func test_formulaExpressionSplitter_endingWithExponent_hasEmptyRemainder() {
        guard let parts = FilmModeDetailsFormulaExpressionText.split(
            "Tc = Tm^1.31"
        ) else {
            return XCTFail("Splitter must accept the simplified shape.")
        }
        XCTAssertEqual(parts.base, "Tc = Tm")
        XCTAssertEqual(parts.exponent, "1.31")
        XCTAssertEqual(parts.remainder, "")
    }

    func test_formulaExpressionSplitter_noCaret_returnsNil() {
        XCTAssertNil(
            FilmModeDetailsFormulaExpressionText.split("Tc = Tm"),
            "Splitter must return nil for plain (no-caret) expressions so the caller can render the raw string."
        )
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

    // MARK: - ISO chip list

    func test_commonISOs_includes320_atStablePosition() {
        // The user noticed ISO 320 could not be chosen from chips.
        // Pin the order so a future expansion does not silently
        // regress the layout.
        XCTAssertEqual(
            customFilmEditorCommonISOs,
            [
                "6", "12", "20", "25", "50", "64", "80", "100", "125",
                "160", "200", "250", "320", "400", "500", "640", "800",
                "1000", "1250", "1600", "3200",
            ]
        )
        XCTAssertTrue(customFilmEditorCommonISOs.contains("320"))
    }
}
