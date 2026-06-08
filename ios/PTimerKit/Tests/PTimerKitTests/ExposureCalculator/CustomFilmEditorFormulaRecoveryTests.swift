import XCTest
import PTimerKit

/// PTIMER-84 follow-up: covers the Reset Formula / Revert Formula
/// recovery action. Reset (New flow) restores the safe-default
/// snapshot; Revert (Edit flow) restores the editor's opening
/// snapshot. Both must leave identity / source / notes / reference
/// URL untouched.
final class CustomFilmEditorFormulaRecoveryTests: XCTestCase {

    // MARK: - Safe-default snapshot shape

    func test_resetDefaultsSnapshot_matchesSpec() {
        let defaults = CustomFilmEditorFormState.resetDefaultsFormulaSnapshot
        XCTAssertEqual(defaults.formulaInputMode, .basic)
        XCTAssertEqual(defaults.exponentText, "1.30")
        XCTAssertEqual(defaults.baseTmText, "1")
        XCTAssertEqual(defaults.baseTcText, "1")
        XCTAssertEqual(defaults.offsetSecondsText, "")
        XCTAssertEqual(defaults.noCorrectionThroughText, "1")
        XCTAssertEqual(defaults.validThroughText, "")
    }

    // MARK: - New-flow Reset Formula

    func test_resetFormula_restoresSafeDefaults_andPreservesIdentity() {
        var form = CustomFilmEditorFormState(
            filmLabel: "GP3",
            isoText: "100",
            sourceType: .communityReference,
            notes: "Self-measured at f/8",
            formulaInputMode: .advanced,
            exponentText: "2.5",
            baseTmText: "0.1",
            baseTcText: "0.5",
            offsetSecondsText: "-0.3",
            noCorrectionThroughText: "0.5",
            validThroughText: "500",
            manufacturerText: "Shanghai",
            referenceURLText: "https://example.com/gp3"
        )

        form = form.applyingFormulaSnapshot(.init(
            formulaInputMode: .basic,
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        ))

        // Formula-related fields recover to safe defaults.
        XCTAssertEqual(form.formulaInputMode, .basic)
        XCTAssertEqual(form.exponentText, "1.30")
        XCTAssertEqual(form.baseTmText, "1")
        XCTAssertEqual(form.baseTcText, "1")
        XCTAssertEqual(form.offsetSecondsText, "")
        XCTAssertEqual(form.noCorrectionThroughText, "1")
        XCTAssertEqual(form.validThroughText, "")

        // Identity / source / notes / reference URL preserved.
        XCTAssertEqual(form.filmLabel, "GP3")
        XCTAssertEqual(form.isoText, "100")
        XCTAssertEqual(form.sourceType, .communityReference)
        XCTAssertEqual(form.notes, "Self-measured at f/8")
        XCTAssertEqual(form.manufacturerText, "Shanghai")
        XCTAssertEqual(form.referenceURLText, "https://example.com/gp3")
    }

    // MARK: - Edit-flow Revert Formula

    func test_revertFormula_restoresOpeningSnapshot_andPreservesIdentity() {
        // Simulate the editor opening on an existing T-MAX 100
        // style anchored profile.
        let opening = CustomFilmEditorFormState(
            filmLabel: "T-MAX 100",
            isoText: "100",
            sourceType: .personalTest,
            notes: "Stop bath at 1 min",
            formulaInputMode: .scaled,
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: "",
            manufacturerText: "Kodak",
            referenceURLText: "https://kodak.example/tmax100"
        )
        let snapshot = opening.formulaSnapshot

        // The photographer experiments — switches mode, tweaks
        // every formula field, and edits identity / notes too.
        var working = opening
        working = working.switching(to: .advanced)
        working.exponentText = "1.9"
        working.baseTmText = "0.05"
        working.baseTcText = "0.2"
        working.offsetSecondsText = "1"
        working.noCorrectionThroughText = "0.5"
        working.validThroughText = "60"
        working.notes = "Edited mid-session"
        working.filmLabel = "TMX (tweaked)"

        // Revert restores only the formula fields.
        working = working.applyingFormulaSnapshot(snapshot)

        XCTAssertEqual(working.formulaInputMode, .scaled)
        XCTAssertEqual(working.exponentText, "1.0966")
        XCTAssertEqual(working.baseTmText, "0.1")
        XCTAssertEqual(working.baseTcText, "0.1")
        XCTAssertEqual(working.offsetSecondsText, "")
        XCTAssertEqual(working.noCorrectionThroughText, "1")
        XCTAssertEqual(working.validThroughText, "")

        // Identity-side changes the user made survive the revert.
        XCTAssertEqual(working.notes, "Edited mid-session")
        XCTAssertEqual(working.filmLabel, "TMX (tweaked)")
        XCTAssertEqual(working.sourceType, .personalTest)
        XCTAssertEqual(working.manufacturerText, "Kodak")
        XCTAssertEqual(working.referenceURLText, "https://kodak.example/tmax100")
    }

    // MARK: - Mode switch + revert composition

    func test_revertFormula_recoversFormulaInputModeAfterModeSwitch() {
        // Opening state is Scaled (a T-MAX style profile).
        let opening = CustomFilmEditorFormState(
            filmLabel: "T-MAX 100",
            isoText: "100",
            formulaInputMode: .scaled,
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1"
        )
        let snapshot = opening.formulaSnapshot

        // The user flips to Basic — which resets anchors to 1.
        var working = opening.switching(to: .basic)
        XCTAssertEqual(working.formulaInputMode, .basic)
        XCTAssertEqual(working.baseTmText, "1")

        // Revert restores both the mode and the anchor pair.
        working = working.applyingFormulaSnapshot(snapshot)
        XCTAssertEqual(working.formulaInputMode, .scaled)
        XCTAssertEqual(working.baseTmText, "0.1")
        XCTAssertEqual(working.baseTcText, "0.1")
        XCTAssertEqual(working.exponentText, "1.0966")
    }
}
