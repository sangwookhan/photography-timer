// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-84 polish: covers
/// `CustomFilmEditorFormState.formulaExpressionSummary()`. The
/// rendered string drives the Formula card's live current-value
/// line and the field-sheet formula display, so the photographer
/// reads the same expression for the same form state across the
/// editor — and every term of the anchored shape is always
/// represented, either as a value or as a symbol placeholder.
final class CustomFilmEditorFormulaSummaryTests: XCTestCase {

    /// formulaExpressionSummary() renders the full anchored shape for a
    /// range of form states; each form -> exact rendered string is a
    /// case row (neutral, scaled, sub-second, offset, and the symbol
    /// fallbacks for unparseable anchors/offset).
    func test_formulaSummary_rendersExpectedStringPerFormState() {
        struct Case {
            let name: String
            let build: () -> CustomFilmEditorFormState
            let expected: String
        }
        let cases: [Case] = [
            Case(name: "neutral defaults", build: {
                CustomFilmEditorFormState(exponentText: "1.30", baseTmText: "1", baseTcText: "1", offsetSecondsText: "")
            }, expected: "Tc = 1s × (Tm / 1s)^1.3 + 0s"),
            Case(name: "scaled values", build: {
                CustomFilmEditorFormState(exponentText: "1.29", baseTmText: "2", baseTcText: "3", offsetSecondsText: "")
            }, expected: "Tc = 3s × (Tm / 2s)^1.29 + 0s"),
            Case(name: "sub-second anchors", build: {
                CustomFilmEditorFormState(exponentText: "1.0966", baseTmText: "0.1", baseTcText: "0.1")
            }, expected: "Tc = 0.1s × (Tm / 0.1s)^1.0966 + 0s"),
            Case(name: "positive offset", build: {
                CustomFilmEditorFormState(exponentText: "1.30", baseTmText: "3", baseTcText: "10", offsetSecondsText: "0.3")
            }, expected: "Tc = 10s × (Tm / 3s)^1.3 + 0.3s"),
            Case(name: "unparseable anchors fall back to symbols", build: {
                CustomFilmEditorFormState(exponentText: "1.30", baseTmText: "abc", baseTcText: "xyz")
            }, expected: "Tc = Tc₀ × (Tm / Tm₀)^1.3 + 0s"),
            Case(name: "unparseable offset falls back to symbol b", build: {
                CustomFilmEditorFormState(exponentText: "1.30", baseTmText: "1", baseTcText: "1", offsetSecondsText: "garbage")
            }, expected: "Tc = 1s × (Tm / 1s)^1.3 + b"),
        ]
        for c in cases {
            XCTAssertEqual(c.build().formulaExpressionSummary(), c.expected, "[\(c.name)]")
        }
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
