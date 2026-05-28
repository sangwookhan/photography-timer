import XCTest
@testable import PTimer

/// PTIMER-84 polish: covers the formula token model the Formula
/// card now uses as its editing surface. The four formula terms
/// (`Tc₀`, `Tm₀`, `p`, `b`) render as inline tappable pills
/// inside the equation; tests pin the token order, the symbol /
/// edit-field mapping, the placeholder vs. value-present
/// distinction, and the invalid highlighting for the shortens-
/// exposure cross-field guard.
final class CustomFilmEditorFormulaTokenTests: XCTestCase {

    // MARK: - Order and identity

    func test_tokenOrder_matchesFormulaLeftToRight() {
        // Tokens must iterate in formula order so the view can
        // render them inline without re-sorting; tests can also
        // assert on the order independently of the view layer.
        XCTAssertEqual(
            CustomFilmEditorFormState.FormulaTokenSlot.allCases,
            [.tcAnchor, .tmAnchor, .exponent, .offset]
        )
    }

    func test_tokenSymbols_useFormulaVocabulary() {
        XCTAssertEqual(CustomFilmEditorFormState.FormulaTokenSlot.tcAnchor.symbol, "Tc₀")
        XCTAssertEqual(CustomFilmEditorFormState.FormulaTokenSlot.tmAnchor.symbol, "Tm₀")
        XCTAssertEqual(CustomFilmEditorFormState.FormulaTokenSlot.exponent.symbol, "p")
        XCTAssertEqual(CustomFilmEditorFormState.FormulaTokenSlot.offset.symbol, "b")
    }

    func test_tokenTap_opensMatchingFieldSheet() {
        // The token's `editField` mapping drives the editor view's
        // `.sheet(item:)` modal. Each formula term must route to
        // exactly its own field sheet; the range fields (No
        // correction / Source data) deliberately do NOT appear
        // among formula tokens.
        XCTAssertEqual(
            CustomFilmEditorFormState.FormulaTokenSlot.tcAnchor.editField,
            .correctedAtReference
        )
        XCTAssertEqual(
            CustomFilmEditorFormState.FormulaTokenSlot.tmAnchor.editField,
            .referenceTm
        )
        XCTAssertEqual(
            CustomFilmEditorFormState.FormulaTokenSlot.exponent.editField,
            .exponent
        )
        XCTAssertEqual(
            CustomFilmEditorFormState.FormulaTokenSlot.offset.editField,
            .offset
        )
    }

    func test_rangeFieldsAreNotFormulaTokens() {
        // The user-facing model says No correction / Source data
        // are not formula terms. Their edit-field cases must not
        // be reachable from any token slot.
        let tokenFields = CustomFilmEditorFormState.FormulaTokenSlot.allCases
            .map(\.editField)
        XCTAssertFalse(tokenFields.contains(.noCorrectionThrough))
        XCTAssertFalse(tokenFields.contains(.sourceRangeThrough))
        XCTAssertFalse(tokenFields.contains(.label))
        XCTAssertFalse(tokenFields.contains(.iso))
        XCTAssertFalse(tokenFields.contains(.manufacturer))
    }

    // MARK: - Display text + placeholder state

    func test_displays_neutralDefaults_renderNeutralLabelsAsPlaceholders() {
        // Untouched form: anchors blank → `1s` neutral default,
        // exponent blank → symbol `p`, offset blank → `0s`. All
        // four tokens read as placeholders so the view can dim
        // them.
        let form = CustomFilmEditorFormState()
        let displays = form.formulaTokenDisplays()
        XCTAssertEqual(displays.map(\.slot), [.tcAnchor, .tmAnchor, .exponent, .offset])
        XCTAssertEqual(displays[0].displayText, "1s")
        XCTAssertTrue(displays[0].isPlaceholder)
        XCTAssertEqual(displays[1].displayText, "1s")
        XCTAssertTrue(displays[1].isPlaceholder)
        XCTAssertEqual(displays[2].displayText, "p")
        XCTAssertTrue(displays[2].isPlaceholder)
        XCTAssertEqual(displays[3].displayText, "0s")
        XCTAssertTrue(displays[3].isPlaceholder)
    }

    func test_displays_filledValues_renderUnitsAndDropPlaceholderFlag() {
        let form = CustomFilmEditorFormState(
            filmLabel: "Filled",
            isoText: "100",
            exponentText: "1.29",
            baseTmText: "2",
            baseTcText: "3",
            offsetSecondsText: "0.5"
        )
        let displays = form.formulaTokenDisplays()
        XCTAssertEqual(displays[0].displayText, "3s")
        XCTAssertFalse(displays[0].isPlaceholder)
        XCTAssertEqual(displays[1].displayText, "2s")
        XCTAssertFalse(displays[1].isPlaceholder)
        XCTAssertEqual(displays[2].displayText, "1.29")
        XCTAssertFalse(displays[2].isPlaceholder)
        XCTAssertEqual(displays[3].displayText, "0.5s")
        XCTAssertFalse(displays[3].isPlaceholder)
    }

    func test_displays_subSecondAnchor_trimsTrailingZeros() {
        // Cross-surface vocabulary parity with the Calculation
        // Basis text: `0.1s`, not `0.10s`.
        let form = CustomFilmEditorFormState(
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1"
        )
        let displays = form.formulaTokenDisplays()
        XCTAssertEqual(displays[0].displayText, "0.1s")
        XCTAssertEqual(displays[1].displayText, "0.1s")
    }

    func test_displays_negativeOffset_rendersWithMinusGlyph() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "3",
            baseTcText: "10",
            offsetSecondsText: "-0.5"
        )
        let display = form.formulaTokenDisplay(
            for: CustomFilmEditorFormState.FormulaTokenSlot.offset
        )
        XCTAssertEqual(display.displayText, "−0.5s")
        XCTAssertFalse(display.isPlaceholder)
        XCTAssertFalse(display.displayText.contains("+"))
    }

    func test_displays_unparseableExponent_echoesUserTextNotSymbol() {
        // Mid-edit input that does not parse: the photographer
        // should still see what they typed so they can correct
        // it; the invalid flag does the visual highlighting.
        let form = CustomFilmEditorFormState(
            filmLabel: "Mid",
            isoText: "100",
            exponentText: "abc"
        )
        let display = form.formulaTokenDisplay(
            for: CustomFilmEditorFormState.FormulaTokenSlot.exponent
        )
        XCTAssertEqual(display.displayText, "abc")
        XCTAssertTrue(display.isInvalid)
    }

    // MARK: - Invalid highlighting

    func test_invalidFlag_setsForBothAnchors_whenShortensExposureGuardFails() {
        // The shortens-exposure cross-field guard fires when
        // Tc₀ < Tm₀; both anchor tokens get the invalid flag so
        // the photographer can see which pair is broken at a
        // glance without reading the recovery caption first.
        let form = CustomFilmEditorFormState(
            filmLabel: "Shorten",
            isoText: "100",
            exponentText: "1.30",
            baseTmText: "2",
            baseTcText: "1"
        )
        let displays = form.formulaTokenDisplays()
        XCTAssertTrue(displays[0].isInvalid, "Tc₀ token should flag invalid")
        XCTAssertTrue(displays[1].isInvalid, "Tm₀ token should flag invalid")
        XCTAssertFalse(displays[2].isInvalid, "p is independently valid")
        XCTAssertFalse(displays[3].isInvalid, "b is independently valid")
    }

    func test_invalidFlag_setsForSingleField_onPerFieldErrors() {
        let form = CustomFilmEditorFormState(
            filmLabel: "Just p",
            isoText: "100",
            exponentText: "abc"
        )
        let displays = form.formulaTokenDisplays()
        XCTAssertFalse(displays[0].isInvalid)
        XCTAssertFalse(displays[1].isInvalid)
        XCTAssertTrue(displays[2].isInvalid)
        XCTAssertFalse(displays[3].isInvalid)
    }
}
