import XCTest
@testable import PTimer

/// PTIMER-84 polish: covers
/// `CustomFilmEditorFormState.formulaExpressionSummary()`. The
/// rendered string drives the Formula card's live current-value
/// line and the field-sheet formula display, so the photographer
/// reads the same expression for the same form state across the
/// editor — and every term of the anchored shape is always
/// represented, either as a value or as a symbol placeholder.
final class CustomFilmEditorFormulaSummaryTests: XCTestCase {

    // MARK: - Full anchored shape

    func test_neutralDefaults_renderEverySlot() {
        // Neutral values do NOT collapse out of the editor
        // summary; the row labels below stay mapped 1:1 onto the
        // visible tokens.
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: ""
        )
        XCTAssertEqual(
            form.formulaExpressionSummary(),
            "Tc = 1s × (Tm / 1s)^1.3 + 0s"
        )
    }

    func test_scaledValues_renderWithUnits() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.29",
            baseTmText: "2",
            baseTcText: "3",
            offsetSecondsText: ""
        )
        XCTAssertEqual(
            form.formulaExpressionSummary(),
            "Tc = 3s × (Tm / 2s)^1.29 + 0s"
        )
    }

    func test_subSecondAnchors_renderFractionalSecondLabel() {
        // T-MAX 100 style anchored profile. The Formula card's
        // current line trims trailing zeros so its sub-second
        // tokens match the `FormulaEquationFormatter` vocabulary
        // used by the Calculation Basis surface — `0.1s`, not
        // `0.10s` — so the two surfaces never disagree on the
        // rendered token for the same value.
        let form = CustomFilmEditorFormState(
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1"
        )
        XCTAssertEqual(
            form.formulaExpressionSummary(),
            "Tc = 0.1s × (Tm / 0.1s)^1.0966 + 0s"
        )
    }

    // MARK: - Offset segment

    func test_positiveOffset_appendsPlusSegment() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "3",
            baseTcText: "10",
            offsetSecondsText: "0.3"
        )
        XCTAssertEqual(
            form.formulaExpressionSummary(),
            "Tc = 10s × (Tm / 3s)^1.3 + 0.3s"
        )
    }

    func test_negativeOffset_rendersWithMinusSign() {
        // Negative offsets are model-legal when paired with a
        // sufficiently large baseTc. The summary reads as
        // `... − Ns` instead of `... + -Ns` so the expression
        // stays mathematically familiar.
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "3",
            baseTcText: "10",
            offsetSecondsText: "-0.5"
        )
        let rendered = form.formulaExpressionSummary()
        XCTAssertTrue(
            rendered.contains("− 0.5s"),
            "Expected minus-segment in: \(rendered)"
        )
        XCTAssertFalse(
            rendered.contains("+ -"),
            "Negative offset must not render as `+ -...`."
        )
    }

    // MARK: - Symbol placeholders for missing values

    func test_blankExponent_fallsBackToSymbolP() {
        // The photographer-visible row is labelled `p`, so the
        // mid-edit placeholder must also read `p` — never the
        // descriptive word `exponent`, which does not match any
        // row label.
        let form = CustomFilmEditorFormState()
        let summary = form.formulaExpressionSummary()
        XCTAssertTrue(summary.contains("^p "), "Expected `^p` slot in: \(summary)")
        XCTAssertFalse(summary.contains("exponent"))
    }

    func test_unparseableAnchors_fallBackToTheirSymbols() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "abc",
            baseTcText: "xyz"
        )
        XCTAssertEqual(
            form.formulaExpressionSummary(),
            "Tc = Tc₀ × (Tm / Tm₀)^1.3 + 0s"
        )
    }

    func test_unparseableOffset_fallsBackToSymbolB() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "garbage"
        )
        XCTAssertEqual(
            form.formulaExpressionSummary(),
            "Tc = 1s × (Tm / 1s)^1.3 + b"
        )
    }

    // MARK: - Live updates

    func test_summary_updatesWhenExponentChanges() {
        var form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1"
        )
        XCTAssertEqual(
            form.formulaExpressionSummary(),
            "Tc = 1s × (Tm / 1s)^1.3 + 0s"
        )
        form.exponentText = "1.45"
        XCTAssertEqual(
            form.formulaExpressionSummary(),
            "Tc = 1s × (Tm / 1s)^1.45 + 0s"
        )
    }

    func test_summary_modeAgnostic_alwaysShowsAnchoredShape() {
        // The editor no longer surfaces a mode selector; the
        // rendered shape stays the same across every internal
        // `formulaInputMode` value so the Formula card structure
        // line and current line always line up.
        let scaled = CustomFilmEditorFormState(
            formulaInputMode: .scaled,
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1"
        )
        let advanced = CustomFilmEditorFormState(
            formulaInputMode: .advanced,
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1"
        )
        XCTAssertEqual(
            scaled.formulaExpressionSummary(),
            advanced.formulaExpressionSummary()
        )
    }
}
