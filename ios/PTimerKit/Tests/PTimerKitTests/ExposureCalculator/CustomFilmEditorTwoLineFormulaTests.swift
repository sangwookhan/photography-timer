import XCTest
import PTimerKit

/// PTIMER-84 polish: covers the two-line formula display in the
/// Formula card — the symbolic structure line (always the full
/// anchored shape, regardless of which terms happen to be at
/// neutral defaults) plus the live current-value line (rendered
/// as the matching numeric expression with symbol placeholders
/// for missing slots).
final class CustomFilmEditorTwoLineFormulaTests: XCTestCase {

    func test_structureText_isAlwaysTheFullAnchoredShape() {
        // The editor no longer surfaces a mode selector; the
        // structure line shows the full anchored equation so the
        // six rows below map 1:1 onto its terms.
        let expected = "Tc = Tc₀ × (Tm / Tm₀)^p + b"
        XCTAssertEqual(
            CustomFilmEditorFormState().formulaStructureText(),
            expected
        )
        XCTAssertEqual(
            CustomFilmEditorFormState(formulaInputMode: .basic).formulaStructureText(),
            expected
        )
        XCTAssertEqual(
            CustomFilmEditorFormState(formulaInputMode: .scaled).formulaStructureText(),
            expected
        )
        XCTAssertEqual(
            CustomFilmEditorFormState(formulaInputMode: .advanced).formulaStructureText(),
            expected
        )
    }

    /// The current-value line renders the anchored numeric expression
    /// per form state, with symbol placeholders for missing/unparseable
    /// slots; the descriptive word "exponent" never appears (the row is
    /// labelled `p`). Each form -> expected line is a case row.
    func test_currentLine_rendersExpectedExpressionPerFormState() {
        struct Case {
            let name: String
            let build: () -> CustomFilmEditorFormState
            let expected: String
        }
        let cases: [Case] = [
            Case(name: "neutral", build: {
                CustomFilmEditorFormState(filmLabel: "Neutral", isoText: "100", exponentText: "1.30", baseTmText: "1", baseTcText: "1", offsetSecondsText: "", noCorrectionThroughText: "1", validThroughText: "")
            }, expected: "= 1s × (Tm / 1s)^1.3 + 0s"),
            Case(name: "scaled", build: {
                CustomFilmEditorFormState(filmLabel: "Scaled", isoText: "100", exponentText: "1.29", baseTmText: "2", baseTcText: "3", offsetSecondsText: "", noCorrectionThroughText: "1", validThroughText: "")
            }, expected: "= 3s × (Tm / 2s)^1.29 + 0s"),
            Case(name: "offset segment", build: {
                CustomFilmEditorFormState(filmLabel: "Advanced", isoText: "100", exponentText: "1.36", baseTmText: "0.5", baseTcText: "2", offsetSecondsText: "0.5", noCorrectionThroughText: "1", validThroughText: "")
            }, expected: "= 2s × (Tm / 0.5s)^1.36 + 0.5s"),
            Case(name: "missing exponent -> ^p", build: {
                CustomFilmEditorFormState(filmLabel: "MidEdit", isoText: "100", exponentText: "", baseTmText: "2", baseTcText: "3")
            }, expected: "= 3s × (Tm / 2s)^p + 0s"),
            Case(name: "unparseable anchors -> symbols", build: {
                CustomFilmEditorFormState(filmLabel: "Anchors", isoText: "100", exponentText: "1.30", baseTmText: "abc", baseTcText: "xyz")
            }, expected: "= Tc₀ × (Tm / Tm₀)^1.3 + 0s"),
            Case(name: "unparseable offset -> b", build: {
                CustomFilmEditorFormState(filmLabel: "Offset", isoText: "100", exponentText: "1.30", baseTmText: "1", baseTcText: "1", offsetSecondsText: "garbage")
            }, expected: "= 1s × (Tm / 1s)^1.3 + b"),
        ]
        for c in cases {
            let line = c.build().formulaCurrentLineText()
            XCTAssertEqual(line, c.expected, "[\(c.name)]")
            XCTAssertFalse(line.contains("exponent"), "[\(c.name)] must use symbol p, not the word exponent")
        }
    }

}
