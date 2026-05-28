import XCTest
@testable import PTimer

/// PTIMER-84 polish: covers the two-line formula display in the
/// Formula card — the symbolic structure line (always the full
/// anchored shape, regardless of which terms happen to be at
/// neutral defaults) plus the live current-value line (rendered
/// as the matching numeric expression with symbol placeholders
/// for missing slots).
final class CustomFilmEditorTwoLineFormulaTests: XCTestCase {

    // MARK: - Structure text is mode-agnostic

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

    // MARK: - Current line — every slot rendered

    func test_currentLine_neutralValues_renderInFullAnchoredShape() {
        // Even when every formula term equals its neutral default
        // (Tc₀=1s, Tm₀=1s, b=0s), the current line still spells
        // out the full anchored shape so the row labels below
        // remain mapped to visible tokens. The editor view
        // de-emphasizes the row values themselves; the line text
        // does not collapse.
        let form = CustomFilmEditorFormState(
            filmLabel: "Neutral",
            isoText: "100",
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertEqual(form.formulaCurrentLineText(), "= 1s × (Tm / 1s)^1.3 + 0s")
    }

    func test_currentLine_scaledValues_renderWithUnits() {
        let form = CustomFilmEditorFormState(
            filmLabel: "Scaled",
            isoText: "100",
            exponentText: "1.29",
            baseTmText: "2",
            baseTcText: "3",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertEqual(form.formulaCurrentLineText(), "= 3s × (Tm / 2s)^1.29 + 0s")
    }

    func test_currentLine_includesOffsetSegment() {
        let form = CustomFilmEditorFormState(
            filmLabel: "Advanced",
            isoText: "100",
            exponentText: "1.36",
            baseTmText: "0.5",
            baseTcText: "2",
            offsetSecondsText: "0.5",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertEqual(
            form.formulaCurrentLineText(),
            "= 2s × (Tm / 0.5s)^1.36 + 0.5s"
        )
    }

    // MARK: - Mid-edit token placeholders

    func test_currentLine_missingExponent_fallsBackToSymbolP() {
        // Empty `p` must NOT render as the descriptive word
        // `exponent` (the previous wording was misleading because
        // there is no editor row labelled "exponent"). The
        // photographer-visible row is `p`, so the placeholder
        // is the symbol `p` too.
        let form = CustomFilmEditorFormState(
            filmLabel: "MidEdit",
            isoText: "100",
            exponentText: "",
            baseTmText: "2",
            baseTcText: "3"
        )
        let line = form.formulaCurrentLineText()
        XCTAssertEqual(line, "= 3s × (Tm / 2s)^p + 0s")
        XCTAssertFalse(line.contains("exponent"))
    }

    func test_currentLine_unparseableAnchors_fallBackToTheirSymbols() {
        let form = CustomFilmEditorFormState(
            filmLabel: "Anchors",
            isoText: "100",
            exponentText: "1.30",
            baseTmText: "abc",
            baseTcText: "xyz"
        )
        let line = form.formulaCurrentLineText()
        XCTAssertEqual(line, "= Tc₀ × (Tm / Tm₀)^1.3 + 0s")
        XCTAssertFalse(line.contains("exponent"))
    }

    func test_currentLine_unparseableOffset_fallsBackToSymbolB() {
        let form = CustomFilmEditorFormState(
            filmLabel: "Offset",
            isoText: "100",
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "garbage"
        )
        XCTAssertEqual(
            form.formulaCurrentLineText(),
            "= 1s × (Tm / 1s)^1.3 + b"
        )
    }
}
