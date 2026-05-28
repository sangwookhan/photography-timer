import XCTest
@testable import PTimer

/// PTIMER-84 polish: Reset Formula and Revert Formula are now
/// two distinct affordances. Reset always replaces the formula
/// fields with the documented neutral starter values regardless
/// of whether the editor is in the New or Edit flow. Revert only
/// makes sense in the Edit flow, where it restores the formula
/// the editor was opened with.
///
/// The view-level button visibility is exercised manually (no
/// view harness yet); this test class pins the snapshot value
/// contract and the round-trip behavior of the underlying
/// `applyingFormulaSnapshot(_:)` helper that drives both actions.
final class CustomFilmEditorResetRevertTests: XCTestCase {

    // MARK: - Neutral starter contract

    func test_resetDefaultsSnapshot_carriesDocumentedNeutralValues() {
        // Spec: Tc₀ = 1s, Tm₀ = 1s, p = 1.30, b = 0s,
        // No correction = 1s, Source data = Unlimited.
        let snapshot = CustomFilmEditorFormState.resetDefaultsFormulaSnapshot
        XCTAssertEqual(snapshot.exponentText, "1.30")
        XCTAssertEqual(snapshot.baseTmText, "1")
        XCTAssertEqual(snapshot.baseTcText, "1")
        XCTAssertEqual(snapshot.offsetSecondsText, "")
        XCTAssertEqual(snapshot.noCorrectionThroughText, "1")
        XCTAssertEqual(snapshot.validThroughText, "")
    }

    func test_applyResetSnapshot_overwritesAllFormulaFields() {
        // Starting from arbitrary user-typed values, applying
        // the reset snapshot must restore every formula field —
        // not just the ones a particular mode used to surface.
        let working = CustomFilmEditorFormState(
            filmLabel: "WIP",
            isoText: "200",
            exponentText: "abc",
            baseTmText: "5",
            baseTcText: "12",
            offsetSecondsText: "0.5",
            noCorrectionThroughText: "3",
            validThroughText: "60",
            manufacturerText: "ADOX"
        )
        let reset = working.applyingFormulaSnapshot(
            CustomFilmEditorFormState.resetDefaultsFormulaSnapshot
        )
        XCTAssertEqual(reset.exponentText, "1.30")
        XCTAssertEqual(reset.baseTmText, "1")
        XCTAssertEqual(reset.baseTcText, "1")
        XCTAssertEqual(reset.offsetSecondsText, "")
        XCTAssertEqual(reset.noCorrectionThroughText, "1")
        XCTAssertEqual(reset.validThroughText, "")
        // Identity / metadata fields are preserved — Reset only
        // touches the formula fields, never the photographer's
        // identity work.
        XCTAssertEqual(reset.filmLabel, "WIP")
        XCTAssertEqual(reset.isoText, "200")
        XCTAssertEqual(reset.manufacturerText, "ADOX")
    }

    // MARK: - Reset vs Revert routing

    func test_resetThenRevert_inEditFlow_restoresOpeningSnapshot() {
        // Edit flow contract: the editor captures an opening
        // snapshot at init time. Reset replaces formula fields
        // with the neutral defaults; a subsequent Revert restores
        // the saved values from that opening snapshot. Both
        // operations preserve identity / metadata fields.
        let opening = CustomFilmEditorFormState(
            filmLabel: "Saved",
            isoText: "100",
            exponentText: "1.45",
            baseTmText: "2",
            baseTcText: "3",
            offsetSecondsText: "0.5",
            noCorrectionThroughText: "1",
            validThroughText: "120"
        )
        let openingSnapshot = opening.formulaSnapshot

        // Reset replaces formula fields with neutral defaults.
        let resetted = opening.applyingFormulaSnapshot(
            CustomFilmEditorFormState.resetDefaultsFormulaSnapshot
        )
        XCTAssertEqual(resetted.exponentText, "1.30")
        XCTAssertEqual(resetted.baseTcText, "1")
        XCTAssertEqual(resetted.validThroughText, "")
        XCTAssertEqual(resetted.filmLabel, "Saved")

        // Revert from the reset state must restore every formula
        // field to the opening snapshot — proving Reset did not
        // clobber the snapshot.
        let reverted = resetted.applyingFormulaSnapshot(openingSnapshot)
        XCTAssertEqual(reverted.exponentText, "1.45")
        XCTAssertEqual(reverted.baseTmText, "2")
        XCTAssertEqual(reverted.baseTcText, "3")
        XCTAssertEqual(reverted.offsetSecondsText, "0.5")
        XCTAssertEqual(reverted.noCorrectionThroughText, "1")
        XCTAssertEqual(reverted.validThroughText, "120")
        XCTAssertEqual(reverted.filmLabel, "Saved")
    }

    func test_revertFromUntouchedNewFlow_isAnIdentityOnFormulaFields() {
        // New flow has no opening snapshot; the view hides the
        // Revert button. The model-level contract is that
        // applying a state's own snapshot to itself is a no-op
        // on formula fields — confirming a future caller that
        // accidentally routes Revert in the New flow would not
        // corrupt the form.
        let blank = CustomFilmEditorFormState()
        let echoed = blank.applyingFormulaSnapshot(blank.formulaSnapshot)
        XCTAssertEqual(echoed.exponentText, blank.exponentText)
        XCTAssertEqual(echoed.baseTmText, blank.baseTmText)
        XCTAssertEqual(echoed.baseTcText, blank.baseTcText)
        XCTAssertEqual(echoed.offsetSecondsText, blank.offsetSecondsText)
        XCTAssertEqual(echoed.noCorrectionThroughText, blank.noCorrectionThroughText)
        XCTAssertEqual(echoed.validThroughText, blank.validThroughText)
    }
}
